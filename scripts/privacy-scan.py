#!/usr/bin/env python3
"""Blocks pushes that would publish the owner's private values.

Patterns come from Config/private-patterns.txt (git-ignored): one literal per line, '#' starts a comment.
Each literal is searched case-insensitively as text, as hex (with and without spaces) and as base64,
in every file being pushed (binary files too, so image metadata is covered) and in commit messages.

  privacy-scan.py              scan tracked and new, not ignored, files in the working tree
  privacy-scan.py --pre-push   scan the commits git is about to push (stdin of the pre-push hook)
  privacy-scan.py --self-test  check the encodings
"""
import base64
import os
import subprocess
import sys

ZERO = "0" * 40


def root():
    return subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True,
                          check=True).stdout.strip()


def git(*args):
    return subprocess.run(["git", "-C", root(), *args], capture_output=True, check=True).stdout


def b64_cores(raw):
    """Base64 text that appears whatever the literal's alignment inside the encoded data."""
    cores = set()
    for pad in range(3):
        encoded = base64.b64encode(b"\0" * pad + raw)
        start = (pad * 8 + 5) // 6           # first char not touched by the bytes before the literal
        end = ((pad + len(raw)) * 8) // 6    # chars after this depend on the bytes after the literal
        core = encoded[start:end]
        if len(core) >= 6:
            cores.add(core.lower())  # data is lowercased before matching; this can only add matches
    return cores


def needles(literal):
    """Every byte string that would reveal the literal, mapped to a masked label for the report."""
    label = literal[:2] + "…"
    found = {}
    for variant in {literal, literal.lower(), literal.upper()}:
        raw = variant.encode()
        found[raw.lower()] = f"{label} (text)"
        hexed = raw.hex()
        found[hexed.encode()] = f"{label} (hex)"
        found[" ".join(hexed[i:i + 2] for i in range(0, len(hexed), 2)).encode()] = f"{label} (hex)"
        for core in b64_cores(raw):
            found[core] = f"{label} (base64)"
    return found


def load_table():
    path = os.path.join(root(), "Config", "private-patterns.txt")
    if not os.path.exists(path):
        sys.exit(f"privacy-scan: {path} is missing. Create it (one private value per line) before pushing.")
    table = {}
    with open(path, encoding="utf-8") as patterns:
        for line in patterns:
            literal = line.strip()
            if literal and not literal.startswith("#"):
                table.update(needles(literal))
    if not table:
        sys.exit(f"privacy-scan: {path} has no patterns. Add one private value per line before pushing.")
    return table


def worktree_blobs():
    top = root()
    names = git("ls-files", "-z", "--cached", "--others", "--exclude-standard").decode().split("\0")
    for name in filter(None, names):
        path = os.path.join(top, name)
        if os.path.isfile(path):
            with open(path, "rb") as handle:
                yield name, handle.read()


def pushed_blobs(lines):
    for line in lines:
        parts = line.split()
        if len(parts) != 4 or parts[1] == ZERO:  # malformed, or deleting a remote branch
            continue
        local_sha, remote_sha = parts[1], parts[3]
        try:
            commits = git("rev-list", f"{remote_sha}..{local_sha}") if remote_sha != ZERO else None
        except subprocess.CalledProcessError:
            commits = None
        if commits is None:
            commits = git("rev-list", local_sha, "--not", "--remotes")
        for commit in commits.decode().split():
            yield f"commit {commit[:8]} (message and author)", git("log", "-1", "--format=%an %ae%n%cn %ce%n%B", commit)
            raw = git("diff-tree", "-r", "-m", "--root", "--no-commit-id", "--raw", commit).decode()
            for entry in filter(None, raw.split("\n")):
                meta, path = entry.split("\t", 1)
                new_sha = meta.split()[3]
                if new_sha != ZERO:
                    yield f"{path} in {commit[:8]}", git("cat-file", "blob", new_sha)


def scan(blobs, table):
    hits = set()
    for name, data in blobs:
        lowered = data.lower()
        for needle, what in table.items():
            if needle in lowered:
                hits.add(f"{name}: {what}")
    return sorted(hits)


def self_test():
    literal = "Example Name"
    table = needles(literal)
    raw = literal.encode()
    samples = [b"x " + raw + b" y", literal.upper().encode(), raw.hex().upper().encode(),
               " ".join(f"{b:02X}" for b in raw).encode(), literal.lower().encode().hex().encode(),
               base64.b64encode(literal.upper().encode())]
    samples += [base64.b64encode(prefix + raw + b"tail") for prefix in (b"", b"a", b"ab")]
    for sample in samples:
        assert any(needle in sample.lower() for needle in table), sample
    assert not any(needle in b"nothing private here" for needle in table)
    print("privacy-scan self-test passed")


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
        sys.exit(0)
    table = load_table()
    blobs = pushed_blobs(sys.stdin) if "--pre-push" in sys.argv else worktree_blobs()
    found = scan(blobs, table)
    if found:
        print("privacy-scan: private values found, push blocked:", *found, sep="\n  ")
        sys.exit(1)
    print("privacy-scan: clean")
