# HomeDeck Phase 0 (the shell) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the HomeDeck iPhone app shell (device contract, Home, Market with feature lists, Settings with the shared log), move REX5 in as the first working device, add the six other devices as catalog entries, and set up the docs and privacy guard for the device sessions that follow.

**Architecture:** One Xcode project (`HomeDeck.xcodeproj`, synchronized folders `App`, `Widgets`, `Shared`) and one local Swift package (`Packages/`, product `HomeDeckKits`) with a `HubCore` target plus one target per device. Device protocol code lives in its package target and is tested with `swift test` on the Mac; device screens and the class that adapts a device to the `HomeDevice` contract live in `App/Devices/<Name>/`. REX5's code is copied from the REX5 repo and adapted, not rewritten.

**Tech Stack:** Swift 5 language mode, SwiftUI, Observation, CoreBluetooth, WidgetKit, App Intents, XCTest, Python 3 (stdlib only) for the privacy scan, Xcode 27.

**Spec:** `docs/superpowers/specs/2026-11-13-homedeck-design.md`. **REX5 source:** the REX5 repo checked out next to this one at `../rex5` (github.com/VM-development/noble-rex5-custom-app).

## Global Constraints

- App deployment target iOS 26.0; package platforms `.iOS(.v17), .macOS(.v14)` so `swift test` runs on the Mac.
- `swift-tools-version: 5.10`, Swift 5 language mode (matches the copied REX5 code).
- Bundle ID `local.homedeck.app`; widget extension `local.homedeck.app.widgets`; App Group `group.local.homedeck.app`.
- Design: plain `systemGroupedBackground`, `.clear` glass, no decorative gradients (reuse REX5's `Glass.swift`).
- No personal data in any committed file: no real names, device names, Bluetooth addresses, UDIDs, team ID, serial numbers, IP addresses, Wi-Fi names, home folder paths or personal emails. Use placeholders such as `<phone>` in docs and journals.
- Git-ignored, never committed: `research/`, `Config/Team.xcconfig`, `Config/private-patterns.txt`.
- Commit rule (spec, "Commit rule"): commits are allowed on branch `phase-0-shell`; creating `main`, merging into it, creating the GitHub repo and every push need the owner's explicit yes.
- Every task ends by appending an entry to `docs/journal/hub.md` in the journal format (Task 8 adds the template; Task 1 starts the file).
- Widget `configurationDisplayName` and `description` are string literals (a runtime-built name crashed REX5's widget extension).
- No emojis in files.

## Plan notes: refinements of the spec

These keep the spec's intent and were written back into the spec when this plan was written:

1. **One package, one target per device.** `Packages/Package.swift` holds `HubCore` and every `<Device>Kit` as targets of one package with one product, `HomeDeckKits`. Adding a device then only edits `Package.swift`, never the Xcode project file.
2. **Glass components stay in the app** (`App/UI/Glass.swift`): they use iOS 26 glass APIs, while the package stays at iOS 17 / macOS 14 for `swift test`.
3. **Device kits don't depend on HubCore.** Each kit exposes `<Name>Catalog.featuresURL`; `DeviceKind` decodes it.
4. **Keychain storage arrives with XiaomiCloudKit**, its first user (wave 1). Phase 0 stores no secrets.
5. **Remove from Home** is a long-press menu on the card (cards are not in a `List`, so there is no swipe).
6. **The privacy scan is `scripts/privacy-scan.py`**: hex and base64 variants are simpler and safer in Python than in shell.

## File structure

```
homedeck/
  .gitignore  LICENSE  README.md
  Config/Signing.xcconfig  Config/Team.xcconfig.example
  scripts/privacy-scan.py            privacy scan, worktree and pre-push modes, self-test
  hooks/pre-push                     runs the scan; enabled by core.hooksPath
  HomeDeck.xcodeproj/                copied from REX5's project and renamed
  App/
    HomeDeckApp.swift                app entry, tabs, deep links, notification routing
    DeviceRegistry.swift             one DeviceKind per device
    DashboardView.swift              Home tab and DeviceCard
    MarketView.swift                 Market tab, MarketTile, FeatureListView
    HubSettingsView.swift            Settings tab and LogView
    UI/Glass.swift                   REX5's glass components
    Devices/Rex5/                    REX5's service, link, screens, intent, adapter
    Info.plist  HomeDeck.entitlements  Assets.xcassets
  Widgets/                           REX5's widgets; HomeDeckWidgets.entitlements
  Shared/GlassStyle.swift            BatteryRing, used by app and widgets
  Packages/
    Package.swift
    Sources/HubCore/                 Catalog.swift Device.swift DeviceStore.swift FeatureChoices.swift FeatureGate.swift ConnectionLog.swift
    Sources/Rex5Kit/                 copied from REX5, plus Catalog.swift, CardSummary.swift, features.json
    Sources/<Device>Kit/             Catalog.swift + features.json for the six devices
    Tests/HubCoreTests/  Tests/Rex5KitTests/  Tests/CatalogTests/
  docs/
    adding-a-device.md
    templates/protocol.md  templates/journal.md
    journal/hub.md
    superpowers/specs/…  superpowers/plans/…
```

---

### Task 1: Repo, ignore rules and privacy scan

**Files:**
- Create: `.gitignore`, `scripts/privacy-scan.py`, `hooks/pre-push`, `docs/journal/hub.md`, `Config/private-patterns.txt` (git-ignored)

**Interfaces:**
- Produces: `python3 scripts/privacy-scan.py` (scan working tree), `--pre-push` (scan commits from the pre-push hook's stdin), `--self-test`. Exit code 1 on any hit or a missing patterns file.

- [ ] **Step 1: Initialise the repo on the work branch**

```bash
cd ~/Development/homedeck
git init -b main
git checkout -b phase-0-shell
git config user.name VM-development
git config user.email 49589920+VM-development@users.noreply.github.com
```

- [ ] **Step 2: Write `.gitignore`**

```gitignore
build/
.build/
.swiftpm/
DerivedData/
xcuserdata/
*.xcuserstate
.DS_Store
.superpowers/
research/
Config/Team.xcconfig
Config/private-patterns.txt
```

- [ ] **Step 3: Write the scan with its self-test first**

`scripts/privacy-scan.py`:

```python
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
    raw = literal.encode()
    found = {}
    for variant in {literal, literal.lower(), literal.upper()}:
        found[variant.encode().lower()] = f"{label} (text)"
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
            raw = git("diff-tree", "-r", "--root", "--no-commit-id", "--raw", commit).decode()
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
               " ".join(f"{b:02X}" for b in raw).encode()]
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
```

- [ ] **Step 4: Run the self-test**

Run: `python3 scripts/privacy-scan.py --self-test`
Expected: `privacy-scan self-test passed`

- [ ] **Step 5: Add the hook and enable it**

`hooks/pre-push`:

```sh
#!/bin/sh
# Blocks the push if it would publish a private value. Enabled with: git config core.hooksPath hooks
exec python3 "$(git rev-parse --show-toplevel)/scripts/privacy-scan.py" --pre-push
```

```bash
chmod +x hooks/pre-push scripts/privacy-scan.py
git config core.hooksPath hooks
```

- [ ] **Step 6: Create `Config/private-patterns.txt` (git-ignored)**

Collect the owner's real values from local sources, one per line, and never copy them into any other file or message that gets committed:
- device names and Bluetooth address bytes from the git-ignored REX5 probe reports in `../rex5/docs/superpowers/probe-results/` (names appear as hex in the packet log; decode them);
- the team ID from `../rex5/Config/Team.xcconfig`;
- the iPhone's name and UDID from `xcrun devicectl list devices`;
- the owner's first and last name, in every script they use.

Then ask the owner to add anything missing (Wi-Fi name, account emails, other device names) before the first push in Task 9. Check that git ignores it:

Run: `git check-ignore Config/private-patterns.txt`
Expected: `Config/private-patterns.txt`

- [ ] **Step 7: Prove the pre-push path blocks a hex-encoded value**

```bash
echo "homedeck-scan-test-value" >> Config/private-patterns.txt
git checkout -b scan-test
printf 'homedeck-scan-test-value' | xxd -p > leak.txt
git add leak.txt && git commit -q -m "scan test"
echo "refs/heads/scan-test $(git rev-parse HEAD) refs/heads/scan-test 0000000000000000000000000000000000000000" \
  | python3 scripts/privacy-scan.py --pre-push; echo "exit $?"
```

Expected: `privacy-scan: private values found, push blocked:`, a line `leak.txt in <sha>: ho… (hex)`, and `exit 1`.

Clean up:

```bash
git checkout phase-0-shell
git branch -D scan-test
rm -f leak.txt
sed -i '' '/homedeck-scan-test-value/d' Config/private-patterns.txt
```

- [ ] **Step 8: Start the hub journal**

`docs/journal/hub.md`:

```markdown
# HomeDeck shell: journal

Entries are only ever appended. No real names, addresses, keys or tokens: use placeholders such as `<phone>`.

## 2026-11-13: Spec, plan and privacy guard

**Tried:** Designed HomeDeck with the owner (spec in docs/superpowers/specs), wrote the Phase 0 plan, then built the privacy scan first, before any device code exists.
**Device answered:** n/a.
**Conclusion:** The scan finds a private value written as hex inside a commit, so the pre-push hook blocks it (verified locally).
**Next:** HubCore's catalog types.
Article note: the privacy guard came before the first line of app code, because six parallel sessions will push to a public repo.
```

- [ ] **Step 9: Commit**

```bash
git add .gitignore scripts hooks docs
git commit -m "Repo scaffold, privacy scan and pre-push hook, spec and Phase 0 plan"
```

---

### Task 2: HubCore catalog types

**Files:**
- Create: `Packages/Package.swift`, `Packages/Sources/HubCore/Catalog.swift`, `Packages/Sources/HubCore/Device.swift`
- Test: `Packages/Tests/HubCoreTests/Helpers.swift`, `Packages/Tests/HubCoreTests/CatalogTypesTests.swift`

**Interfaces:**
- Produces:
  - `enum Link: String, Codable { case bluetooth, wifi }`
  - `struct Feature: Codable, Identifiable, Equatable` with `id`, `title`, `status: Feature.Status` (`.working`, `.planned`, `.notPlanned`), `init(id:title:status:)`, `static func load(from: URL) -> [Feature]`
  - `enum DeviceStatus: Equatable { case notSetUp, offline(reason: String?), connecting, online(summary: String) }` with `var cardLine: String`
  - `@MainActor protocol HomeDevice: AnyObject, Observable` with `status`, `connect() async`, `disconnect() async`, `makeScreen() -> AnyView`
  - `struct DeviceKind: Identifiable` with `id`, `name`, `symbol`, `link`, `features`, `makeDevice`, `init(id:name:symbol:link:featuresURL:makeDevice:)`, `var workingSummary: String`
  - `@MainActor final class UnbuiltDevice: HomeDevice` with `init(name:)`
  - Test helpers `featuresFile(_:) throws -> URL` and `makeKind(id:_:) throws -> DeviceKind`

- [ ] **Step 1: Write the package manifest**

`Packages/Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

// One package with one target per device, so adding a device never edits the Xcode project.
let package = Package(
    name: "HomeDeckKits",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "HomeDeckKits", targets: ["HubCore"])],
    targets: [
        .target(name: "HubCore"),
        .testTarget(name: "HubCoreTests", dependencies: ["HubCore"]),
    ]
)
```

- [ ] **Step 2: Write the failing tests**

`Packages/Tests/HubCoreTests/Helpers.swift`:

```swift
import Foundation
@testable import HubCore

/// Writes features to a temporary features.json, the way a device package ships them.
func featuresFile(_ features: [Feature]) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    try JSONEncoder().encode(features).write(to: url)
    return url
}

func makeKind(id: String = "test", _ features: [Feature]) throws -> DeviceKind {
    DeviceKind(id: id, name: "Test Device", symbol: "questionmark", link: .bluetooth,
               featuresURL: try featuresFile(features)) { UnbuiltDevice(name: "Test Device") }
}
```

`Packages/Tests/HubCoreTests/CatalogTypesTests.swift`:

```swift
import XCTest
@testable import HubCore

@MainActor
final class CatalogTypesTests: XCTestCase {
    func testFeatureListDecodesAllStatuses() throws {
        let json = #"[{"id":"a","title":"A","status":"working"},{"id":"b","title":"B","status":"planned"},{"id":"c","title":"C","status":"notPlanned"}]"#
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try Data(json.utf8).write(to: url)
        XCTAssertEqual(Feature.load(from: url).map(\.status), [.working, .planned, .notPlanned])
    }

    func testWorkingSummaryCountsWorkingFeatures() throws {
        let kind = try makeKind([
            Feature(id: "a", title: "A", status: .working),
            Feature(id: "b", title: "B", status: .planned),
            Feature(id: "c", title: "C", status: .notPlanned),
        ])
        XCTAssertEqual(kind.workingSummary, "1 of 3 features working")
    }

    func testCardLineHidesTheOfflineReason() {
        XCTAssertEqual(DeviceStatus.offline(reason: "Earbuds not found").cardLine, "Offline")
        XCTAssertEqual(DeviceStatus.online(summary: "L 80% · R 75%").cardLine, "L 80% · R 75%")
        XCTAssertEqual(DeviceStatus.notSetUp.cardLine, "Not set up")
        XCTAssertEqual(DeviceStatus.connecting.cardLine, "Connecting…")
    }

    func testUnbuiltDeviceStaysNotSetUp() async {
        let device = UnbuiltDevice(name: "Fan")
        await device.connect()
        XCTAssertEqual(device.status, .notSetUp)
    }
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `cd Packages && swift test --filter CatalogTypesTests`
Expected: build error, `cannot find 'Feature' in scope`.

- [ ] **Step 4: Implement the types**

`Packages/Sources/HubCore/Catalog.swift`:

```swift
import Foundation

public enum Link: String, Codable, Sendable { case bluetooth, wifi }

/// One thing a device's vendor app can do. The list lives in the device package's features.json.
public struct Feature: Codable, Identifiable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case working, planned, notPlanned }

    public let id: String
    public let title: String
    public let status: Status

    public init(id: String, title: String, status: Status) {
        self.id = id
        self.title = title
        self.status = status
    }

    /// Reads a features.json. A broken file is a build mistake, so it stops with the reason;
    /// CatalogTests decodes every device's file, so this can't reach the phone.
    public static func load(from url: URL) -> [Feature] {
        do { return try JSONDecoder().decode([Feature].self, from: Data(contentsOf: url)) }
        catch { preconditionFailure("Can't read \(url.lastPathComponent): \(error)") }
    }
}
```

`Packages/Sources/HubCore/Device.swift`:

```swift
import SwiftUI
import Observation

public enum DeviceStatus: Equatable, Sendable {
    case notSetUp
    case offline(reason: String?)
    case connecting
    case online(summary: String)

    /// The line under the device's name on its Home card. The offline reason is shown in the device's own screen.
    public var cardLine: String {
        switch self {
        case .notSetUp: "Not set up"
        case .offline: "Offline"
        case .connecting: "Connecting…"
        case .online(let summary): summary
        }
    }
}

/// What every device module implements. Its class lives in App/Devices/<Name>/.
@MainActor
public protocol HomeDevice: AnyObject, Observable {
    var status: DeviceStatus { get }
    func connect() async
    func disconnect() async
    /// The device's full screen, including first-time setup while the status is .notSetUp.
    func makeScreen() -> AnyView
}

/// One catalog entry: what the Market shows and how to create the device.
public struct DeviceKind: Identifiable {
    public let id: String
    public let name: String
    public let symbol: String
    public let link: Link
    public let features: [Feature]
    public let makeDevice: @MainActor () -> any HomeDevice

    public init(id: String, name: String, symbol: String, link: Link, featuresURL: URL,
                makeDevice: @escaping @MainActor () -> any HomeDevice) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.link = link
        self.features = Feature.load(from: featuresURL)
        self.makeDevice = makeDevice
    }

    public var workingSummary: String {
        "\(features.filter { $0.status == .working }.count) of \(features.count) features working"
    }
}

/// Stands in for a device whose module isn't built yet, so the Market lists it and Add works.
@MainActor
@Observable
public final class UnbuiltDevice: HomeDevice {
    public let name: String

    public init(name: String) { self.name = name }

    public var status: DeviceStatus { .notSetUp }
    public func connect() async {}
    public func disconnect() async {}

    public func makeScreen() -> AnyView {
        AnyView(ContentUnavailableView(
            "\(name) isn't built yet", systemImage: "hammer",
            description: Text("Its features are listed in Market. Mark the ones you want and send the wishlist to its session.")))
    }
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `cd Packages && swift test --filter CatalogTypesTests`
Expected: `Executed 4 tests, with 0 failures`

- [ ] **Step 6: Journal entry and commit**

Append a `## 2026-11-13: HubCore catalog types` entry to `docs/journal/hub.md` (what was built, that 4 tests pass, next: choices and store).

```bash
git add Packages docs/journal/hub.md
git commit -m "HubCore: catalog types and HomeDevice contract"
```

---

### Task 3: Feature choices, device store and the feature modifier

**Files:**
- Create: `Packages/Sources/HubCore/FeatureChoices.swift`, `Packages/Sources/HubCore/DeviceStore.swift`, `Packages/Sources/HubCore/FeatureGate.swift`
- Test: `Packages/Tests/HubCoreTests/FeatureChoicesTests.swift`, `Packages/Tests/HubCoreTests/DeviceStoreTests.swift`

**Interfaces:**
- Consumes: `Feature`, `DeviceKind`, `HomeDevice`, `UnbuiltDevice`, test helpers from Task 2.
- Produces:
  - `@MainActor @Observable final class FeatureChoices` with `static let shared`, `init(defaults: UserDefaults = .standard)`, `isHidden(_:device:)`, `setHidden(_:_:device:)`, `isWanted(_:device:)`, `setWanted(_:_:device:)`, `wishlist(for: DeviceKind) -> String?`
  - `@MainActor @Observable final class DeviceStore` with `init(kinds:defaults:)`, `kinds`, `addedIDs`, `added: [DeviceKind]`, `isAdded(_:)`, `kind(id:)`, `add(_:)`, `remove(_:)`, `device(for:) -> any HomeDevice`, `static let key`
  - `EnvironmentValues.deviceID: String` and `View.feature(_ id: String)`

- [ ] **Step 1: Write the failing tests**

`Packages/Tests/HubCoreTests/FeatureChoicesTests.swift`:

```swift
import XCTest
@testable import HubCore

@MainActor
final class FeatureChoicesTests: XCTestCase {
    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

    func testChoicesSurviveRelaunchPerDevice() {
        let defaults = freshDefaults()
        FeatureChoices(defaults: defaults).setHidden(true, "battery", device: "rex5")
        let reloaded = FeatureChoices(defaults: defaults)
        XCTAssertTrue(reloaded.isHidden("battery", device: "rex5"))
        XCTAssertFalse(reloaded.isHidden("battery", device: "fan"))
    }

    func testUnhidingRemovesTheChoice() {
        let choices = FeatureChoices(defaults: freshDefaults())
        choices.setHidden(true, "battery", device: "rex5")
        choices.setHidden(false, "battery", device: "rex5")
        XCTAssertFalse(choices.isHidden("battery", device: "rex5"))
    }

    func testWishlistListsWantedFeaturesThatDontWorkYet() throws {
        let kind = try makeKind(id: "fan", [
            Feature(id: "power", title: "Power", status: .working),
            Feature(id: "timer", title: "Timer", status: .planned),
            Feature(id: "light", title: "Light", status: .notPlanned),
        ])
        let choices = FeatureChoices(defaults: freshDefaults())
        XCTAssertNil(choices.wishlist(for: kind))
        choices.setWanted(true, "light", device: "fan")
        choices.setWanted(true, "timer", device: "fan")
        choices.setWanted(true, "power", device: "fan")  // already working: left out
        XCTAssertEqual(choices.wishlist(for: kind), "HomeDeck wishlist for Test Device:\n- Timer (timer)\n- Light (light)")
    }
}
```

`Packages/Tests/HubCoreTests/DeviceStoreTests.swift`:

```swift
import XCTest
@testable import HubCore

@MainActor
final class DeviceStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults { UserDefaults(suiteName: "test.\(UUID().uuidString)")! }

    func testAddedDevicesSurviveRelaunchAndUnknownKindsAreDropped() throws {
        let defaults = freshDefaults()
        defaults.set(["removed-from-registry"], forKey: DeviceStore.key)
        let kind = try makeKind(id: "fan", [])
        let store = DeviceStore(kinds: [kind], defaults: defaults)
        XCTAssertTrue(store.added.isEmpty)
        store.add(kind)
        store.add(kind)
        XCTAssertEqual(DeviceStore(kinds: [kind], defaults: defaults).added.map(\.id), ["fan"])
    }

    func testAddedDeviceIsCreatedOnceAtLaunch() throws {
        var made = 0
        let kind = DeviceKind(id: "fan", name: "Fan", symbol: "fan.floor", link: .wifi,
                              featuresURL: try featuresFile([])) {
            made += 1
            return UnbuiltDevice(name: "Fan")
        }
        let defaults = freshDefaults()
        defaults.set(["fan"], forKey: DeviceStore.key)
        let store = DeviceStore(kinds: [kind], defaults: defaults)
        XCTAssertEqual(made, 1)  // created at launch, so Bluetooth state restoration finds its manager
        XCTAssertTrue(store.device(for: kind) === store.device(for: kind))
        XCTAssertEqual(made, 1)
    }

    func testRemoveTakesTheDeviceOffHome() throws {
        let defaults = freshDefaults()
        let kind = try makeKind(id: "fan", [])
        let store = DeviceStore(kinds: [kind], defaults: defaults)
        store.add(kind)
        store.remove(kind)
        XCTAssertFalse(store.isAdded(kind))
        XCTAssertTrue(DeviceStore(kinds: [kind], defaults: defaults).added.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd Packages && swift test --filter "FeatureChoicesTests|DeviceStoreTests"`
Expected: build error, `cannot find 'FeatureChoices' in scope`.

- [ ] **Step 3: Implement**

`Packages/Sources/HubCore/FeatureChoices.swift`:

```swift
import Foundation
import Observation

/// The owner's Show and Want ticks, kept on the phone. What exists and what works lives in features.json.
@MainActor
@Observable
public final class FeatureChoices {
    public static let shared = FeatureChoices()

    private let defaults: UserDefaults
    private var hidden: [String: Set<String>]
    private var wanted: [String: Set<String>]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hidden = Self.load("featureChoices.hidden", from: defaults)
        wanted = Self.load("featureChoices.wanted", from: defaults)
    }

    public func isHidden(_ feature: String, device: String) -> Bool { hidden[device, default: []].contains(feature) }
    public func isWanted(_ feature: String, device: String) -> Bool { wanted[device, default: []].contains(feature) }

    public func setHidden(_ on: Bool, _ feature: String, device: String) {
        Self.set(&hidden, on, feature, device)
        Self.save(hidden, "featureChoices.hidden", to: defaults)
    }

    public func setWanted(_ on: Bool, _ feature: String, device: String) {
        Self.set(&wanted, on, feature, device)
        Self.save(wanted, "featureChoices.wanted", to: defaults)
    }

    /// Plain text for the share sheet, pasted into the device's session. Nil when nothing is wanted.
    public func wishlist(for kind: DeviceKind) -> String? {
        let lines = kind.features
            .filter { $0.status != .working && isWanted($0.id, device: kind.id) }
            .map { "- \($0.title) (\($0.id))" }
        guard !lines.isEmpty else { return nil }
        return (["HomeDeck wishlist for \(kind.name):"] + lines).joined(separator: "\n")
    }

    private static func set(_ table: inout [String: Set<String>], _ on: Bool, _ feature: String, _ device: String) {
        if on { table[device, default: []].insert(feature) } else { table[device, default: []].remove(feature) }
    }

    private static func load(_ key: String, from defaults: UserDefaults) -> [String: Set<String>] {
        (defaults.dictionary(forKey: key) as? [String: [String]] ?? [:]).mapValues(Set.init)
    }

    private static func save(_ table: [String: Set<String>], _ key: String, to defaults: UserDefaults) {
        defaults.set(table.mapValues { Array($0).sorted() }, forKey: key)
    }
}
```

`Packages/Sources/HubCore/DeviceStore.swift`:

```swift
import Foundation
import Observation

/// Which kinds the owner added to Home, and one live device per kind.
@MainActor
@Observable
public final class DeviceStore {
    static let key = "deviceStore.added"

    public let kinds: [DeviceKind]
    public private(set) var addedIDs: [String]
    @ObservationIgnored private var devices: [String: any HomeDevice] = [:]
    private let defaults: UserDefaults

    public init(kinds: [DeviceKind], defaults: UserDefaults = .standard) {
        self.kinds = kinds
        self.defaults = defaults
        let known = Set(kinds.map(\.id))
        addedIDs = (defaults.stringArray(forKey: Self.key) ?? []).filter(known.contains)
        // Added devices start at launch, so Bluetooth state restoration and background work find them.
        for kind in added { _ = device(for: kind) }
    }

    public var added: [DeviceKind] { addedIDs.compactMap(kind(id:)) }
    public func kind(id: String) -> DeviceKind? { kinds.first { $0.id == id } }
    public func isAdded(_ kind: DeviceKind) -> Bool { addedIDs.contains(kind.id) }

    public func add(_ kind: DeviceKind) {
        guard !isAdded(kind) else { return }
        addedIDs.append(kind.id)
        defaults.set(addedIDs, forKey: Self.key)
    }

    /// Takes the card off Home. It doesn't disconnect: for REX5 that would drop the iPhone's audio.
    public func remove(_ kind: DeviceKind) {
        addedIDs.removeAll { $0 == kind.id }
        defaults.set(addedIDs, forKey: Self.key)
    }

    /// The same instance every time: device classes hold live connections.
    public func device(for kind: DeviceKind) -> any HomeDevice {
        if let device = devices[kind.id] { return device }
        let device = kind.makeDevice()
        devices[kind.id] = device
        return device
    }
}
```

`Packages/Sources/HubCore/FeatureGate.swift`:

```swift
import SwiftUI

private struct DeviceIDKey: EnvironmentKey { static let defaultValue = "" }

public extension EnvironmentValues {
    /// Set by the shell on each device screen, so `.feature(_:)` knows whose choices to read.
    var deviceID: String {
        get { self[DeviceIDKey.self] }
        set { self[DeviceIDKey.self] = newValue }
    }
}

private struct FeatureGate: ViewModifier {
    let feature: String
    @Environment(\.deviceID) private var device

    @ViewBuilder func body(content: Content) -> some View {
        if !FeatureChoices.shared.isHidden(feature, device: device) { content }
    }
}

public extension View {
    /// Hides this part of a device screen when the owner switched the feature off in Market.
    func feature(_ id: String) -> some View { modifier(FeatureGate(feature: id)) }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd Packages && swift test`
Expected: `Executed 10 tests, with 0 failures`

- [ ] **Step 5: Journal entry and commit**

Append `## 2026-11-13: Feature choices and device store` to `docs/journal/hub.md`.

```bash
git add Packages docs/journal/hub.md
git commit -m "HubCore: feature choices, device store, feature modifier"
```

---

### Task 4: Shared connection log

**Files:**
- Create: `Packages/Sources/HubCore/ConnectionLog.swift` (ported from `../rex5/App/ConnectionLog.swift`, now tagged by device)
- Test: `Packages/Tests/HubCoreTests/ConnectionLogTests.swift`

**Interfaces:**
- Produces: `@MainActor @Observable final class ConnectionLog` with `static let shared`, `static let limit = 500`, `init(url:)`, `entries: [Entry]` (`date`, `device`, `text`), `add(_:device:)`, `entries(for: String?)`, `shareText(for: String?)`, `tagged(_:) -> DeviceLogger`; `@MainActor struct DeviceLogger` with `device` and `add(_:)`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import HubCore

@MainActor
final class ConnectionLogTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jsonl")
    }

    func testEntriesAreTaggedAndSurviveRelaunch() {
        let url = tempURL()
        let log = ConnectionLog(url: url)
        log.tagged("rex5").add("Connected")
        log.add("Fan on", device: "fan")
        let reloaded = ConnectionLog(url: url)
        XCTAssertEqual(reloaded.entries.map(\.device), ["rex5", "fan"])
        XCTAssertEqual(reloaded.entries(for: "fan").map(\.text), ["Fan on"])
        XCTAssertEqual(reloaded.entries(for: nil).count, 2)
    }

    func testKeepsOnlyTheNewestEntries() {
        let url = tempURL()
        let log = ConnectionLog(url: url)
        for i in 0..<(ConnectionLog.limit + 5) { log.add("line \(i)", device: "rex5") }
        XCTAssertEqual(log.entries.count, ConnectionLog.limit)
        XCTAssertEqual(log.entries.first?.text, "line 5")
        XCTAssertEqual(ConnectionLog(url: url).entries.count, ConnectionLog.limit)
    }

    func testShareTextIsNewestFirstWithTheDevice() {
        let log = ConnectionLog(url: tempURL())
        log.add("first", device: "rex5")
        log.add("second", device: "fan")
        let lines = log.shareText(for: nil).split(separator: "\n")
        XCTAssertTrue(lines[0].hasSuffix("[fan] second"))
        XCTAssertTrue(lines[1].hasSuffix("[rex5] first"))
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `cd Packages && swift test --filter ConnectionLogTests`
Expected: build error, `cannot find 'ConnectionLog' in scope`.

- [ ] **Step 3: Implement**

`Packages/Sources/HubCore/ConnectionLog.swift`:

```swift
import Foundation
import Observation

/// Append-only JSON-lines log of every device's exchanges, tagged by device id. Keeps the newest 500
/// and trims the file at launch.
@MainActor
@Observable
public final class ConnectionLog {
    public struct Entry: Codable, Equatable, Sendable {
        public let date: Date
        public let device: String
        public let text: String
    }

    public static let limit = 500
    nonisolated public static let defaultURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("connection-log.jsonl")
    public static let shared = ConnectionLog()

    public private(set) var entries: [Entry]
    private let url: URL

    public init(url: URL = ConnectionLog.defaultURL) {
        self.url = url
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = (try? String(contentsOf: url, encoding: .utf8))?.split(separator: "\n") ?? []
        entries = lines.suffix(Self.limit).compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
        if lines.count > Self.limit {  // trim the file once per launch; it only grows by appends while running
            try? entries.compactMap(Self.line).reduce(Data(), +).write(to: url, options: .atomic)
        }
    }

    public func add(_ text: String, device: String) {
        let entry = Entry(date: Date(), device: device, text: text)
        entries.append(entry)
        if entries.count > Self.limit { entries.removeFirst() }
        if let line = Self.line(entry) { append(line) }
    }

    public func entries(for device: String?) -> [Entry] {
        guard let device else { return entries }
        return entries.filter { $0.device == device }
    }

    /// Newest first, for the Share button.
    public func shareText(for device: String?) -> String {
        let formatter = ISO8601DateFormatter()
        return entries(for: device).reversed()
            .map { "\(formatter.string(from: $0.date)) [\($0.device)] \($0.text)" }
            .joined(separator: "\n")
    }

    public func tagged(_ device: String) -> DeviceLogger { DeviceLogger(device: device, log: self) }

    private func append(_ line: Data) {
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? line.write(to: url, options: .atomic)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: line)
    }

    private static func line(_ entry: Entry) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(entry)).map { $0 + Data("\n".utf8) }
    }
}

/// A device's view of the shared log, so its code keeps calling `log.add("...")`.
@MainActor
public struct DeviceLogger {
    public let device: String
    let log: ConnectionLog

    public func add(_ text: String) { log.add(text, device: device) }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `cd Packages && swift test`
Expected: `Executed 13 tests, with 0 failures`

- [ ] **Step 5: Journal entry and commit**

Append `## 2026-11-13: Shared connection log` to `docs/journal/hub.md`.

```bash
git add Packages docs/journal/hub.md
git commit -m "HubCore: shared connection log tagged by device"
```

---

### Task 5: Device kits: REX5 plus six catalog stubs

**Files:**
- Copy: `../rex5/Rex5Kit/Sources/Rex5Kit/*` to `Packages/Sources/Rex5Kit/`, `../rex5/Rex5Kit/Tests/Rex5KitTests/*` to `Packages/Tests/Rex5KitTests/`
- Modify: `Packages/Sources/Rex5Kit/EarbudSnapshot.swift` (App Group id), `Packages/Package.swift`
- Create: `Packages/Sources/Rex5Kit/Catalog.swift`, `Packages/Sources/Rex5Kit/CardSummary.swift`, `Packages/Sources/Rex5Kit/features.json`, and for each of `WalkingPadKit`, `MiScaleKit`, `PhilipsAirKit`, `ZeppelinKit`, `XiaomiFanKit`, `DreameKit`: `Packages/Sources/<Kit>/Catalog.swift` and `features.json`
- Test: `Packages/Tests/Rex5KitTests/CardSummaryTests.swift`, `Packages/Tests/CatalogTests/CatalogTests.swift`

**Interfaces:**
- Consumes: `Feature.load(from:)` from Task 2.
- Produces: `Rex5Catalog.featuresURL`, `WalkingPadCatalog.featuresURL`, `MiScaleCatalog.featuresURL`, `PhilipsAirCatalog.featuresURL`, `ZeppelinCatalog.featuresURL`, `XiaomiFanCatalog.featuresURL`, `DreameCatalog.featuresURL` (all `URL`); `EarbudSnapshot.cardSummary: String`; `SnapshotFile.appGroup == "group.local.homedeck.app"`. Feature ids used by Task 6's REX5 screen: `battery`, `noise-control`, `equalizer`, `connections`, `troubleshooting`.

- [ ] **Step 1: Copy Rex5Kit and point it at HomeDeck's App Group**

```bash
mkdir -p Packages/Sources Packages/Tests
cp -R ../rex5/Rex5Kit/Sources/Rex5Kit Packages/Sources/
cp -R ../rex5/Rex5Kit/Tests/Rex5KitTests Packages/Tests/
sed -i '' 's/group\.local\.rex5\.app/group.local.homedeck.app/' Packages/Sources/Rex5Kit/EarbudSnapshot.swift
grep -rn "local.rex5" Packages || echo "no old ids left"
```

Expected: `no old ids left`.

- [ ] **Step 2: Write the manifest with every kit**

`Packages/Package.swift`:

```swift
// swift-tools-version: 5.10
import PackageDescription

// One package with one target per device, so adding a device never edits the Xcode project.
// A device session adds its `<Name>KitTests` test target when it writes protocol code.
let kits = ["Rex5Kit", "WalkingPadKit", "MiScaleKit", "PhilipsAirKit", "ZeppelinKit", "XiaomiFanKit", "DreameKit"]

let package = Package(
    name: "HomeDeckKits",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "HomeDeckKits", targets: ["HubCore"] + kits)],
    targets: [
        .target(name: "HubCore"),
        .testTarget(name: "HubCoreTests", dependencies: ["HubCore"]),
        .testTarget(name: "Rex5KitTests", dependencies: ["Rex5Kit"]),
        .testTarget(name: "CatalogTests", dependencies: ["HubCore"] + kits.map { Target.Dependency.byName(name: $0) }),
    ] + kits.map { Target.target(name: $0, resources: [.process("features.json")]) }
)
```

- [ ] **Step 3: Write the failing tests**

`Packages/Tests/Rex5KitTests/CardSummaryTests.swift`:

```swift
import XCTest
@testable import Rex5Kit

final class CardSummaryTests: XCTestCase {
    func testCardSummaryShowsBothEarbuds() {
        var snapshot = EarbudSnapshot(link: .connected, leftBattery: 80, rightBattery: nil, batteryReadAt: Date())
        XCTAssertEqual(snapshot.cardSummary, "L 80% · R In case")
        snapshot.leftBattery = nil
        snapshot.batteryReadAt = nil
        XCTAssertEqual(snapshot.cardSummary, "L — · R —")
    }
}
```

`Packages/Tests/CatalogTests/CatalogTests.swift`:

```swift
import XCTest
import HubCore
import Rex5Kit
import WalkingPadKit
import MiScaleKit
import PhilipsAirKit
import ZeppelinKit
import XiaomiFanKit
import DreameKit

/// Every device's features.json must decode, with unique ids, before it can reach the Market.
final class CatalogTests: XCTestCase {
    let lists: [String: URL] = [
        "rex5": Rex5Catalog.featuresURL,
        "walkingpad-c2": WalkingPadCatalog.featuresURL,
        "mi-scale-s400": MiScaleCatalog.featuresURL,
        "philips-ac2729": PhilipsAirCatalog.featuresURL,
        "zeppelin-pro": ZeppelinCatalog.featuresURL,
        "xiaomi-fan-2-pro": XiaomiFanCatalog.featuresURL,
        "dreame-l40-ultra": DreameCatalog.featuresURL,
    ]

    func testEveryFeatureListDecodesWithUniqueIDs() {
        for (device, url) in lists {
            let features = Feature.load(from: url)
            XCTAssertFalse(features.isEmpty, device)
            XCTAssertEqual(Set(features.map(\.id)).count, features.count, "duplicate feature id in \(device)")
        }
    }

    func testRex5ListsWhatAlreadyWorks() {
        let working = Feature.load(from: Rex5Catalog.featuresURL).filter { $0.status == .working }.map(\.id)
        XCTAssertEqual(working, ["battery", "noise-control", "equalizer", "connections", "widgets", "troubleshooting"])
    }
}
```

- [ ] **Step 4: Run the tests to see them fail**

Run: `cd Packages && swift test`
Expected: build errors, `cannot find 'Rex5Catalog' in scope` and missing source directories for the six kits.

- [ ] **Step 5: Add REX5's catalog, summary and features**

`Packages/Sources/Rex5Kit/Catalog.swift`:

```swift
import Foundation

public enum Rex5Catalog {
    public static let featuresURL = Bundle.module.url(forResource: "features", withExtension: "json")!
}
```

`Packages/Sources/Rex5Kit/CardSummary.swift`:

```swift
extension EarbudSnapshot {
    /// The HomeDeck card's status line, for example "L 80% · R In case".
    public var cardSummary: String { "L \(batteryText(leftBattery)) · R \(batteryText(rightBattery))" }
}
```

`Packages/Sources/Rex5Kit/features.json`:

```json
[
  { "id": "battery", "title": "Battery for each earbud, with In case", "status": "working" },
  { "id": "noise-control", "title": "Noise control: off, ANC, ambient", "status": "working" },
  { "id": "equalizer", "title": "Equalizer: built-in presets and 5-band custom", "status": "working" },
  { "id": "connections", "title": "Connect or disconnect this iPhone, drop other paired devices", "status": "working" },
  { "id": "widgets", "title": "Home Screen and Lock Screen widgets", "status": "working" },
  { "id": "troubleshooting", "title": "Guided reset", "status": "working" },
  { "id": "prompt-tones", "title": "Prompt tone switch", "status": "planned" },
  { "id": "multipoint", "title": "Multipoint on or off", "status": "notPlanned" },
  { "id": "factory-restore", "title": "Factory restore", "status": "notPlanned" },
  { "id": "firmware-update", "title": "Firmware update", "status": "notPlanned" }
]
```

- [ ] **Step 6: Add the six stub kits**

Create `Packages/Sources/<Kit>/Catalog.swift` for each kit with its enum name:

| Kit | Enum |
|---|---|
| WalkingPadKit | WalkingPadCatalog |
| MiScaleKit | MiScaleCatalog |
| PhilipsAirKit | PhilipsAirCatalog |
| ZeppelinKit | ZeppelinCatalog |
| XiaomiFanKit | XiaomiFanCatalog |
| DreameKit | DreameCatalog |

For example `Packages/Sources/WalkingPadKit/Catalog.swift`:

```swift
import Foundation

public enum WalkingPadCatalog {
    public static let featuresURL = Bundle.module.url(forResource: "features", withExtension: "json")!
}
```

Starting feature lists, all `planned`, expected from each vendor app and replaced by the device session's real inventory:

`Packages/Sources/WalkingPadKit/features.json`:

```json
[
  { "id": "start-stop", "title": "Start and stop the belt", "status": "planned" },
  { "id": "speed", "title": "Set the speed", "status": "planned" },
  { "id": "mode", "title": "Mode: manual, automatic, standby", "status": "planned" },
  { "id": "live-stats", "title": "Live speed, distance, steps and time", "status": "planned" },
  { "id": "history", "title": "Workout history", "status": "planned" }
]
```

`Packages/Sources/MiScaleKit/features.json`:

```json
[
  { "id": "weight", "title": "Weight", "status": "planned" },
  { "id": "body-composition", "title": "Body composition: fat, muscle, water, bone, BMI", "status": "planned" },
  { "id": "heart-rate", "title": "Heart rate", "status": "planned" },
  { "id": "profiles", "title": "User profiles", "status": "planned" },
  { "id": "history", "title": "History and trends", "status": "planned" },
  { "id": "apple-health", "title": "Save to Apple Health", "status": "planned" }
]
```

`Packages/Sources/PhilipsAirKit/features.json`:

```json
[
  { "id": "power", "title": "Power on and off", "status": "planned" },
  { "id": "mode", "title": "Mode: auto, sleep, allergen, manual", "status": "planned" },
  { "id": "fan-speed", "title": "Fan speed", "status": "planned" },
  { "id": "humidifier", "title": "Purify only, or purify and humidify", "status": "planned" },
  { "id": "humidity-target", "title": "Target humidity", "status": "planned" },
  { "id": "air-quality", "title": "Air quality and PM2.5 readings", "status": "planned" },
  { "id": "humidity-reading", "title": "Humidity and temperature readings", "status": "planned" },
  { "id": "filter-status", "title": "Filter status", "status": "planned" },
  { "id": "water-level", "title": "Water level", "status": "planned" },
  { "id": "timer", "title": "Timer", "status": "planned" },
  { "id": "light", "title": "Display brightness", "status": "planned" },
  { "id": "child-lock", "title": "Child lock", "status": "planned" }
]
```

`Packages/Sources/ZeppelinKit/features.json`:

```json
[
  { "id": "playback", "title": "Play, pause and skip", "status": "planned" },
  { "id": "volume", "title": "Volume", "status": "planned" },
  { "id": "now-playing", "title": "Now playing and source", "status": "planned" },
  { "id": "eq", "title": "Bass and treble", "status": "planned" },
  { "id": "light", "title": "Ambient light brightness", "status": "planned" },
  { "id": "power-settings", "title": "Standby and auto-wake settings", "status": "planned" },
  { "id": "firmware-update", "title": "Firmware update", "status": "planned" }
]
```

`Packages/Sources/XiaomiFanKit/features.json`:

```json
[
  { "id": "power", "title": "Power on and off", "status": "planned" },
  { "id": "speed", "title": "Fan speed", "status": "planned" },
  { "id": "mode", "title": "Mode: direct or natural breeze", "status": "planned" },
  { "id": "oscillation", "title": "Oscillation and its angle", "status": "planned" },
  { "id": "timer", "title": "Timer", "status": "planned" },
  { "id": "child-lock", "title": "Child lock", "status": "planned" },
  { "id": "light", "title": "Indicator light", "status": "planned" },
  { "id": "sound", "title": "Beep on or off", "status": "planned" }
]
```

`Packages/Sources/DreameKit/features.json`:

```json
[
  { "id": "status", "title": "Status and battery", "status": "planned" },
  { "id": "start-pause-dock", "title": "Start, pause and return to dock", "status": "planned" },
  { "id": "clean-mode", "title": "Cleaning mode: vacuum, mop, both", "status": "planned" },
  { "id": "suction", "title": "Suction level", "status": "planned" },
  { "id": "water-level", "title": "Mop water level", "status": "planned" },
  { "id": "rooms", "title": "Clean selected rooms", "status": "planned" },
  { "id": "map", "title": "Map", "status": "planned" },
  { "id": "schedule", "title": "Schedules", "status": "planned" },
  { "id": "consumables", "title": "Brush, filter and mop pad life", "status": "planned" },
  { "id": "base-station", "title": "Base station: empty, wash and dry mops", "status": "planned" },
  { "id": "do-not-disturb", "title": "Do not disturb", "status": "planned" }
]
```

- [ ] **Step 7: Run all package tests**

Run: `cd Packages && swift test`
Expected: all tests pass: the copied REX5 tests, `CardSummaryTests`, `CatalogTests` and the HubCore tests. If a copied REX5 test asserts the old App Group string, change that expectation to `group.local.homedeck.app`.

- [ ] **Step 8: Journal entry and commit**

Append `## 2026-11-13: Device kits` to `docs/journal/hub.md`.

```bash
git add Packages docs/journal/hub.md
git commit -m "Device kits: Rex5Kit moved in, catalogs and starting feature lists for six devices"
```

---

### Task 6: Xcode project, app shell and REX5 migration

**Files:**
- Copy and rename: `../rex5/Rex5.xcodeproj` to `HomeDeck.xcodeproj`
- Copy: REX5 app files into `App/Devices/Rex5/`, `App/UI/Glass.swift`, `App/Assets.xcassets`, `App/Info.plist`, `Widgets/*`, `Shared/GlassStyle.swift`, `Config/Signing.xcconfig`, `Config/Team.xcconfig.example`, `Config/Team.xcconfig` (git-ignored)
- Create: `App/HomeDeckApp.swift`, `App/DeviceRegistry.swift`, `App/DashboardView.swift`, `App/Devices/Rex5/Rex5Device.swift`, `App/HomeDeck.entitlements`, `Widgets/HomeDeckWidgets.entitlements`
- Modify: `App/Devices/Rex5/EarbudService.swift`, `EarbudLink.swift`, `ToolsView.swift`, `Rex5Screen.swift`; `Widgets/EarbudWidgets.swift`; `App/Info.plist`

**Interfaces:**
- Consumes: `DeviceStore`, `DeviceKind`, `HomeDevice`, `DeviceStatus`, `UnbuiltDevice`, `ConnectionLog`, `DeviceLogger`, `EnvironmentValues.deviceID`, `View.feature(_:)`, all `<Name>Catalog.featuresURL`, `EarbudSnapshot.cardSummary`.
- Produces: `DeviceRegistry.kinds: [DeviceKind]`; `Rex5Device.shared` with `pendingLink: DeepLink?`; `HomeDeckApp.open(_ kind: DeviceKind)` used by Task 7's Market; `HubSettingsView(kinds:)` and `MarketView(store:openDevice:)` are referenced here and created in Task 7 (Step 9 below adds temporary one-line stubs so this task builds).

- [ ] **Step 1: Copy the project and rename everything in it**

```bash
cp -R ../rex5/Rex5.xcodeproj HomeDeck.xcodeproj
rm -rf HomeDeck.xcodeproj/xcuserdata HomeDeck.xcodeproj/project.xcworkspace/xcuserdata
sed -i '' \
  -e 's/Rex5Widgets/HomeDeckWidgets/g' \
  -e 's/Rex5\.entitlements/HomeDeck.entitlements/g' \
  -e 's/relativePath = Rex5Kit;/relativePath = Packages;/' \
  -e 's/path = Rex5Kit;/path = Packages;/' \
  -e 's/Rex5Kit/HomeDeckKits/g' \
  -e 's/local\.rex5\.app/local.homedeck.app/g' \
  -e 's/Rex5/HomeDeck/g' \
  HomeDeck.xcodeproj/project.pbxproj
grep -ci "rex5" HomeDeck.xcodeproj/project.pbxproj
```

Expected: `0`.

- [ ] **Step 2: Copy the REX5 app files**

```bash
mkdir -p App/Devices/Rex5 App/UI Widgets Shared Config
cp ../rex5/App/{EarbudLink,EarbudService,RefreshIntent,TakeoverNotifier}.swift App/Devices/Rex5/
cp ../rex5/App/Screens/{EqualizerView,PairedDevicesView,SettingsView,ToolsView}.swift App/Devices/Rex5/
cp ../rex5/App/Screens/HomeView.swift App/Devices/Rex5/Rex5Screen.swift
cp ../rex5/App/Screens/Glass.swift App/UI/Glass.swift
cp -R ../rex5/App/Assets.xcassets App/
cp ../rex5/App/Info.plist App/Info.plist
cp ../rex5/Widgets/{EarbudWidgets,Rex5Widget}.swift ../rex5/Widgets/Info.plist Widgets/
cp ../rex5/Shared/GlassStyle.swift Shared/
cp ../rex5/Config/{Signing.xcconfig,Team.xcconfig.example} Config/
cp ../rex5/Config/Team.xcconfig Config/
git check-ignore Config/Team.xcconfig
```

Expected: `Config/Team.xcconfig` (ignored).

- [ ] **Step 3: Entitlements and Info.plist**

`App/HomeDeck.entitlements` and `Widgets/HomeDeckWidgets.entitlements`, both:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.local.homedeck.app</string>
	</array>
</dict>
</plist>
```

```bash
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName HomeDeck" App/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLName local.homedeck.app" App/Info.plist
/usr/libexec/PlistBuddy -c "Set :NSBluetoothAlwaysUsageDescription Connects to your Bluetooth home devices." App/Info.plist
/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes" App/Info.plist
```

Expected: the URL schemes still list `rex5`, which the REX5 widgets and alerts link to.

- [ ] **Step 4: Adapt EarbudService, EarbudLink, ToolsView and the widget bundle**

`App/Devices/Rex5/EarbudService.swift`: add `import HubCore` under `import Rex5Kit`, then make three replacements:

```swift
// before
    let log: ConnectionLog
// after
    let log: DeviceLogger
```

```swift
// before
    static let shared = EarbudService(link: EarbudLink(), log: ConnectionLog(), notifier: TakeoverNotifier(),
// after
    static let shared = EarbudService(link: EarbudLink(), log: ConnectionLog.shared.tagged("rex5"), notifier: TakeoverNotifier(),
```

```swift
// before
    init(link: EarbudLink, log: ConnectionLog, notifier: TakeoverNotifier, snapshotURL: URL?) {
// after
    init(link: EarbudLink, log: DeviceLogger, notifier: TakeoverNotifier, snapshotURL: URL?) {
```

`App/Devices/Rex5/EarbudLink.swift`, the restoration identifier (spec: `homedeck.<id>`):

```swift
// before
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "rex5.central"])
// after
                                   options: [CBCentralManagerOptionRestoreIdentifierKey: "homedeck.rex5"])
```

`App/Devices/Rex5/ToolsView.swift`: the shared log now lives in Settings, so delete this row:

```swift
        row("Connection log", "list.bullet.rectangle") { LogView(log: service.log) }
```

and delete the whole `struct LogView: View { … }` definition (from `struct LogView` through its closing brace).

`Widgets/EarbudWidgets.swift`:

```swift
// before
struct Rex5Widgets: WidgetBundle {
// after
struct HomeDeckWidgets: WidgetBundle {
```

- [ ] **Step 5: Turn REX5's HomeView into Rex5Screen**

In `App/Devices/Rex5/Rex5Screen.swift`, replace everything from `struct HomeView: View {` through the end of its `body` (the line `    }` after the `.onChange(of: route)` block) with:

```swift
struct Rex5Screen: View {
    enum Screen: Hashable { case devices, tools, settings }

    @Bindable var service: EarbudService
    @Bindable var device: Rex5Device
    @State private var opened: Screen?
    @Namespace private var glass
    @State private var checkedANC: ANCMode?

    private var snapshot: EarbudSnapshot { service.snapshot }

    var body: some View {
        GlassScreen {
            batteryCard.feature("battery")
            noticeCard
            actionButton.feature("connections")
            soundCard
            GlassCard(title: "Paired devices") { DevicesList(service: service) }.feature("connections")
            GlassCard(title: "Tools") { ToolsList(service: service) }.feature("troubleshooting")
            CardCaption("If you swipe HomeDeck away in the app switcher, alerts and widget updates stop until you open it again.")
        }
        .refreshable { await service.refresh() }
        .navigationTitle("REX5")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { opened = .settings } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        .navigationDestination(item: $opened) { screen in
            switch screen {
            case .devices: PairedDevicesView(service: service)
            case .tools: ToolsView(service: service)
            case .settings: SettingsView(service: service)
            }
        }
        .sheet(isPresented: Binding(get: { service.needsThisPhoneChoice }, set: { _ in })) {
            NavigationStack { ThisPhonePicker(service: service) }
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $service.showRoutePicker) { RoutePickerSheet() }
        .alert(service.notice ?? "", isPresented: Binding(get: { service.notice != nil }, set: { if !$0 { service.notice = nil } })) {
            Button("OK", role: .cancel) {}
        }
        .onChange(of: device.pendingLink, initial: true) { _, link in
            guard let link else { return }
            device.pendingLink = nil
            switch link {
            case .connect: Task { await service.connectThisPhone() }
            case .disconnect: Task { await service.disconnectThisPhone() }
            case .tools: opened = .tools
            case .devices: opened = .devices
            }
        }
    }
```

Then, inside `soundCard`, add `.feature("noise-control")` to the `GlassSegments` noise-control control and `.feature("equalizer")` to the Equalizer `NavigationLink`. The screen no longer owns a `NavigationStack`: the Home tab's stack hosts it.

Run: `grep -n "path\|HomeView\|NavigationStack(path" App/Devices/Rex5/Rex5Screen.swift`
Expected: no output.

- [ ] **Step 6: The REX5 adapter**

`App/Devices/Rex5/Rex5Device.swift`:

```swift
import SwiftUI
import UIKit
import HubCore
import Rex5Kit

/// REX5 behind the HomeDeck contract. EarbudService does the work, as in the standalone app.
@MainActor
@Observable
final class Rex5Device: HomeDevice {
    static let shared = Rex5Device()

    let service = EarbudService.shared
    /// A widget or alert link waiting for Rex5Screen to act on it.
    var pendingLink: DeepLink?

    private init() {
        // REX5 refreshes whenever the app comes to the foreground, as the standalone app did on scenePhase.
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.service.appBecameActive() }
        }
    }

    var status: DeviceStatus {
        let snapshot = service.snapshot
        switch snapshot.link {
        case .connected: return .online(summary: snapshot.cardSummary)
        case .connecting: return .connecting
        default: return .offline(reason: snapshot.statusLine)
        }
    }

    func connect() async { await service.connectThisPhone() }
    func disconnect() async { await service.disconnectThisPhone() }
    func makeScreen() -> AnyView { AnyView(Rex5Screen(service: service, device: self)) }
}
```

- [ ] **Step 7: The registry**

`App/DeviceRegistry.swift`:

```swift
import HubCore
import Rex5Kit
import WalkingPadKit
import MiScaleKit
import PhilipsAirKit
import ZeppelinKit
import XiaomiFanKit
import DreameKit

/// Every device HomeDeck knows. A device session replaces its UnbuiltDevice with its own class.
enum DeviceRegistry {
    static let kinds: [DeviceKind] = [
        DeviceKind(id: "rex5", name: "Noble FoKus Rex5", symbol: "earbuds", link: .bluetooth,
                   featuresURL: Rex5Catalog.featuresURL) { Rex5Device.shared },
        DeviceKind(id: "walkingpad-c2", name: "WalkingPad C2", symbol: "figure.walk", link: .bluetooth,
                   featuresURL: WalkingPadCatalog.featuresURL) { UnbuiltDevice(name: "WalkingPad C2") },
        DeviceKind(id: "mi-scale-s400", name: "Mi Body Composition Scale S400", symbol: "scalemass", link: .bluetooth,
                   featuresURL: MiScaleCatalog.featuresURL) { UnbuiltDevice(name: "Mi Body Composition Scale S400") },
        DeviceKind(id: "philips-ac2729", name: "Philips 2000i AC2729", symbol: "humidifier", link: .wifi,
                   featuresURL: PhilipsAirCatalog.featuresURL) { UnbuiltDevice(name: "Philips 2000i AC2729") },
        DeviceKind(id: "zeppelin-pro", name: "Zeppelin Pro Edition", symbol: "hifispeaker", link: .wifi,
                   featuresURL: ZeppelinCatalog.featuresURL) { UnbuiltDevice(name: "Zeppelin Pro Edition") },
        DeviceKind(id: "xiaomi-fan-2-pro", name: "Xiaomi Standing Fan 2 Pro", symbol: "fan.floor", link: .wifi,
                   featuresURL: XiaomiFanCatalog.featuresURL) { UnbuiltDevice(name: "Xiaomi Standing Fan 2 Pro") },
        DeviceKind(id: "dreame-l40-ultra", name: "Dreame L40 Ultra", symbol: "circle.circle", link: .wifi,
                   featuresURL: DreameCatalog.featuresURL) { UnbuiltDevice(name: "Dreame L40 Ultra") },
    ]
}
```

- [ ] **Step 8: Home tab**

`App/DashboardView.swift`:

```swift
import SwiftUI
import HubCore

/// Home tab: one glass card per added device.
struct DashboardView: View {
    let store: DeviceStore

    var body: some View {
        GlassScreen {
            if store.added.isEmpty {
                CardCaption("No devices yet. Add them in Market.")
            }
            ForEach(store.added) { kind in
                NavigationLink(value: kind.id) { DeviceCard(kind: kind, device: store.device(for: kind)) }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Remove from Home", systemImage: "minus.circle", role: .destructive) { store.remove(kind) }
                    }
            }
        }
        .navigationTitle("HomeDeck")
    }
}

struct DeviceCard: View {
    let kind: DeviceKind
    let device: any HomeDevice

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: kind.symbol).font(.title2).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.name).font(.headline)
                    Text(device.status.cardLine).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
        }
    }
}
```

- [ ] **Step 9: App entry**

Replace the copied entry: `rm -f App/Rex5App.swift` (if it was copied) and write `App/HomeDeckApp.swift`:

```swift
import SwiftUI
import UserNotifications
import HubCore
import Rex5Kit

/// Routes notification taps (REX5 takeover alerts) to a deep link.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var openLink: ((DeepLink) -> Void)?
    var pendingLink: DeepLink?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let text = response.notification.request.content.userInfo["link"] as? String,
           let url = URL(string: text), let link = DeepLink(url: url) {
            if let openLink { openLink(link) } else { pendingLink = link }
        }
        completionHandler()
    }
}

@main
struct HomeDeckApp: App {
    enum HomeTab: Hashable { case home, market, settings }

    @UIApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var store = DeviceStore(kinds: DeviceRegistry.kinds)
    @State private var tab = HomeTab.home
    @State private var homePath: [String] = []

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                Tab("Home", systemImage: "house", value: HomeTab.home) {
                    NavigationStack(path: $homePath) {
                        DashboardView(store: store)
                            .navigationDestination(for: String.self) { id in
                                if let kind = store.kind(id: id) {
                                    store.device(for: kind).makeScreen().environment(\.deviceID, id)
                                }
                            }
                    }
                }
                Tab("Market", systemImage: "square.grid.2x2", value: HomeTab.market) {
                    NavigationStack { MarketView(store: store, openDevice: open) }
                }
                Tab("Settings", systemImage: "gearshape", value: HomeTab.settings) {
                    NavigationStack { HubSettingsView(kinds: store.kinds) }
                }
            }
            .onOpenURL { url in
                if let link = DeepLink(url: url) { openRex5(link) }
            }
            .onAppear {
                delegate.openLink = { openRex5($0) }
                if let pending = delegate.pendingLink {
                    openRex5(pending)
                    delegate.pendingLink = nil
                }
            }
        }
    }

    /// Shows a device's screen on the Home tab.
    private func open(_ kind: DeviceKind) {
        tab = .home
        homePath = [kind.id]
    }

    /// Widgets and REX5 alerts link to rex5:// URLs. They open the REX5 screen, which acts on the link.
    private func openRex5(_ link: DeepLink) {
        guard let kind = store.kind(id: "rex5") else { return }
        Rex5Device.shared.pendingLink = link
        open(kind)
    }
}
```

So this task builds before Task 7, add temporary stubs in `App/MarketView.swift` and `App/HubSettingsView.swift` (Task 7 replaces both files):

```swift
import SwiftUI
import HubCore

struct MarketView: View {
    let store: DeviceStore
    let openDevice: (DeviceKind) -> Void
    var body: some View { Text("Market") }
}
```

```swift
import SwiftUI
import HubCore

struct HubSettingsView: View {
    let kinds: [DeviceKind]
    var body: some View { Text("Settings") }
}
```

- [ ] **Step 10: Build for the simulator**

Run: `xcodebuild -project HomeDeck.xcodeproj -scheme HomeDeck -destination 'platform=iOS Simulator,name=iPhone Air' -derivedDataPath build/dd build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"`
Expected: `** BUILD SUCCEEDED **`. Fix any leftover reference to the removed `LogView` or `ConnectionLog()` that the compiler reports.

- [ ] **Step 11: Run it and follow a REX5 link**

```bash
xcrun simctl boot "iPhone Air" 2>/dev/null; open -a Simulator
xcrun simctl install booted build/dd/Build/Products/Debug-iphonesimulator/HomeDeck.app
xcrun simctl launch booted local.homedeck.app
xcrun simctl io booted screenshot "$TMPDIR/homedeck-home.png"
xcrun simctl openurl booted rex5://tools
xcrun simctl io booted screenshot "$TMPDIR/homedeck-rex5-tools.png"
```

Expected: the first screenshot shows the Home tab titled HomeDeck with "No devices yet. Add them in Market."; the second shows REX5's Tools screen pushed on the Home tab, with Guided reset and no Connection log row. Check that each device symbol renders in Task 7's Market screenshot; if one is blank, use `circle.circle` for it.

- [ ] **Step 12: Journal entry and commit**

Append `## 2026-11-13: Shell app and REX5 migration` to `docs/journal/hub.md`, including what changed in the REX5 code and why.

```bash
git add HomeDeck.xcodeproj App Widgets Shared Config/Signing.xcconfig Config/Team.xcconfig.example docs/journal/hub.md
git commit -m "Shell app: Home tab, registry, REX5 moved in as the first device"
```

---

### Task 7: Market, feature lists, wishlist and Settings

**Files:**
- Replace: `App/MarketView.swift`, `App/HubSettingsView.swift`

**Interfaces:**
- Consumes: `DeviceStore`, `DeviceKind`, `Feature`, `FeatureChoices.shared` (`isHidden`, `setHidden`, `isWanted`, `setWanted`, `wishlist(for:)`), `ConnectionLog.shared` (`entries(for:)`, `shareText(for:)`), `GlassScreen`, `GlassCard`.
- Produces: `MarketView(store:openDevice:)`, `FeatureListView(kind:store:openDevice:)`, `HubSettingsView(kinds:)`, `LogView(kinds:)`.

- [ ] **Step 1: Market and feature lists**

`App/MarketView.swift`:

```swift
import SwiftUI
import HubCore

/// Market tab: every device HomeDeck knows, with how much of it works.
struct MarketView: View {
    let store: DeviceStore
    let openDevice: (DeviceKind) -> Void

    var body: some View {
        GlassScreen {
            ForEach(store.kinds) { kind in
                NavigationLink {
                    FeatureListView(kind: kind, store: store, openDevice: openDevice)
                } label: {
                    MarketTile(kind: kind, isAdded: store.isAdded(kind))
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Market")
    }
}

struct MarketTile: View {
    let kind: DeviceKind
    let isAdded: Bool

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image(systemName: kind.symbol).font(.title2).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.name).font(.headline)
                    Text("\(kind.link == .bluetooth ? "Bluetooth" : "Wi-Fi") · \(kind.workingSummary)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if isAdded { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
            }
        }
    }
}

/// A device's features: Show toggles for what works, Want toggles for the rest, and the wishlist.
struct FeatureListView: View {
    let kind: DeviceKind
    let store: DeviceStore
    let openDevice: (DeviceKind) -> Void
    @State private var choices = FeatureChoices.shared

    private func features(_ status: Feature.Status) -> [Feature] { kind.features.filter { $0.status == status } }

    var body: some View {
        List {
            section("Working", footer: "Switch off to hide it from the device screen.", features(.working)) { feature in
                Binding(get: { !choices.isHidden(feature.id, device: kind.id) },
                        set: { choices.setHidden(!$0, feature.id, device: kind.id) })
            }
            section("Planned", footer: "Switch on to ask for it in the wishlist.", features(.planned), want)
            section("Not planned", footer: "Switch on if you want it after all.", features(.notPlanned), want)
        }
        .navigationTitle(kind.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if store.isAdded(kind) {
                    Button("Open") { openDevice(kind) }
                } else {
                    Button("Add") {
                        store.add(kind)
                        openDevice(kind)
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                if let text = choices.wishlist(for: kind) {
                    ShareLink("Send wishlist", item: text)
                }
            }
        }
    }

    private func want(_ feature: Feature) -> Binding<Bool> {
        Binding(get: { choices.isWanted(feature.id, device: kind.id) },
                set: { choices.setWanted($0, feature.id, device: kind.id) })
    }

    @ViewBuilder
    private func section(_ title: String, footer: String, _ features: [Feature],
                         _ binding: @escaping (Feature) -> Binding<Bool>) -> some View {
        if !features.isEmpty {
            Section {
                ForEach(features) { feature in Toggle(feature.title, isOn: binding(feature)) }
            } header: {
                Text(title)
            } footer: {
                Text(footer)
            }
        }
    }
}
```

- [ ] **Step 2: Settings and the shared log**

`App/HubSettingsView.swift`:

```swift
import SwiftUI
import HubCore

/// Settings tab. Accounts (Xiaomi sign-in) arrive with XiaomiCloudKit in wave 1.
struct HubSettingsView: View {
    let kinds: [DeviceKind]

    var body: some View {
        List {
            Section("Log") {
                NavigationLink("Connection log") { LogView(kinds: kinds) }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
                Text("HomeDeck controls Bluetooth and Wi-Fi home devices from one app. It's an unofficial hobby project, not affiliated with any device maker.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

/// Every device's exchanges, newest first, filterable by device.
struct LogView: View {
    let kinds: [DeviceKind]
    @State private var log = ConnectionLog.shared
    @State private var device: String?

    var body: some View {
        List(Array(log.entries(for: device).reversed().enumerated()), id: \.offset) { _, entry in
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.date.formatted(date: .abbreviated, time: .standard)) · \(entry.device)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(entry.text).font(.callout.monospaced())
            }
        }
        .navigationTitle("Connection log")
        .toolbar {
            ToolbarItem {
                Picker("Device", selection: $device) {
                    Text("All devices").tag(String?.none)
                    ForEach(kinds) { kind in Text(kind.name).tag(Optional(kind.id)) }
                }
                .pickerStyle(.menu)
            }
            ToolbarItem { ShareLink(item: log.shareText(for: device)) }
        }
    }
}
```

- [ ] **Step 3: Build, run and check the Market**

Run the build command from Task 6 Step 10, then install and launch as in Task 6 Step 11. Use the iOS Simulator control tool (tap and screenshot):
1. Market tab: seven tiles; REX5 reads "Bluetooth · 6 of 10 features working", the others "… · 0 of N features working". Every symbol renders.
2. Tap REX5, then Add: the Home tab opens the REX5 screen.
3. Back on Home: a REX5 card with "Offline" (no earbuds in the simulator).
4. Market, REX5, switch off "Battery for each earbud…", open REX5 again: the battery card is gone. Switch it back on.
5. Market, WalkingPad C2, switch on "Set the speed": a "Send wishlist" button appears at the bottom.
6. Settings, Connection log: entries tagged `rex5`, and the device filter works.

Save the screenshots in `research/screenshots/` (git-ignored) for the owner.

- [ ] **Step 4: Journal entry and commit**

Append `## 2026-11-13: Market and Settings` to `docs/journal/hub.md`.

```bash
git add App docs/journal/hub.md
git commit -m "Market with feature lists and wishlist; Settings with the shared log"
```

---

### Task 8: Docs, templates and README

**Files:**
- Create: `docs/templates/protocol.md`, `docs/templates/journal.md`, `docs/adding-a-device.md`, `README.md`, `LICENSE`

**Interfaces:**
- Produces: the docs every device session follows; nothing in code.

- [ ] **Step 1: Protocol template**

`docs/templates/protocol.md`:

````markdown
# <Device>: protocol

Every claim carries one evidence label: **verified on device**, **from APK**, **from open source**, or **guess**.
No real names, addresses, keys or tokens: use placeholders such as `<phone>`, `AA:BB:CC` or `<token>`.

## Device

- Model:
- Firmware tested:
- Vendor app and version (iOS and the Android APK studied):

## Transport

Bluetooth: services, characteristics and their properties. Wi-Fi: address discovery (Bonjour type, UDP broadcast, cloud), port, protocol.

## Keys and sessions

Pairing, tokens, encryption, and where each key comes from (device, vendor cloud, APK constant).

## Packet format

Byte layout with a worked example.

## Commands

| Name | Bytes or endpoint | Payload | Reply | Evidence |
|---|---|---|---|---|

## Pushed updates

What the device sends on its own, and when.

## Quirks

Behaviour that surprised us, with the log line or capture that shows it.

## Sources

Open-source projects (with links and licences), APK classes, own captures in `research/<device>/`.
````

- [ ] **Step 2: Journal template**

`docs/templates/journal.md`:

```markdown
# <Device>: journal

Entries are only ever appended; dead ends stay. No real names, addresses, keys or tokens.

## YYYY-MM-DD: <short title>

**Tried:** what and why.
**Device answered:** anonymized bytes or log lines.
**Conclusion:** what this proves, with its evidence label.
**Next:** the next step.
Article note: optional, anything worth telling in the article.
```

- [ ] **Step 3: The device checklist**

`docs/adding-a-device.md`:

````markdown
# Adding a device

Each device is built by its own session, in its own git worktree, on branch `device/<id>` (for example `device/walkingpad-c2`). The session commits on that branch as it goes. Merging into `main` and every push wait for the owner's explicit yes, after the hub session's review.

A device session changes only:
- `Packages/Sources/<Name>Kit/` and `Packages/Tests/<Name>KitTests/` (plus one test-target line in `Packages/Package.swift`);
- `App/Devices/<Name>/`;
- `docs/devices/<id>/`;
- its one line in `App/DeviceRegistry.swift` (replace `UnbuiltDevice(...)` with the device's class);
- for a Wi-Fi device, `App/Info.plist`: `NSLocalNetworkUsageDescription` (added once, by the first Wi-Fi device) and its Bonjour service type in `NSBonjourServices`.

Raw material (APKs, decompiled code, captures, raw logs) goes in `research/<id>/`, which git ignores. Never copy it into the repo.

## Steps

1. **Inventory.** List every feature of the vendor app in `Packages/Sources/<Name>Kit/features.json` (`working`, `planned` or `notPlanned`). Start `docs/devices/<id>/journal.md` from `docs/templates/journal.md`.
2. **Existing work.** Search for open-source implementations of the device's protocol (Home Assistant integrations, Python libraries, GitHub write-ups). Record each under Sources with its licence. Don't copy code from projects whose licence doesn't allow it; describe the protocol in your own words.
3. **APK, for the gaps only.** The owner puts the vendor's Android app in `research/<id>/`. Unzip it (an `.xapk` is a zip of APKs) and dump the code with Android build-tools' `dexdump -d classes.dex > classes.dex.txt`. Read it; never install or run it.
4. **Probe.** Make the device's module log every raw exchange to the shared log (`ConnectionLog.shared.tagged("<id>")`) and try the commands on the real device. Ask the owner for each physical step.
5. **Protocol doc.** Write `docs/devices/<id>/protocol.md` from `docs/templates/protocol.md`, with an evidence label on every command.
6. **Kit.** Protocol code in `<Name>Kit` (no SwiftUI), tests in `<Name>KitTests` built from real captures with names, addresses and keys replaced. Run `cd Packages && swift test --filter <Name>KitTests`.
7. **App.** The device class (`HomeDevice`) and screens in `App/Devices/<Name>/`, using `App/UI/Glass.swift` and `.feature("<feature id>")` on each part of the screen. Swap the registry line.
8. **On the phone.** Build and install the branch on the owner's iPhone, test each feature with the owner, and update `features.json`.
9. **Finish.** Run `python3 scripts/privacy-scan.py`, look at every image you add (app screens only, never the Home Screen or device names), add the journal entry, and report to the hub session for review.

Secrets (tokens, bind keys) go in the iPhone Keychain only, never in files, logs or test fixtures.
````

- [ ] **Step 4: README and LICENSE**

`README.md`:

````markdown
# HomeDeck

One iPhone app for my Bluetooth and Wi-Fi home devices, replacing their separate vendor apps. Each device is reverse-engineered and built as its own module, the same way as my [REX5 earbuds app](https://github.com/VM-development/noble-rex5-custom-app). The whole process is journaled in `docs/` for an article.

It isn't affiliated with any of the device makers.

## Devices

| Device | Link | Status |
|---|---|---|
| Noble FoKus Rex5 earbuds | Bluetooth | Working |
| WalkingPad C2 | Bluetooth | Planned |
| Mi Body Composition Scale S400 | Bluetooth | Planned |
| Philips 2000i AC2729 | Wi-Fi | Planned |
| Bowers & Wilkins Zeppelin Pro Edition | Wi-Fi | Planned |
| Xiaomi Smart Standing Fan 2 Pro | Wi-Fi | Planned |
| Dreame L40 Ultra | Wi-Fi | Planned |

The app's Market tab shows every feature of every device and whether it works yet.

## How it's built

- `App/`: the SwiftUI shell (Home, Market, Settings) and each device's screens in `App/Devices/`.
- `Packages/`: one Swift package with `HubCore` (the device contract, feature choices, shared log) and one target per device for its protocol code, tested with `swift test`.
- `docs/adding-a-device.md`: the checklist each device follows; `docs/devices/<id>/` holds its protocol doc and journal.

## Build

You need Xcode 27 and an iPhone on iOS 26 or later.

```bash
cp Config/Team.xcconfig.example Config/Team.xcconfig   # then put your team ID in it
git config core.hooksPath hooks                         # privacy check before every push
open HomeDeck.xcodeproj
```

```bash
cd Packages && swift test
```

## License

[MIT](LICENSE). Device and brand names are trademarks of their owners.
````

`LICENSE`: copy `../rex5/LICENSE` and change the year line if needed (`cp ../rex5/LICENSE LICENSE`).

- [ ] **Step 5: Scan, journal entry and commit**

Run: `python3 scripts/privacy-scan.py`
Expected: `privacy-scan: clean`

Append `## 2026-11-13: Docs and templates` to `docs/journal/hub.md`.

```bash
git add README.md LICENSE docs
git commit -m "Docs: device checklist, protocol and journal templates, README"
```

---

### Task 9: On the iPhone, then publish with the owner's yes

**Files:**
- Modify: `docs/journal/hub.md`

- [ ] **Step 1: Install on the iPhone**

Ask the owner to connect the iPhone by cable and unlock it. Find its UDID in `xcrun devicectl list devices` and use it below as `$DEVICE` (never write it into a file).

```bash
xcodebuild -project HomeDeck.xcodeproj -scheme HomeDeck -destination "id=$DEVICE" -configuration Debug \
  -derivedDataPath build/dd -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcrun devicectl device install app --device "$DEVICE" build/dd/Build/Products/Debug-iphoneos/HomeDeck.app
xcrun devicectl device process launch --device "$DEVICE" local.homedeck.app
```

Expected: `** BUILD SUCCEEDED **`, the app installs and launches.

- [ ] **Step 2: Check REX5 with the owner**

With the earbuds out of the case and playing, the owner confirms each item:
1. Market lists seven devices; Add REX5; the Home card shows "L …% · R …%".
2. The REX5 screen shows the battery, switches Off, ANC and Ambient with the confirmation, and an EQ change is audible.
3. The owner adds the HomeDeck widgets (small, medium, Lock Screen line and circles) and they show the same state as the app.
4. A case cycle with the Shortcuts automation rebuilt for "Refresh REX5" from HomeDeck updates the widgets.

Then check for widget crashes:

Run: `xcrun devicectl device info files --device "$DEVICE" --domain-type systemCrashLogs | grep -i homedeck`
Expected: no output.

- [ ] **Step 3: Retire the standalone REX5 app**

Ask the owner to delete the standalone REX5 app from the iPhone, so only HomeDeck connects to the earbuds, then repeat check 2 once.

- [ ] **Step 4: Final checks**

```bash
cd Packages && swift test 2>&1 | tail -1; cd ..
python3 scripts/privacy-scan.py
```

Expected: `Executed … tests, with 0 failures` and `privacy-scan: clean`. Ask the owner to look over `Config/private-patterns.txt` for anything missing.

Append `## 2026-11-13: HomeDeck on the iPhone` to `docs/journal/hub.md` with the results of Step 2 (anonymized), and commit it on `phase-0-shell`.

- [ ] **Step 5: Ask before publishing**

Ask the owner: "Phase 0 works on the phone. Create `main` from `phase-0-shell`, create the public GitHub repo VM-development/homedeck, and push?" Only on an explicit yes:

```bash
git branch main phase-0-shell
GH_TOKEN=$(gh auth token --user VM-development) gh repo create VM-development/homedeck --public \
  --description "One iPhone app for my Bluetooth and Wi-Fi home devices, reverse-engineered one by one" \
  --source . --remote origin
git push -u origin main
```

Expected: the pre-push hook prints `privacy-scan: clean`, then the push succeeds. If the hook blocks the push, fix the reported file, never bypass the hook.

Phase 0 is done; the hub session then starts the wave-1 device sessions (spec, "Phase 1").
