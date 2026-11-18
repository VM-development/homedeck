---
name: add-device
description: Use when adding a smart home device to HomeDeck (start it with the vendor's Android app, scaffold its kit, device.json, class and screen), reverse-engineering a Bluetooth or Wi-Fi device's protocol, building or extending a device module (kit, tests, device class, screen), probing a device from the Mac, or testing a module on the owner's iPhone and reading its connection log.
---

# Adding a device to HomeDeck

HomeDeck replaces vendor apps with one iPhone app. Each device is reverse-engineered, built as its own module, and checked feature by feature on the owner's real device and iPhone, one device at a time. The repo will be public, so the privacy rules come before everything else.

This skill extends `docs/adding-a-device.md` (the checklist and the files a device session may touch) with what the first seven devices taught. Their journals in `docs/devices/*/journal.md` hold the details; read the one closest to your device (same vendor, same transport) before starting.

## The tool: `hd.py`

Three commands do what used to be typed by hand (`python3 .claude/skills/add-device/hd.py --help`):

| Command | Does |
|---|---|
| `hd.py new <id> --kit <Name> --name "<Display name>" --symbol <sf-symbol> --link bluetooth\|wifi --category <category> [--apk <file>]` | Creates the kit (`device.json`, `Catalog.swift`), its test target, `App/Devices/<Name>/` (device class and screen), the `Package.swift` and registry lines, and the journal and protocol notes. With `--apk`, copies the vendor app into `research/<id>/apk/`, unpacks an `.xapk`, and dexdumps every `classes*.dex` into `research/<id>/dex/`. |
| `hd.py phone [--phone <udid>]` | Builds, installs and launches on the connected iPhone; copies the two config files into a worktree that lacks them. |
| `hd.py log <id> [--phone <udid>]` | Pulls the connection log into `research/<id>/logs/` and prints that device's lines, masked. |

Every device is described by one file, `Packages/Sources/<Name>Kit/device.json`: id, name, SF Symbol, link, category (`fitness`, `music`, `climate`, `cleaning`, `kitchen`, `other`) and the feature list. The registry line only says which class to create. `CatalogTests` decodes every `device.json` it finds, so a new kit needs no test line.

## Rules

- **Branch.** Work on `device/<id>` in its own worktree, branched from `phase-0-shell` (the integration branch until `main` exists); in a worktree the app made on another branch, rename it with `git branch -m device/<id>`. `<id>` is the kebab-case model, as in the registry (`xiaomi-fan-2-pro`). Commit on that branch as you go. Merging (fast-forward into `phase-0-shell`) and any push need the owner's explicit yes, after the hub session's review.
- **Scope.** Touch only the files the checklist lists. A shared file (`App/Info.plist`, `App/UI/Glass.swift`, HubCore, `Config/*.example`, README) only when the device needs it, and list it under "Shared changes" in the hub journal entry.
- **Raw material** (APKs, decompiled code, captures, pulled logs, probe scripts) lives in `research/<id>/`, which git ignores. Never copy it into the repo.
- **No private values in the repo:** people's names, room names, Wi-Fi names, device names, IPs, MACs, device ids, serials, tokens, keys, the owner's health data. Docs and tests use placeholders (`<ip>`, `<token>`, `AA:BB:CC`) and made-up values.
- **Mask what you print.** Pipe any output that may hold a private value through `python3 .claude/skills/add-device/mask.py`. It masks every private pattern (in the encodings the privacy scan knows), home-network IPs and MACs. Write probe scripts so they print ids, names and keys masked or not at all. A Bonjour TXT record carries the room name (`snm`); an extractor's output carries every key.
- **New private values** (a device's IP, id, MAC or token, a vendor constant, a room or Wi-Fi name) are appended to `Config/private-patterns.txt` in the main checkout, one per line, without echoing them: a short script that copies the value from the file it sits in, or ask the owner. Never print or read that file, and never create it in a worktree.
- **The owner's secrets** (tokens, bind keys, cloud sessions) go in the iPhone Keychain (`HubCore/Keychain.swift`), entered on the device's setup screen. Never in files, logs or test fixtures. For a cloud account keep the session tokens, not the password. If the owner pastes keys into the chat, don't repeat them; add them to the patterns.
- **Vendor constants** (a fixed LAN secret, an app's salt or signing key) go in the git-ignored `Config/Secrets.xcconfig`, hex-encoded (xcconfig cuts a value at `//` and has no quoting), as `<VENDOR>_<WHAT>_HEX`. Write it into both copies, the worktree's for your builds and the main checkout's so it survives the merge, without printing it. Add the empty key and a comment naming its public source to `Secrets.xcconfig.example`, pass it through `Info.plist` as `<Vendor><What>` = `$(<VENDOR>_<WHAT>_HEX)`, decode it in the device class (`secret(_:)` in `DreameDevice.swift`), and name the source in `protocol.md`. The app must build without it, and the device then says so. Use only constants already published in open source; don't lift unpublished keys out of an APK to call a vendor's cloud.

## 1. Start

1. Ask the owner, with one question each: the device's display name, its category, and the vendor's Android app (the path to an `.apk` or `.xapk`, or skip when open source covers the protocol). APKPure and similar sites offer `.xapk` downloads; the owner downloads it, never you.
2. Make the worktree on `device/<id>`, then: `python3 .claude/skills/add-device/hd.py new <id> --kit <Name> --name "<Display name>" --symbol <sf-symbol> --link <link> --category <category> --apk <file>`. Pick an SF Symbol that exists (`fan.floor`, `scalemass`, `hifispeaker`).
3. `python3 scripts/privacy-scan.py` must print `clean`.

`Config/Team.xcconfig` and `Config/Secrets.xcconfig` are git-ignored and live only in the main checkout; `hd.py phone` copies them into the worktree (without `Team.xcconfig` phone signing fails). Never print them. Delete them before `git worktree remove`. The scan finds the patterns file in the main checkout by itself.

## 2. Can the phone reach the device?

Ask this before any protocol work. Four devices needed it:
- The fan and the purifier were on another Wi-Fi. Their vendor apps still worked through the cloud, which hid it. The owner moved each to the phone's Wi-Fi in the vendor app (the fan got a new token and IP).
- The kettle wasn't on Wi-Fi at all; the owner reports Bluetooth.
- The robot needed the owner's vendor-app password; a Google-login account has to set one in the app first.

From the Mac it takes a minute: ping, `dns-sd -B _<type>._tcp`, a unicast sweep of the /24 on the device's port, the vendor's broadcast hello. Also ask the owner to close the vendor app while testing: the pad talks to one phone at a time, and Xiaomi Home can stop the scale broadcasting.

## 3. Inventory and research

1. Every feature of the vendor app goes in the `features` list of `Packages/Sources/<Name>Kit/device.json` (`working` or `planned`); the ids are what the screen's `.feature("…")` uses. `hd.py new` started the journal and protocol notes in `docs/devices/<id>/`.
2. Open source first: Home Assistant integrations, Python libraries, write-ups. Record each with its licence. MIT and Apache: learn from it. GPL or no licence: facts only. Always describe the protocol in your own words; never copy code.
3. The APK only for the gaps. `hd.py new --apk` leaves `research/<id>/dex/classes*.dex.txt`: grep them, and read around the hits; never install or run the app. Check a known constant by presence (`grep -c`), never print it. REA (`github.com/morluto/rea`, an MCP server for reverse engineering) can decompile APKs into Java-like code instead, once its JADX bridge (`jadx-headless-mcp` 0.7.1 JAR, set as `REA_JADX_MCP_JAR`) is set up; it isn't set up here, and none of the first seven devices used it. Often the device's panel is downloaded at runtime and isn't in the APK (the scale's plugin, the kettle's Tuya panel, the robot's map path).
4. Every claim in `protocol.md` carries one label: **verified on device**, **from APK**, **from open source** or **guess**. Sources are often wrong in details (advertised name, port, a "read-only" property that is writable), so keep the label honest until the device confirms it.

## 4. Probe before building

Wi-Fi: probe from the Mac before writing app code, with small stdlib Python scripts in `research/<id>/`, read-only first, output masked. Mac probes found the fan's network problem, the purifier's subscription limit and the speaker's volume echo faster than phone builds would have.

Bluetooth: the Mac can't scan (the shell's host app has no Bluetooth permission, and the owner prefers not to grant it). Build the module with every exchange logged and probe from the phone.

Append a journal entry after each probe session, not only at the end.

## 5. Kit and tests

- `Packages/Sources/<Name>Kit/`: protocol code only, no SwiftUI. Codec, cipher and state parsing as pure functions where possible.
- `hd.py new` added the `<Name>KitTests` target with one test that the `device.json` is bundled. Tests in `Packages/Tests/<Name>KitTests/` use real captures with every name, id, address and key replaced by made-up ones; say so in the file's comment. Published test vectors make good fixtures (the scale's tests use five).
- `cd Packages && swift test --filter <Name>KitTests`

## 6. Device class and screen

In `App/Devices/<Name>/`, following an existing device of the same transport:
- `<Name>Device`: `@MainActor @Observable final class … : HomeDevice` with `static let id = "<id>"` and `ConnectionLog.shared.tagged(Self.id)`; UserDefaults and Keychain keys start with `<id>.`. Its `init` runs at every launch, background Bluetooth relaunches included: keep it cheap, no permission prompts, and start Bluetooth or networking only for a device set up before. A Bluetooth device owns its `CBCentralManager` with restoration id `homedeck.<id>`. The shell never calls `connect()`/`disconnect()`; the device connects on its own.
- Log every raw exchange and every user action, with keys and tokens redacted: the log is how features get proved, and it can be shared.
- `<Name>Screen`: setup while not set up, then a compact screen: a `DeviceHeader` (status, plus the main action as a `RoundButton`), readings as `CardStat` grids, settings as `MenuRow`s in one `GlassCard`, on/off settings as `ToggleTile`s and one-shot actions as `ActionTile`s in a `TileRow`, and Forget/Change in a toolbar `Menu("More", systemImage: "ellipsis.circle")` with a centred alert. The pieces are in `App/UI/Glass.swift` and `App/UI/DeviceUI.swift`; put `.feature("<feature id>")` on each part. A component's second user moves it into those files. A device that can switch on and off conforms to `PowerSwitchable`, which puts a power button on its Home tile.
- `hd.py new` wrote a starter class (status `.notSetUp`, a tagged log) and a screen with a `DeviceHeader`, and registered them. For a device already listed with `UnbuiltDevice(...)` (the kettle), replace that in `App/DeviceRegistry.swift` instead.
- Wi-Fi: add the device's Bonjour type to `NSBonjourServices` in `Info.plist`. `NSLocalNetworkUsageDescription` and `NSAllowsLocalNetworking` (plain HTTP) are already there.

## 7. The phone loop

The owner connects the iPhone by cable and unlocks it (a charge-only cable shows the phone as unavailable).

```bash
python3 .claude/skills/add-device/hd.py phone       # build, install, launch
python3 .claude/skills/add-device/hd.py log <id>    # after each round: pull the log, print this device's lines masked
```

With several phones connected, pass `--phone <udid>` (from `xcrun devicectl list devices | python3 .claude/skills/add-device/mask.py`); never write the identifier into a file. Tell the owner exactly what to do, one physical step at a time.

The log keeps the newest 500 lines and another device's polling fills it fast, so pull right after each test. After a crash: `xcrun devicectl device info files --device <udid> --domain-type systemCrashLogs | grep -i homedeck`.

**The log decides, not the memory of the test.** Owners over-report: a 12-second walk "counted distance" (it couldn't move yet), and three speaker features were reported working with no trace in the log. Go through the features one by one and ask "did you try X?" with the log open. A feature is working only when a log line shows the command and the device's confirming answer. An action that leaves no line gets one, and is tried again.

## 8. Finish

- `device.json` features: `working` only when verified on device. A feature that couldn't be tested (a broken water tank, no update available) stays `planned`, and the journal says why.
- `docs/devices/<id>/protocol.md` from `docs/templates/protocol.md`, every claim labelled. The journal is append-only and keeps dead ends.
- README device table: the device's status.
- `docs/journal/hub.md`: a short entry pointing to the device journal, with the shared changes.
- Images: PNG app screens only, looked at before committing; never the Home Screen or device names. The scan refuses photo files.
- `python3 scripts/privacy-scan.py` must print `clean`. Then commit on the branch and report to the hub session.

If the only way in needs a key from the vendor's cloud and the owner declines every route (like the kettle), stop: journal the dead ends, set README to "Paused", and say what would restart it.

## What devices did

| Seen | Cause | Do |
|---|---|---|
| Vendor app works, device silent on the LAN | Device on another Wi-Fi; the vendor app goes through the cloud | Owner moves it to the phone's Wi-Fi in the vendor app; take the new token and IP |
| `success` or `code 0`, nothing changed | A reply isn't proof: the purifier once ignored six "successful" commands | Confirm each command from the next status or push |
| The reply carries the old value | The speaker's set_volume reply echoes stale volume; the push brings the new one | Trust only the change event or a fresh read |
| A documented parameter is ignored | The speaker ignores `muted: true` | Emulate it (volume 0, then restore) |
| Pushes stop, sync still answers | Subscription slots fill up and aren't forgotten (purifier) | Subscribe from a fixed port and token, cancel on remove; a power cycle clears it |
| Crash building a URL from a found address | Network.framework addresses can carry `%en0` | Build the address from its bytes or cut at `%`; no force-unwraps |
| Bonjour's port refuses | The API is on another port (42425, not the advertised 45525) | Probe ports; don't trust the advertised one |
| Multicast discovery silent | Also needs Apple's multicast entitlement on iOS | Unicast sweep of the /24 |
| Stored history always empty | The pad keeps nothing for apps | Record it in HomeDeck |
| Key held by a vendor cloud | Xiaomi bind keys and tokens, Tuya local keys | The owner runs an extractor (Xiaomi Cloud Tokens Extractor, one `uv run`); never the vendor's private app keys |
| Map upside down or mirrored | Orientation differs per app and robot | Compare with the vendor app on the owner's phone |

## Screen mistakes already made

- A slider snapped back on release: its binding read a copy of the state from the last draw. Keep the dragged value in `@State` and send it on release.
- A confirmation dialog in a Form appeared in a corner: use a centred alert with Cancel.
- iOS hides bottom toolbars in a tab-bar app: put the button in the list.
- A reply that arrived after Forget marked the device "Offline": drop replies once the device isn't set up.
