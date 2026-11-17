---
name: add-device
description: Use when adding a smart home device to HomeDeck, reverse-engineering a Bluetooth or Wi-Fi device's protocol, building or extending a device module (kit, tests, device class, screen), probing a device from the Mac, or testing a module on the owner's iPhone and reading its connection log.
---

# Adding a device to HomeDeck

HomeDeck replaces vendor apps with one iPhone app. Each device is reverse-engineered, built as its own module, and checked feature by feature on the owner's real device and iPhone, one device at a time. The repo will be public, so the privacy rules come before everything else.

This skill extends `docs/adding-a-device.md` (the checklist and the files a device session may touch) with what the first seven devices taught. Their journals in `docs/devices/*/journal.md` hold the details; read the one closest to your device (same vendor, same transport) before starting.

## Rules

- **Branch.** Work on `device/<id>` in its own worktree, branched from `phase-0-shell` (the integration branch until `main` exists); in a worktree the app made on another branch, rename it with `git branch -m device/<id>`. `<id>` is the kebab-case model, as in the registry (`xiaomi-fan-2-pro`). Commit on that branch as you go. Merging (fast-forward into `phase-0-shell`) and any push need the owner's explicit yes, after the hub session's review.
- **Scope.** Touch only the files the checklist lists. A shared file (`App/Info.plist`, `App/UI/Glass.swift`, HubCore, `Config/*.example`, README) only when the device needs it, and list it under "Shared changes" in the hub journal entry.
- **Raw material** (APKs, decompiled code, captures, pulled logs, probe scripts) lives in `research/<id>/`, which git ignores. Never copy it into the repo.
- **No private values in the repo:** people's names, room names, Wi-Fi names, device names, IPs, MACs, device ids, serials, tokens, keys, the owner's health data. Docs and tests use placeholders (`<ip>`, `<token>`, `AA:BB:CC`) and made-up values.
- **Mask what you print.** Pipe any output that may hold a private value through `python3 .claude/skills/add-device/mask.py`. It masks every private pattern (in the encodings the privacy scan knows), home-network IPs and MACs. Write probe scripts so they print ids, names and keys masked or not at all. A Bonjour TXT record carries the room name (`snm`); an extractor's output carries every key.
- **New private values** (a device's IP, id, MAC or token, a vendor constant, a room or Wi-Fi name) are appended to `Config/private-patterns.txt` in the main checkout, one per line, without echoing them: a short script that copies the value from the file it sits in, or ask the owner. Never print or read that file, and never create it in a worktree.
- **The owner's secrets** (tokens, bind keys, cloud sessions) go in the iPhone Keychain (`HubCore/Keychain.swift`), entered on the device's setup screen. Never in files, logs or test fixtures. For a cloud account keep the session tokens, not the password. If the owner pastes keys into the chat, don't repeat them; add them to the patterns.
- **Vendor constants** (a fixed LAN secret, an app's salt or signing key) go in the git-ignored `Config/Secrets.xcconfig`, hex-encoded (xcconfig cuts a value at `//` and has no quoting), as `<VENDOR>_<WHAT>_HEX`. Write it into both copies, the worktree's for your builds and the main checkout's so it survives the merge, without printing it. Add the empty key and a comment naming its public source to `Secrets.xcconfig.example`, pass it through `Info.plist` as `<Vendor><What>` = `$(<VENDOR>_<WHAT>_HEX)`, decode it in the device class (`secret(_:)` in `DreameDevice.swift`), and name the source in `protocol.md`. The app must build without it, and the device then says so. Use only constants already published in open source; don't lift unpublished keys out of an APK to call a vendor's cloud.

## 1. Fresh worktree

```bash
MAIN=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
cp "$MAIN/Config/Team.xcconfig" "$MAIN/Config/Secrets.xcconfig" Config/
python3 scripts/privacy-scan.py
```

Both files are git-ignored and live only in the main checkout; without `Team.xcconfig` phone signing fails. Never print them. The scan finds the patterns file in the main checkout by itself.

## 2. Can the phone reach the device?

Ask this before any protocol work. Four devices needed it:
- The fan and the purifier were on another Wi-Fi. Their vendor apps still worked through the cloud, which hid it. The owner moved each to the phone's Wi-Fi in the vendor app (the fan got a new token and IP).
- The kettle wasn't on Wi-Fi at all; the owner reports Bluetooth.
- The robot needed the owner's vendor-app password; a Google-login account has to set one in the app first.

From the Mac it takes a minute: ping, `dns-sd -B _<type>._tcp`, a unicast sweep of the /24 on the device's port, the vendor's broadcast hello. Also ask the owner to close the vendor app while testing: the pad talks to one phone at a time, and Xiaomi Home can stop the scale broadcasting.

## 3. Inventory and research

1. Every feature of the vendor app goes in `Packages/Sources/<Name>Kit/features.json` (`working`, `planned`, `notPlanned`); the ids are what the screen's `.feature("…")` uses. Start `docs/devices/<id>/journal.md` from `docs/templates/journal.md`. If the device has no kit yet, the hub session adds the catalog entry first (kit with `Catalog.swift` and `features.json`, its name in `kits` in `Package.swift`, an `UnbuiltDevice` registry line).
2. Open source first: Home Assistant integrations, Python libraries, write-ups. Record each with its licence. MIT and Apache: learn from it. GPL or no licence: facts only. Always describe the protocol in your own words; never copy code.
3. The APK only for the gaps. The owner puts it in `research/<id>/` (an `.xapk` is a zip of APKs). Dump with `dexdump -d classes.dex > classes.dex.txt` and grep; never install or run it. Check a known constant by presence (`grep -c`), never print it. Often the device's panel is downloaded at runtime and isn't in the APK (the scale's plugin, the kettle's Tuya panel, the robot's map path).
4. Every claim in `protocol.md` carries one label: **verified on device**, **from APK**, **from open source** or **guess**. Sources are often wrong in details (advertised name, port, a "read-only" property that is writable), so keep the label honest until the device confirms it.

## 4. Probe before building

Wi-Fi: probe from the Mac before writing app code, with small stdlib Python scripts in `research/<id>/`, read-only first, output masked. Mac probes found the fan's network problem, the purifier's subscription limit and the speaker's volume echo faster than phone builds would have.

Bluetooth: the Mac can't scan (the shell's host app has no Bluetooth permission, and the owner prefers not to grant it). Build the module with every exchange logged and probe from the phone.

Append a journal entry after each probe session, not only at the end.

## 5. Kit and tests

- `Packages/Sources/<Name>Kit/`: protocol code only, no SwiftUI. Codec, cipher and state parsing as pure functions where possible.
- Add `.testTarget(name: "<Name>KitTests", dependencies: ["<Name>Kit"])` to `Packages/Package.swift`. Tests in `Packages/Tests/<Name>KitTests/` use real captures with every name, id, address and key replaced by made-up ones; say so in the file's comment. Published test vectors make good fixtures (the scale's tests use five).
- `cd Packages && swift test --filter <Name>KitTests`

## 6. Device class and screen

In `App/Devices/<Name>/`, following an existing device of the same transport:
- `<Name>Device`: `@MainActor @Observable final class … : HomeDevice` with `static let id = "<id>"` and `ConnectionLog.shared.tagged(Self.id)`; UserDefaults and Keychain keys start with `<id>.`. Its `init` runs at every launch, background Bluetooth relaunches included: keep it cheap, no permission prompts, and start Bluetooth or networking only for a device set up before. A Bluetooth device owns its `CBCentralManager` with restoration id `homedeck.<id>`. The shell never calls `connect()`/`disconnect()`; the device connects on its own.
- Log every raw exchange and every user action, with keys and tokens redacted: the log is how features get proved, and it can be shared.
- `<Name>Screen`: setup while not set up, then the controls, built from `GlassScreen`, `GlassCard`, `CardRow`, `GlassSegments`, `GlassChip`, `BigButton`, `RoundButton` in `App/UI/Glass.swift`, with `.feature("<feature id>")` on each part. A component's second user moves it into `Glass.swift`.
- Replace the device's `UnbuiltDevice(...)` in `App/DeviceRegistry.swift`.
- Wi-Fi: add the device's Bonjour type to `NSBonjourServices` in `Info.plist`. `NSLocalNetworkUsageDescription` and `NSAllowsLocalNetworking` (plain HTTP) are already there.

## 7. The phone loop

The owner connects the iPhone by cable and unlocks it (a charge-only cable shows the phone as unavailable). Find its identifier with `xcrun devicectl list devices | python3 .claude/skills/add-device/mask.py` (the row with an iPhone model and state `connected`; ask the owner if several match) and pass it as `$DEVICE`; never write it into a file.

```bash
xcodebuild -project HomeDeck.xcodeproj -scheme HomeDeck -destination "id=$DEVICE" -configuration Debug \
  -derivedDataPath build/dd -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)"
xcrun devicectl device install app --device "$DEVICE" build/dd/Build/Products/Debug-iphoneos/HomeDeck.app
xcrun devicectl device process launch --device "$DEVICE" local.homedeck.app
```

Tell the owner exactly what to do, one physical step at a time. After each round, pull the log and read it masked:

```bash
xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
  --domain-identifier local.homedeck.app --source Documents/connection-log.jsonl \
  --destination research/<id>/connection-log.jsonl
grep '"device":"<id>"' research/<id>/connection-log.jsonl | python3 .claude/skills/add-device/mask.py
```

The log keeps the newest 500 lines and another device's polling fills it fast, so pull right after each test. After a crash: `xcrun devicectl device info files --device "$DEVICE" --domain-type systemCrashLogs | grep -i homedeck`.

**The log decides, not the memory of the test.** Owners over-report: a 12-second walk "counted distance" (it couldn't move yet), and three speaker features were reported working with no trace in the log. Go through the features one by one and ask "did you try X?" with the log open. A feature is working only when a log line shows the command and the device's confirming answer. An action that leaves no line gets one, and is tried again.

## 8. Finish

- `features.json`: `working` only when verified on device. A feature that couldn't be tested (a broken water tank, no update available) stays `planned`, and the journal says why.
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
