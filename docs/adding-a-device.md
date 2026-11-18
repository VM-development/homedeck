# Adding a device

Each device is built by its own session, in its own git worktree, on branch `device/<id>` (for example `device/walkingpad-c2`). The session commits on that branch as it goes. Merging into `phase-0-shell` (the integration branch until `main` exists) and every push wait for the owner's explicit yes, after the hub session's review. The `add-device` skill (`.claude/skills/add-device/`) adds the lessons from the first devices and `hd.py`, which creates a device's files (`hd.py new`), runs the app on the iPhone (`hd.py phone`) and pulls its log (`hd.py log`).

Worktree setup: the git-ignored `Config/Team.xcconfig` and `Config/Secrets.xcconfig` live only in the main checkout. `hd.py phone` copies them in; by hand: `cp <main checkout>/Config/Team.xcconfig <main checkout>/Config/Secrets.xcconfig Config/`. A new vendor constant goes into both copies, so it survives the merge. The privacy scan reads `Config/private-patterns.txt` from the main checkout too. Never create or edit that file in a worktree; if the scan says it is missing, ask the owner.

A device session changes only:
- `Packages/Sources/<Name>Kit/` (with its `device.json`) and `Packages/Tests/<Name>KitTests/` (plus its kit and test-target lines in `Packages/Package.swift`);
- `App/Devices/<Name>/`;
- `docs/devices/<id>/`;
- its import and one line in `App/DeviceRegistry.swift`;
- for a Wi-Fi device, `App/Info.plist`: `NSLocalNetworkUsageDescription` (added once, by the first Wi-Fi device) and its Bonjour service type in `NSBonjourServices`.

Anything else (the app entry and link routing, entitlements, HubCore, other devices' files): stop and ask the hub session.

Raw material (APKs, decompiled code, captures, raw logs) goes in `research/<id>/`, which git ignores. Never copy it into the repo.

## Steps

1. **Start and inventory.** `hd.py new` creates the device's files, including `Packages/Sources/<Name>Kit/device.json` (id, name, SF Symbol, link, category, features) and `docs/devices/<id>/journal.md`. List every feature of the vendor app in its `features` (`working` or `planned`).
2. **Existing work.** Search for open-source implementations of the device's protocol (Home Assistant integrations, Python libraries, GitHub write-ups). Record each under Sources with its licence. Don't copy code from projects whose licence doesn't allow it; describe the protocol in your own words.
3. **APK, for the gaps only.** The owner gives the vendor's Android app (`.apk` or `.xapk`); `hd.py new --apk` unpacks it into `research/<id>/` and dumps the code with Android build-tools' `dexdump -d`. Read it; never install or run it.
4. **Probe.** Make the device's module log every raw exchange to the shared log (`ConnectionLog.shared.tagged("<id>")`) and try the commands on the real device. Ask the owner for each physical step. Append a journal entry for each probe session as you go, not only at the end. Redact keys and tokens in log lines: the log can be shared.
5. **Protocol doc.** Write `docs/devices/<id>/protocol.md` from `docs/templates/protocol.md`, with an evidence label on every command.
6. **Kit.** Protocol code in `<Name>Kit` (no SwiftUI), tests in `<Name>KitTests` built from real captures with names, addresses and keys replaced. Run `cd Packages && swift test --filter <Name>KitTests`.
7. **App.** The device class (`HomeDevice`) and screens in `App/Devices/<Name>/`, using `App/UI/Glass.swift` and `App/UI/DeviceUI.swift` (header, menu rows, tiles) and `.feature("<feature id>")` on each part of the screen. `hd.py new` registered a starter class and screen. The device class is created at every launch, including background Bluetooth relaunches, so its `init` must stay cheap and must not trigger permission prompts. A Bluetooth device owns its own `CBCentralManager` with restoration identifier `homedeck.<id>`. The shell never calls `connect()`/`disconnect()` yet; the device connects on its own schedule.
8. **On the phone.** `hd.py phone` builds and installs the branch on the owner's iPhone; test each feature with the owner, read `hd.py log <id>`, and update `device.json`.
9. **Finish.** Run `python3 scripts/privacy-scan.py`, look at every image you add (app screens only, never the Home Screen or device names), add the journal entry, and report to the hub session for review.

Secrets (tokens, bind keys) go in the iPhone Keychain only, never in files, logs or test fixtures.
