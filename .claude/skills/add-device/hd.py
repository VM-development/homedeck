#!/usr/bin/env python3
"""HomeDeck's device loop in three commands. Standard library only; run from anywhere in the repo or a worktree.

  hd.py new <id> --kit <Name> --name "<Display name>" --symbol <sf-symbol> --link bluetooth|wifi \\
            --category fitness|music|climate|cleaning|kitchen|other [--apk <file.apk|file.xapk>]
      Creates the kit (device.json, Catalog.swift), its test target, the app's device class and screen,
      the Package.swift and DeviceRegistry lines, and docs/devices/<id>/{journal,protocol}.md.
      With --apk: copies the app into research/<id>/apk/, unpacks it and dexdumps every classes*.dex.

  hd.py phone [--phone <udid>]
      Builds, installs and launches HomeDeck on the connected iPhone. Prints only errors and the result.

  hd.py log <id> [--phone <udid>]
      Pulls the connection log off the phone into research/<id>/logs/ and prints that device's lines, masked.

The phone's identifier is never printed or written to a file.
"""
import argparse
import datetime
import importlib.util
import json
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
BUNDLE_ID = "local.homedeck.app"
CATEGORIES = ["fitness", "music", "climate", "cleaning", "kitchen", "other"]


def fail(message):
    sys.exit(f"hd: {message}")


def run(*cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, **kw)


# MARK: new

def new(a):
    if not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", a.id):
        fail("the id is lowercase words joined by '-', like walkingpad-c2")
    if not re.fullmatch(r"[A-Z][A-Za-z0-9]*", a.kit):
        fail("--kit is one capitalised word, like WalkingPad (the kit becomes WalkingPadKit)")
    kit = f"{a.kit}Kit"
    src, tests, app = ROOT / f"Packages/Sources/{kit}", ROOT / f"Packages/Tests/{kit}Tests", ROOT / f"App/Devices/{a.kit}"
    for path in (src, tests, app):
        if path.exists():
            fail(f"{path.relative_to(ROOT)} already exists")
    for manifest in (ROOT / "Packages/Sources").glob("*/device.json"):
        if json.loads(manifest.read_text())["id"] == a.id:
            fail(f"{manifest.relative_to(ROOT)} already uses the id {a.id}")

    device = {"id": a.id, "name": a.name, "symbol": a.symbol, "link": a.link, "category": a.category}
    write(src / "device.json", "{\n" + "".join(f'  "{k}": {json.dumps(v)},\n' for k, v in device.items()) + '  "features": []\n}\n')
    write(src / "Catalog.swift", f"""import Foundation

public enum {a.kit}Catalog {{
    /// This device's device.json: what Home and the Market show about it.
    public static let manifest = Bundle.module.url(forResource: "device", withExtension: "json")!
}}
""")
    write(tests / f"{kit}Tests.swift", f"""import XCTest
@testable import {kit}

final class {kit}Tests: XCTestCase {{
    func testDeviceJSONIsBundled() {{
        XCTAssertTrue(FileManager.default.fileExists(atPath: {a.kit}Catalog.manifest.path))
    }}
}}
""")
    write(app / f"{a.kit}Device.swift", f"""import HubCore
import SwiftUI
import {kit}

/// {a.name}. What it speaks: docs/devices/{a.id}/protocol.md.
@MainActor
@Observable
final class {a.kit}Device: HomeDevice {{
    static let id = "{a.id}"

    private(set) var status: DeviceStatus = .notSetUp
    @ObservationIgnored let log = ConnectionLog.shared.tagged({a.kit}Device.id)

    func makeScreen() -> AnyView {{ AnyView({a.kit}Screen(device: self)) }}
}}
""")
    write(app / f"{a.kit}Screen.swift", f"""import HubCore
import SwiftUI

struct {a.kit}Screen: View {{
    let device: {a.kit}Device

    var body: some View {{
        GlassScreen {{
            DeviceHeader(symbol: "{a.symbol}", title: "{a.name}", subtitle: device.status.cardLine)
        }}
        .navigationTitle("{a.name}")
    }}
}}
""")

    package = ROOT / "Packages/Package.swift"
    text = package.read_text()
    text = re.sub(r"(let kits = \[[^\]]*)\]", lambda m: f'{m.group(1)}, "{kit}"]', text, count=1)
    text = text.replace('        .testTarget(name: "CatalogTests"',
                        f'        .testTarget(name: "{kit}Tests", dependencies: ["{kit}"]),\n        .testTarget(name: "CatalogTests"', 1)
    package.write_text(text)

    registry = ROOT / "App/DeviceRegistry.swift"
    text = registry.read_text()
    imports = list(re.finditer(r"^import \w+\n", text, re.M))
    text = text[:imports[-1].end()] + f"import {kit}\n" + text[imports[-1].end():]
    text = text.replace("    ]\n}", f"        DeviceKind(manifest: {a.kit}Catalog.manifest) {{ {a.kit}Device() }},\n    ]\n}}", 1)
    registry.write_text(text)

    for doc in ("journal", "protocol"):
        template = (ROOT / f"docs/templates/{doc}.md").read_text()
        write(ROOT / f"docs/devices/{a.id}/{doc}.md", template.replace("<Device>", a.name))

    print(f"Created {kit}, its tests, App/Devices/{a.kit}/, docs/devices/{a.id}/ and the Package.swift and registry lines.")
    if a.apk:
        unpack(Path(a.apk).expanduser(), ROOT / f"research/{a.id}")


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def unpack(apk, research):
    """Copies the vendor app in, unzips it and dexdumps its code. Nothing here is ever committed (research/ is ignored)."""
    if not apk.is_file():
        fail(f"no file at {apk}")
    folder = research / "apk"
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copy2(apk, folder / apk.name)
    base = folder / apk.name
    if apk.suffix == ".xapk":  # a zip of APKs: the base one is the largest that isn't a config split
        with zipfile.ZipFile(base) as z:
            z.extractall(folder / "x", [n for n in z.namelist() if n.endswith(".apk")])
        apks = [p for p in (folder / "x").rglob("*.apk") if not p.name.startswith("config.")]
        if not apks:
            fail(f"no base APK inside {apk.name}")
        base = max(apks, key=lambda p: p.stat().st_size)
    dex = research / "dex"
    dex.mkdir(exist_ok=True)
    with zipfile.ZipFile(base) as z:
        names = sorted(n for n in z.namelist() if re.fullmatch(r"classes\d*\.dex", n))
        z.extractall(dex, names)
    dexdump = find_dexdump()
    if not dexdump:
        print(f"Unpacked {len(names)} dex files into {dex.relative_to(ROOT)}; dexdump not found "
              "(install Android build-tools), so they aren't dumped.")
        return
    for name in names:
        with open(dex / f"{name}.txt", "w") as out:
            subprocess.run([str(dexdump), "-d", str(dex / name)], stdout=out, stderr=subprocess.DEVNULL)
    print(f"Unpacked {base.name} and dumped {len(names)} dex files into {dex.relative_to(ROOT)}/classes*.dex.txt; grep them.")


def find_dexdump():
    def version(p):
        return [int(x) if x.isdigit() else 0 for x in re.split(r"[.-]", p.parent.name)]
    found = sorted(Path.home().glob("Library/Android/sdk/build-tools/*/dexdump"), key=version)
    return found[-1] if found else shutil.which("dexdump")


# MARK: phone

def phone_id(given):
    if given:
        return given
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        if run("xcrun", "devicectl", "list", "devices", "--json-output", f.name).returncode != 0:
            fail("xcrun devicectl list devices failed; is Xcode installed?")
        devices = json.load(open(f.name))["result"]["devices"]
    phones = [d["hardwareProperties"]["udid"] for d in devices
              if d.get("hardwareProperties", {}).get("reality") == "physical"
              and d.get("hardwareProperties", {}).get("deviceType") == "iPhone"
              and d.get("connectionProperties", {}).get("tunnelState") == "connected"]
    if len(phones) != 1:
        fail(f"{len(phones)} connected iPhones. Connect one by cable and unlock it (a charge-only cable doesn't count), "
             "or pass --phone with its identifier.")
    return phones[0]


def phone(a):
    udid = phone_id(a.phone)
    copy_config()
    print("Building…", flush=True)
    build = run("xcodebuild", "-project", "HomeDeck.xcodeproj", "-scheme", "HomeDeck", "-destination", f"id={udid}",
                "-configuration", "Debug", "-derivedDataPath", "build/dd", "-allowProvisioningUpdates", "build")
    errors = sorted({line.strip() for line in build.stdout.splitlines() if "error:" in line})
    if build.returncode != 0:
        print("\n".join(errors[:20]) or build.stdout[-2000:])
        fail("BUILD FAILED")
    app = ROOT / "build/dd/Build/Products/Debug-iphoneos/HomeDeck.app"
    if run("xcrun", "devicectl", "device", "install", "app", "--device", udid, str(app)).returncode != 0:
        fail("install failed; is the phone unlocked?")
    if run("xcrun", "devicectl", "device", "process", "launch", "--terminate-existing", "--device", udid, BUNDLE_ID).returncode != 0:
        fail("installed, but launch failed; unlock the phone and open HomeDeck")
    print("Built, installed and launched HomeDeck on the iPhone.")


def copy_config():
    """A worktree has no git-ignored config; it lives only in the main checkout."""
    listing = run("git", "worktree", "list", "--porcelain").stdout.splitlines()
    main = Path(listing[0].split(" ", 1)[1]) if listing else ROOT
    for name in ("Team.xcconfig", "Secrets.xcconfig"):
        target, source = ROOT / "Config" / name, main / "Config" / name
        if not target.exists() and source.exists():
            shutil.copy2(source, target)
            print(f"Copied Config/{name} from the main checkout (git-ignored; delete it before removing the worktree).")


# MARK: log

def log(a):
    udid = phone_id(a.phone)
    folder = ROOT / f"research/{a.id}/logs"
    folder.mkdir(parents=True, exist_ok=True)
    target = folder / f"{datetime.datetime.now():%Y%m%d-%H%M%S}.jsonl"
    copy = run("xcrun", "devicectl", "device", "copy", "from", "--device", udid, "--domain-type", "appDataContainer",
               "--domain-identifier", BUNDLE_ID, "--source", "Documents/connection-log.jsonl", "--destination", str(target))
    if copy.returncode != 0 or not target.exists():
        fail("couldn't copy the log; has HomeDeck run on this phone, and is the phone unlocked?")
    lines = []
    for raw in target.read_text().splitlines():
        try:
            entry = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if entry.get("device") == a.id:
            lines.append(f"{entry['date'][11:19]} {entry['text']}")
    masker = load_mask()
    sys.stdout.buffer.write(masker.mask("\n".join(lines).encode() + b"\n", masker.scan.load_table()))
    print(f"{len(lines)} lines for {a.id}; full log in {target.relative_to(ROOT)} (newest 500 lines of all devices).")


def load_mask():
    spec = importlib.util.spec_from_file_location("mask", Path(__file__).with_name("mask.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("new", help="start a new device")
    p.add_argument("id")
    p.add_argument("--kit", required=True)
    p.add_argument("--name", required=True)
    p.add_argument("--symbol", required=True)
    p.add_argument("--link", required=True, choices=["bluetooth", "wifi"])
    p.add_argument("--category", required=True, choices=CATEGORIES)
    p.add_argument("--apk")
    p.set_defaults(func=new)
    p = sub.add_parser("phone", help="build, install and launch on the iPhone")
    p.add_argument("--phone")
    p.set_defaults(func=phone)
    p = sub.add_parser("log", help="pull the connection log and show one device's lines")
    p.add_argument("id")
    p.add_argument("--phone")
    p.set_defaults(func=log)
    a = parser.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
