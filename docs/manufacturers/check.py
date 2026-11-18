#!/usr/bin/env python3
"""Check Open Local Control (OLC) files beyond their shape: byte templates, examples,
references and the security level. Usage: check.py <file.olc.json>...  (format.md)"""
import json, math, re, sys

FIELD = re.compile(r"\{(\w+):([ui](?:8|(?:16|24|32)(?:be|le)))(?:\*([0-9.]+))?\}")
CHECKSUM = re.compile(r"\{(sum8|xor8):(\d+)\}")


def tokens(template):
    """Each token as (kind, size, details)."""
    out = []
    for t in template.split():
        if re.fullmatch(r"[0-9A-Fa-f]{2}", t):
            out.append(("fixed", 1, int(t, 16)))
        elif t == "??":
            out.append(("any", 1, None))
        elif m := CHECKSUM.fullmatch(t):
            out.append((m[1], 1, int(m[2])))
        elif m := FIELD.fullmatch(t):
            name, kind, scale = m[1], m[2], float(m[3] or 1)
            size = 1 if kind[1:] == "8" else int(kind[1:-2]) // 8
            out.append(("field", size, (name, kind[0] == "i", "little" if kind.endswith("le") else "big", scale)))
        else:
            raise ValueError(f"unknown token {t!r}")
    return out


def decode(template, data):
    """The fields in `data`; raises if a fixed byte, checksum or the length is wrong."""
    fields, at = {}, 0
    for kind, size, d in tokens(template):
        chunk = data[at:at + size]
        if len(chunk) < size:
            raise ValueError("example is shorter than the template")
        if kind == "fixed" and chunk[0] != d:
            raise ValueError(f"byte {at} is {chunk[0]:02X}, template says {d:02X}")
        if kind in ("sum8", "xor8"):
            span, want = data[d:at], 0
            for b in span:
                want = (want + b) % 256 if kind == "sum8" else want ^ b
            if chunk[0] != want:
                raise ValueError(f"checksum at byte {at} is {chunk[0]:02X}, should be {want:02X}")
        if kind == "field":
            name, signed, order, scale = d
            fields[name] = int.from_bytes(chunk, order, signed=signed) * scale
        at += size
    if at != len(data):
        raise ValueError(f"example has {len(data)} bytes, template {at}")
    return fields


def pointer(doc, path):
    for part in path.split("/")[1:]:
        doc = doc[part.replace("~1", "/").replace("~0", "~")]
    return doc


def owner_key_gaps(f):
    """What keeps a file from owner-key, in words."""
    s, gaps = f["security"], []
    need = lambda ok, text: ok or gaps.append(text)
    need(s["key"]["unique"] == "per-device", f"key is {s['key']['unique']}: give every unit its own key")
    need(s["key"]["unique"] == "none" or s["key"]["from"] in ("device", "pairing"), f"key comes from {s['key']['from']}: let the owner get it from the device itself")
    need(s["pairing"] in ("ble-passkey", "ble-numeric-comparison", "ble-oob", "setup-code-pake"),
         f"pairing is {s['pairing']}: use a Bluetooth passkey, numeric comparison or out-of-band pairing, or a setup code with a PAKE")
    need(s["setupCode"] != "none", "no setup code: print one on the label or show it on the display")
    need(s["encryption"] != "none", "no encryption")
    need(s["integrity"] in ("keyed-hash", "aead"), f"integrity is {s['integrity']}: a stranger can change messages; use an AEAD cipher")
    need(s["freshness"] in ("counter", "nonce", "tls"), f"freshness is {s['freshness']}: old messages can be sent again")
    need(s["controllers"] == "many-revocable", f"controllers is {s['controllers']}: let the owner allow several apps and remove each one")
    need(s["worksOffline"], "local control needs the internet")
    for a in f.get("actions", []):
        need(not a["risky"] or a["id"] in s["buttonPressFor"], f"risky action {a['id']} runs without a button press on the device")
    for i in s["otherInterfaces"]:
        need(i["protection"] not in ("none", "unknown"), f"{i['what']}: protection is {i['protection']}")
    for l in f["links"]:
        need(l.get("certificate") in (None, "ca", "pinned-at-pairing"), f"link {l['id']} uses a {l.get('certificate')} certificate with nothing to check it against")
    need(s["disclosure"]["contact"], "no vulnerability contact")
    need(s["disclosure"]["supportUntil"], "no security support end date")
    return gaps


def level(f):
    key = f["security"]["key"]["unique"]
    if key == "none":
        return "open"
    if key == "per-model":
        return "shared-secret"
    return "per-device-key" if owner_key_gaps(f) else "owner-key"


def check(f):
    errors = []
    links, messages = {l["id"] for l in f["links"]}, f["messages"]
    actions = {a["id"] for a in f.get("actions", [])}
    for name, m in messages.items():
        if m["link"] not in links:
            errors.append(f"{name}: no link {m['link']!r}")
        if "reply" in m and m["reply"] not in messages:
            errors.append(f"{name}: no message {m['reply']!r}")
        for ex in m.get("examples", []):
            try:
                if "bytes" in m:
                    got = decode(m["bytes"], bytes.fromhex(ex["bytes"]))
                    for k, v in ex["fields"].items():
                        if k not in got or not math.isclose(got[k], v, abs_tol=1e-9):
                            errors.append(f"{name}: example decodes {k} as {got.get(k)}, says {v}")
                elif "json" in m:
                    for k, v in ex["fields"].items():
                        if pointer(ex["json"], m["fields"][k]) != v:
                            errors.append(f"{name}: example {k} isn't {v!r}")
            except (ValueError, KeyError, TypeError) as e:
                errors.append(f"{name}: {e}")
        if "bytes" in m:
            try:
                tokens(m["bytes"])
            except ValueError as e:
                errors.append(f"{name}: {e}")
    for p in f.get("properties", []):
        for use in ("read", "write"):
            if use not in p:
                continue
            m = messages.get(p[use])
            if m is None:
                errors.append(f"property {p['id']}: no message {p[use]!r}")
                continue
            try:
                carried = [d[0] for k, _, d in tokens(m["bytes"]) if k == "field"] if "bytes" in m else m.get("fields", {})
            except ValueError:
                carried = []
            if p["id"] not in carried:
                errors.append(f"property {p['id']}: message {p[use]} doesn't carry it")
    for a in f.get("actions", []):
        if a["send"] not in messages:
            errors.append(f"action {a['id']}: no message {a['send']!r}")
    for a in f["security"]["buttonPressFor"]:
        if a not in actions:
            errors.append(f"buttonPressFor: no action {a!r}")
    if f["security"]["level"] != level(f):
        errors.append(f"level says {f['security']['level']}, the keys say {level(f)}")
    return errors


if __name__ == "__main__":
    failed = False
    for path in sys.argv[1:]:
        with open(path) as fh:
            f = json.load(fh)
        errors = check(f)
        failed |= bool(errors)
        print(f"{path}: {'FAIL' if errors else 'ok'}, level {level(f)}")
        for e in errors:
            print(f"  error: {e}")
        for g in owner_key_gaps(f):
            print(f"  for owner-key: {g}")
    sys.exit(1 if failed else 0)
