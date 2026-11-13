# HomeDeck: one iPhone app for every home device

Date: 2026-11-13. Status: design approved section by section in conversation; this document collects it.

## Goal

HomeDeck is a single iPhone app that controls all of the owner's Bluetooth and Wi-Fi home devices and replaces the separate vendor apps. Each device gets its own module, built by reverse engineering in the same way as the REX5 earbuds app (github.com/VM-development/noble-rex5-custom-app). Modules are built in parallel, one Claude session per device. Every step is journaled so that the process can be written up as an article. A reusable Claude skill is distilled from the work at the end.

## Decisions

| Topic | Decision |
|---|---|
| Control path | Local control first. A vendor cloud is allowed where it is the only way, and mostly only once, to fetch device keys. |
| Repo | New public GitHub repo `homedeck` under VM-development, separate from REX5. |
| Structure | One app, one Swift package per device, one small core package. |
| Device market | In-app catalog of devices, with a per-device feature list that drives both what the device screen shows and what gets built next. |
| Platform | iPhone only, iOS 26 minimum (Liquid Glass), SwiftUI, Xcode 27. |
| Design | Same as REX5: plain `systemGroupedBackground`, `.clear` glass, no decorative gradients. |
| Devices of the same kind | One of each. Adding a second device of a kind is out of scope. |
| REX5 | Stays a separate app; HomeDeck has no REX5 module (owner decision during the Phase 0 phone test, 2026-11-13). |

## Devices

All expectations below are unverified. Checking them is step 2 of each device's checklist.

| Device | Link | Vendor app (iOS) | Expectation, unverified | Wave |
|---|---|---|---|---|
| KingSmith WalkingPad C2 | Bluetooth | KS Fit | Open-source projects (for example `ph4-walkingpad`) describe its BLE protocol | 1 |
| Philips 2000i Series AC2729/13 | Wi-Fi | Philips Air+ | Local encrypted CoAP protocol, implemented by open-source Home Assistant integrations | 1 |
| Bowers & Wilkins Zeppelin Pro Edition | Wi-Fi | B&W Music | Playback and volume through AirPlay; app-only settings (EQ, light) use an unknown protocol | 1 |
| Xiaomi Smart Standing Fan 2 Pro | Wi-Fi | Mi Home | Local Xiaomi MIoT protocol with a per-device token from the Xiaomi cloud | 2 |
| Mi Mijia Body Composition Scale S400 | Bluetooth | Mi Home / Zepp Life | Measurements in encrypted BLE advertisements; bind key from the Xiaomi cloud | 2 |
| Dreame L40 Ultra CE | Wi-Fi | Dreamehome / Mi Home | Newer Dreame models are often controllable only through Dreame's cloud | 2 |
| Shared: Xiaomi cloud keys | Cloud | Mi Home | Sign in once, fetch tokens and bind keys for the Xiaomi devices | 1 |

The owner provides each vendor's Android APK in `research/<device>/`. Sessions decompile and read APKs; they never run them, and never download APKs themselves.

## Architecture

### Repo layout

```
homedeck/
  App/                          SwiftUI shell
    DeviceRegistry.swift        one line per device kind
    Devices/<Name>/             the device's screens and its HomeDevice class
  Widgets/                      no widget extension until a device needs one
  App/UI/Glass.swift            glass components from REX5 (iOS 26 APIs)
  Packages/                     one Swift package, product HomeDeckKits
    Package.swift               one target per device, so adding a device never edits the Xcode project
    Sources/HubCore/            contract, log, feature choices, the .feature() modifier
    Sources/<Device>Kit/        one per device: protocol code and features.json
    Sources/XiaomiCloudKit/     Xiaomi sign-in, key fetch and Keychain storage (wave 1)
    Tests/<Target>Tests/        tests per target
  docs/
    adding-a-device.md          the checklist every device session follows
    templates/protocol.md       template for a device's protocol doc
    templates/journal.md        template for a device's journal
    devices/<name>/protocol.md
    devices/<name>/journal.md
    journal/hub.md              the shell's own journal
  research/                     git-ignored: APKs, decompiled code, probe dumps, raw logs
  scripts/privacy-scan.py
  hooks/pre-push                enabled with `git config core.hooksPath hooks`
  Config/Signing.xcconfig       includes the git-ignored Team.xcconfig
  Config/private-patterns.txt   git-ignored: the owner's real values to scan for
```

The Xcode project uses synchronized folders, as REX5 does, and references `Packages/` as one local Swift package. Bundle ID `local.homedeck.app`; App Group `group.local.homedeck.app`.

### Package rules

- A `<Device>Kit` target holds protocol code only: packet builders, parsers, state types. It does not import SwiftUI and does not depend on HubCore; it exposes `<Name>Catalog.featuresURL`. It is tested with `swift test` on the Mac, without the phone.
- The device's `HomeDevice` class, its CoreBluetooth or network transport, and its screens live in `App/Devices/<Name>/`.
- Each Bluetooth module owns its own `CBCentralManager`, with restoration identifier `homedeck.<id>`. There is no shared Bluetooth layer until two devices need coordinating.
- A device session changes only its package target (and one test-target line in `Package.swift`), its `App/Devices/<Name>/` folder, its `docs/devices/<name>/` folder, and its one line in `DeviceRegistry.swift`.

### Contract (HubCore)

```swift
public enum Link: String, Codable, Sendable { case bluetooth, wifi }

public struct Feature: Codable, Identifiable, Sendable {
    public enum Status: String, Codable, Sendable { case working, planned, notPlanned }
    public let id: String          // "speed"
    public let title: String       // "Set the speed"
    public let status: Status
}

public enum DeviceStatus: Equatable, Sendable {
    case notSetUp
    case offline(reason: String?)
    case connecting
    case online(summary: String)   // "Walking, 3.5 km/h"
}

public struct DeviceKind {
    public let id: String          // "walkingpad-c2"
    public let name: String        // "WalkingPad C2"
    public let symbol: String      // SF Symbol name
    public let link: Link
    public let features: [Feature] // decoded from the package's features.json
    public let makeDevice: @MainActor () -> any HomeDevice
}

@MainActor public protocol HomeDevice: AnyObject, Observable {
    var status: DeviceStatus { get }
    func connect() async
    func disconnect() async
    func makeScreen() -> AnyView   // includes first-time setup while status is .notSetUp
}
```

`features.json` lives in each `<Device>Kit` as a processed package resource:

```json
[
  { "id": "speed", "title": "Set the speed", "status": "working" },
  { "id": "firmware-update", "title": "Firmware update", "status": "notPlanned" }
]
```

### Device market

- The Market tab lists every registered `DeviceKind`: icon, name, link type, and "N of M features working".
- Add stores the kind's id in the added-devices list, shows its card on Home, and opens its screen, which runs setup while the status is `.notSetUp`.
- Tapping a kind opens its feature list:
  - **Working** features have a Show toggle. Hidden features disappear from the device screen through the HubCore modifier `.feature("<id>")`.
  - **Planned** and **Not planned** features have a Want toggle.
  - **Send wishlist** opens the share sheet with a plain-text list, "HomeDeck wishlist for <name>:" followed by one "- <title> (<id>)" line per wanted feature. The owner pastes it into that device's session.
- Show and Want choices are stored on the phone in `UserDefaults` by HubCore's `FeatureChoices`. What exists and what works is stored only in the repo's `features.json`.
- Long-pressing a Home card offers Remove from Home, which takes it off the added list without disconnecting, because the device may be in use. Once Keychain storage exists, removal also deletes the device's Keychain items.

## Shell app

### Tabs

| Tab | Content |
|---|---|
| Home | One glass card per added device: symbol, name, status line. Tap opens the device screen. |
| Market | Catalog and feature lists, as above. |
| Settings | Accounts (Xiaomi sign-in), the shared log with a per-device filter, About. |

### REX5

REX5 stays a separate app and HomeDeck has no REX5 module; see the REX5 row under Decisions.

### Shared pieces

- **HubCore:** the contract, the log (every line tagged with a device id), `FeatureChoices` and the `.feature()` modifier. The glass components from REX5's `Glass.swift` live in `App/UI/Glass.swift`, because they use iOS 26 APIs while the package stays testable on the Mac.
- **XiaomiCloudKit:** a separate target built in wave 1, which also adds Keychain storage, its first user. It signs in to the owner's Xiaomi account, lists devices, fetches each device's local token or BLE bind key, and stores them in the Keychain. The owner types the password; the app never stores it.

### Permissions

Bluetooth (WalkingPad, scale), Local Network with the Bonjour service types each Wi-Fi module needs (fan, Philips, Zeppelin), and the `bluetooth-central` background mode.

### Failure handling

- A device that can't be reached shows "Offline" on its card and the reason in its screen. Other devices are unaffected.
- Every exchange with a device goes into the log, which is the first evidence a device session reads.

## Documentation, journal, privacy

### protocol.md (per device, from `docs/templates/protocol.md`)

Headings, in order: Device (model, firmware tested, vendor app and version); Transport; Keys and sessions; Packet format; Commands; Pushed updates; Quirks; Sources.

The Commands table has the columns Name, Bytes or endpoint, Payload, Reply, Evidence. Evidence is one of: **verified on device**, **from APK**, **from open source**, **guess**.

### journal.md (per device, from `docs/templates/journal.md`)

Dated entries, only ever appended: what was tried and why; what the device answered (anonymized bytes or log lines); conclusion; next step. Dead ends stay. An entry may end with "Article note:" for anything worth telling.

### adding-a-device.md

1. List the vendor app's features in `features.json`.
2. Look for existing open-source protocol work; record it under Sources.
3. Decompile the APK from `research/<device>/`, for the gaps only.
4. Probe the real device and log the raw exchanges into `research/<device>/`.
5. Write `protocol.md`.
6. Build `<Device>Kit`, with tests built from real captures with names, addresses and keys replaced.
7. Build the screens and add the registry line.
8. Test on the phone; update `features.json`.
9. Run the privacy scan, add the journal entry, report to the hub session for merging.

### Privacy for a public repo

- `research/`, `Config/Team.xcconfig` and `Config/private-patterns.txt` are git-ignored.
- `scripts/privacy-scan.py` reads `Config/private-patterns.txt` (one literal per line: names, device names, MAC addresses, IP addresses, Wi-Fi name, serial numbers, account IDs, tokens). For each line it searches the files to be pushed for the literal, case-insensitive; its hex form with and without spaces; and its base64 form. It also lists image metadata. Any hit fails the scan.
- `hooks/pre-push` runs the scan and blocks the push on failure.
- Screenshots show app screens only: never the Home Screen, never device names. The session looks at each image before adding it, because the scan can't judge pixels.
- Secrets live only in the iPhone Keychain, never in files, logs or test fixtures.
- Vendor APKs, decompiled code and firmware never enter the repo.

## Workflow

### Phase 0: the shell (one session)

Builds the repo, HubCore, the market, the templates, `adding-a-device.md`, the privacy scan and hook, and a starting `features.json` for each of the six devices. A starting list contains the features expected from each vendor app, all `planned`; the device session replaces it with a real inventory.

Done when:
- HomeDeck runs on the owner's iPhone;
- the Market lists all six devices;
- `swift test` passes for HubCore and the catalogs;
- the pre-push hook blocks a push containing a test pattern;
- the public GitHub repo exists (created only after the owner's yes).

### Phase 1: device sessions in two waves

| Wave | Sessions |
|---|---|
| 1 | XiaomiCloudKit, WalkingPad C2, Philips AC2729, Zeppelin Pro |
| 2 | Xiaomi fan, Mi S400 scale, Dreame L40 Ultra |

At most four sessions run at once. Wave-2 sessions may start research before XiaomiCloudKit is merged, but test on the device only after it is.

Each device session runs in its own git worktree on branch `device/<name>` and follows `adding-a-device.md`. It installs its own branch's build on the phone for testing; the owner's everyday build is `main`.

### Commit rule

- Device sessions may commit on their own `device/<name>` branch without asking.
- Merging into `main` and every push to GitHub need the owner's explicit yes.

### Merging

The hub session reviews a finished branch, runs that device's `swift test` and the privacy scan, and with the owner's yes merges into `main` and pushes.

### Skill

After wave 1, a session distills `adding-a-device.md` and the wave-1 journals into a Claude skill in the repo (`.claude/skills/`), covering how to reverse-engineer a smart device and build its HomeDeck module. Wave 2 uses it and refines it.

### Article

After wave 2, a session drafts the article from the journals, the git history and the evidence labels, in the compact style of the REX5 post. The owner edits and publishes it.

## Out of scope

Two devices of the same kind; Android or Mac apps; HomeKit or Matter bridging; scenes and automations; a shared Bluetooth layer; generic widgets for every device; syncing the wishlist between phone and Mac.

## Risks

- The Dreame L40 Ultra may be cloud-only, which conflicts with local-first but is allowed by the cloud rule.
- Xiaomi sign-in may require extra verification steps (two-factor codes, captchas). The owner completes those; the app may need an in-app web view for sign-in.
- The Zeppelin Pro may offer no local control beyond AirPlay; then its module covers only what AirPlay and any discovered protocol allow.
- One iPhone and one owner limit how much on-device testing happens in parallel.
