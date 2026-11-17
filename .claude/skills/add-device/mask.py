#!/usr/bin/env python3
"""Masks private values in text piped through it, so probe output and logs can be read in a session.

Masks every literal in the main checkout's Config/private-patterns.txt (in each encoding the privacy scan
knows: text, hex, base64, hex bytes in any order), home-network IPv4 addresses and MAC addresses.
The patterns file is never printed.

  <command> | python3 .claude/skills/add-device/mask.py
  python3 .claude/skills/add-device/mask.py < research/<id>/connection-log.jsonl
  python3 .claude/skills/add-device/mask.py --self-test
"""
import importlib.util
import re
import sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("privacy_scan", Path(__file__).resolve().parents[3] / "scripts" / "privacy-scan.py")
scan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scan)

IP = re.compile(rb"\b(?:10\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3})\.\d{1,3}\b")
MAC = re.compile(rb"\b[0-9a-f]{2}(?:[:-][0-9a-f]{2}){5}\b", re.I)


def mask(data, needles):
    lowered = data.lower()  # needles are lowercase, as in the privacy scan
    hidden = bytearray(len(data))
    for needle in needles:
        at = lowered.find(needle)
        while at != -1:
            hidden[at:at + len(needle)] = b"\1" * len(needle)
            at = lowered.find(needle, at + 1)
    out, i = bytearray(), 0
    while i < len(data):
        if hidden[i]:
            while i < len(data) and hidden[i]:
                i += 1
            out += b"<private>"
        else:
            out.append(data[i])
            i += 1
    return MAC.sub(b"<mac>", IP.sub(b"<ip>", bytes(out)))


def self_test():
    needles = scan.needles("Example Room")
    assert mask(b"room=Example Room ok", needles) == b"room=<private> ok"
    assert mask(b"snm=EXAMPLE ROOM", needles) == b"snm=<private>"
    assert b"<private>" in mask("Example Room".encode().hex().encode(), needles)
    assert mask(b"at 192.168.1.20:5683 and 10.0.0.7", {}) == b"at <ip>:5683 and <ip>"
    assert mask(b"mac AA:BB:CC:DD:EE:FF", {}) == b"mac <mac>"
    assert mask(b"host 224.0.1.187, frame f8a2040002", {}) == b"host 224.0.1.187, frame f8a2040002"
    print("mask self-test passed")


if __name__ == "__main__":
    if "--self-test" in sys.argv:
        self_test()
        sys.exit(0)
    table = scan.load_table()  # exits with the scan's own message if the patterns file is missing
    for line in sys.stdin.buffer:
        sys.stdout.buffer.write(mask(line, table))
        sys.stdout.buffer.flush()
