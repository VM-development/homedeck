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
