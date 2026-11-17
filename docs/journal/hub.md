# HomeDeck shell: journal

Entries are only ever appended. No real names, addresses, keys or tokens: use placeholders such as `<phone>`.

## 2026-11-13: Spec, plan and privacy guard

**Tried:** Designed HomeDeck with the owner (spec in docs/superpowers/specs), wrote the Phase 0 plan, then built the privacy scan first, before any device code exists.
**Device answered:** n/a.
**Conclusion:** The scan finds a private value written as hex inside a commit, so the pre-push hook blocks it (verified locally).
**Next:** HubCore's catalog types.
Article note: the privacy guard came before the first line of app code, because six parallel sessions will push to a public repo.

## 2026-11-13: HubCore catalog types

**Tried:** Added the HubCore package (Packages/) with the catalog types (Link, Feature with features.json loading) and the HomeDevice contract (DeviceStatus, DeviceKind, UnbuiltDevice), test-first.
**Device answered:** n/a.
**Conclusion:** 4 catalog tests pass under `swift test` on a clean build with no warnings (built on macOS 27 only; the iOS 17 target is not built here).
**Next:** The device choices and the store.

## 2026-11-13: Feature choices and device store

**Tried:** Added FeatureChoices (per-device Show and Want ticks in UserDefaults, plus the wishlist text), DeviceStore (added kinds that survive relaunch, one device instance per kind created at launch) and the `.feature(_:)` view modifier with a `deviceID` environment key, test-first.
**Device answered:** n/a.
**Conclusion:** The full HubCore suite passes under `swift test` (10 tests: 4 catalog, 6 new) with no warnings in the build output. Built on macOS 27 only; the iOS 17 target is not built here.
**Next:** The shell: Home and Market screens that use these stores.

## 2026-11-13: Shared connection log

**Tried:** Ported the REX5 connection log into HubCore as ConnectionLog, now tagged by device id (entries carry a device; DeviceLogger keeps the `log.add("...")` call shape per device; filter and Share text can be scoped to one device), test-first.
**Device answered:** n/a.
**Conclusion:** The full HubCore suite passes under `swift test` (13 tests: 4 catalog, 3 store, 3 choices, 3 log) and the log survives relaunch with its 500-entry cap. Built on macOS 27 only; the iOS 17 target is not built here.
**Next:** The shell: Home and Market screens that use these stores and the log.
Article note: one log for six devices works best when every line says which device wrote it, so the Share button can export one device or all of them.

## 2026-11-13: Device kits

**Tried:** Moved the REX5 protocol package into Packages/ as Rex5Kit (App Group now group.local.homedeck.app), added its Catalog, CardSummary and features.json, and added six catalog-only kits (WalkingPadKit, MiScaleKit, PhilipsAirKit, ZeppelinKit, XiaomiFanKit, DreameKit) with starting feature lists, test-first.
**Device answered:** n/a.
**Conclusion:** The full package suite passes under `swift test` (54 tests: 13 HubCore, 39 Rex5Kit including the card summary, 2 catalog) with no warnings in the build output. Built on macOS 27 only; the iOS 17 target is not built here.
**Next:** The shell: Home and Market screens that use these stores, and the REX5 screen with the Task 5 feature ids.
Article note: a catalog kit can ship before any protocol code, because the feature list is the contract the Market reads and the device session fills in later.

## 2026-11-13: Shell app and REX5 migration

**Tried:** Copied the REX5 Xcode project as HomeDeck.xcodeproj (targets, bundle ids and the package reference renamed to HomeDeck, HomeDeckWidgets, local.homedeck.app and Packages/HomeDeckKits), moved the REX5 app code into App/Devices/Rex5/ and added the shell: a Home tab with one glass card per added device, the device registry with REX5 plus six not-yet-built devices, and an app entry with Home, Market and Settings tabs (Market and Settings are one-line placeholders until the next task). Built for the iOS simulator and opened a REX5 widget link.
**Device answered:** n/a.
**Conclusion:** The app builds with no errors and no warnings, opens on the Home tab with the empty-state caption. A rex5:// link sent to the simulator stops at iOS's "Open in HomeDeck?" confirmation; the REX5 Tools screen behind it is not checked yet, because tapping the simulator wasn't available in this run. Changes to the REX5 code, and why: its connection log is now the shared HubCore log tagged "rex5" (one log for every device, shown in hub Settings), so the Tools list lost its Connection log row and the old log screen; the Bluetooth restoration id is now `homedeck.rex5`, so each device owns its own id; HomeView became Rex5Screen, which no longer owns a NavigationStack (the Home tab's stack hosts it) and acts on a pending link held by the new Rex5Device adapter instead of a route binding from the app; its parts are wrapped in feature gates (battery, connections, noise-control, equalizer, troubleshooting) so Market can hide them; the foreground refresh moved from the app's scenePhase handler to a didBecomeActive observer in Rex5Device; the widget bundle, entitlements and App Group were renamed for HomeDeck. The rex5:// URL scheme stays, because the widgets and takeover alerts link to it.
**Next:** Market and hub Settings, replacing the placeholders.
Article note: the old app became a device by moving its root view one level down: the screen keeps its own code, and only the navigation and the link routing moved up into the shell.

## 2026-11-13: Market and Settings

**Tried:** Replaced the two placeholders: Market lists every device in the catalog as a glass tile (link type, how many features work, a check mark once added), and each tile opens a feature list with Show toggles for working features, Want toggles for planned and not-planned ones, Add or Open in the toolbar, and a Send wishlist share button that appears once something is wanted. Settings now holds the shared connection log, filterable by device and shareable, and an About section.
**Device answered:** n/a.
**Conclusion:** The app builds for the iOS simulator with no errors and no warnings and launches. The tap-through checks (tiles and symbols, Add opening the device, hiding a feature, the wishlist button, the log filter) are pending: tapping the simulator wasn't available in this run.
**Next:** Run the tap-through checks, then the first wave-1 device.
Article note: the wishlist is a share sheet, not a backend: the user picks the features they want and sends the text, so there is nothing to host.

## 2026-11-13: Docs and templates

**Tried:** Wrote the docs every device session follows: the protocol and journal templates in docs/templates/, the adding-a-device checklist (branch and worktree rules, what a device session may touch, the nine steps from inventory to review), and a README and MIT LICENSE for the public repo, with the build steps and the privacy hook.
**Device answered:** n/a.
**Conclusion:** Docs only, so no test run applies here. The checklist names the files a device session may change, which keeps parallel device sessions out of each other's code. Evidence labels are not needed for docs.
**Next:** Run the privacy scan and the hook setup on a fresh clone, then start the first wave-1 device session from the checklist.
Article note: the checklist is the part of this project a second device should be able to follow without asking questions, so it was written before any second device.

## 2026-11-13: REX5 stays a separate app

**Tried:** The owner tried the HomeDeck build on the phone and decided the earbuds keep their own standalone app. Removed everything Tasks 5 and 6 brought in for REX5: the device folder App/Devices/Rex5/, the Rex5Kit package target and its tests, the widget extension (HomeDeck's only widgets were REX5's) with its Widgets/ folder and its Xcode target, Shared/ (the battery ring only REX5 used), the registry line, and the app entry's notification delegate and link routing. The `rex5://` URL scheme left Info.plist too: the standalone app owns it, and two apps claiming one scheme make iOS pick either. Bluetooth permission and the `bluetooth-central` background mode stay for the WalkingPad and the scale.
**Device answered:** n/a.
**Conclusion:** The Market now lists six devices. The app builds for the iOS simulator and opens on the empty Home tab; `swift test` passes (13 HubCore, 1 catalog). HomeDeck has no working device yet; the first comes from wave 1.
**Next:** The first wave-1 device session.
Article note: at the first real test the hub decided that a working app doesn't need to move: the shell earns its place with devices that have no good app yet, not by absorbing one that already works.

## 2026-11-13: HomeDeck on the iPhone

**Tried:** Installed the REX5-free build on `<phone>` over a USB cable (the first attempt failed: the cable carried no data, so the phone showed as unavailable). The owner checked the app by hand; the simulator walk-through covered the rest.
**Device answered:** Market lists six devices, each at "0 of N features working". Add opens the device's "isn't built yet" screen on Home; the Home card reads "Not set up"; long-press, Remove from Home takes it off. Settings, Connection log opens and its device filter lists the six devices. The "Send wishlist" button never appeared: it sat in a bottom toolbar, and iOS hides bottom toolbars in a tab-bar app. The Want choice itself was saved.
**Conclusion:** Moved "Send wishlist" into the feature list as its own row; it shows as soon as one feature is wanted (verified in the simulator). Phase 0 works on the phone, with no device module yet.
**Next:** The owner's yes for creating `main`, the public repo and the first push; then the wave-1 prep step before device sessions start.
Article note: the first real test changed the plan twice in ten minutes: the earbuds stayed in their own app, and a button the code review called fine turned out to be invisible.

## 2026-11-15: AENO EK7S kettle joins the catalog

**Tried:** The owner added a seventh device, the AENO EK7S smart kettle, and provided the vendor's Android app (in `research/aeno-ek7s/`, git-ignored). Read its package with Android build-tools only; nothing was installed or run.
**Device answered:** n/a. The app is a Tuya (Thing Clips) white-label app: Tuya SDK classes and native libraries throughout, Wi-Fi and Bluetooth pairing permissions. Its kettle screen is a panel the Tuya cloud serves at runtime, so the APK names no kettle features.
**Conclusion:** Added `AenoKit` with a starting feature list (boil, target and current temperature, keep warm, presets, status), all planned and expected rather than read from the app (guess). Market now lists seven devices; the kettle goes to wave 2.
**Next:** The device session checks Tuya's local protocol against the kettle and works out how to get its local key.
Article note: a white-label app is mostly someone else's SDK; the interesting part, the device panel, isn't in the APK at all.

## 2026-11-15: White marble app icon

**Tried:** The owner asked for a white marble app icon in place of the black marble one inherited from the REX5 app. Generated it locally from fractal noise (grey veins bent by low-frequency noise on near-white stone, fixed seed), so it is a computed texture, not a photo.
**Device answered:** n/a. The simulator kept showing the old icon after a plain reinstall; deleting the app and installing again refreshed it.
**Conclusion:** `AppIcon.png` is now white marble (1024 px, no transparency, one universal size as before). Builds; checked on the simulator home screen.
**Next:** The owner sees it on the phone with the next install.
Article note: the first texture had veins that closed into loops and looked like a contour map; lowering the noise frequency made them run one way, like real stone.

## 2026-11-16: Setup before the first device

**Tried:** The owner chose to build devices one at a time and check every feature on the real device before moving on, starting with the WalkingPad C2. Went through the prep list from the Phase 0 review.
**Device answered:** n/a.
**Conclusion:** `.feature(_:)` now asserts in debug builds when a screen forgets the device id, instead of silently showing every feature. The checklist no longer mentions the removed `Widgets/` folder. Three prep items wait for the device that needs them, since one-at-a-time work removes the parallel-edit clashes they guarded against: the local-network prompt text comes with the first Wi-Fi device, Xiaomi sign-in with the first Xiaomi device, and each kit still adds its own test-target line.
**Next:** WalkingPad C2 on branch `device/walkingpad-c2`.
Article note: building one device at a time made half of the "before wave 1" list unnecessary; most of it existed to stop parallel sessions from editing the same lines.

## 2026-11-16: WalkingPad C2 works

**Tried:** Built the first device module on branch `device/walkingpad-c2`, tested on the owner's iPhone against the real pad in three rounds, reading the app's connection log off the phone after each.
**Device answered:** See `docs/devices/walkingpad-c2/journal.md`: the C2 needs no handshake, has no FTMS, uses state 4 for standby, and never returns a stored walk.
**Conclusion:** All five WalkingPad features are working: start and stop, speed, the three modes, live speed, time, distance and steps, and walk history, which HomeDeck records itself. Polling kept running with the phone locked. Market now shows "5 of 5 features working" for it.
**Next:** The owner's review and the merge; then the next device.
Article note: the research pass left ten open questions; three short tests on the real device closed six of them, and the answer to one (stored walks) changed the design.

## 2026-11-16: Mi Body Composition Scale S400 works

**Tried:** Built the scale module on branch `device/mi-scale-s400` in two rounds (decrypting the scale's broadcasts, then people, body composition and Apple Health), tested on the owner's iPhone and scale, reading the app's log off the phone after each weigh-in.
**Device answered:** See `docs/devices/mi-scale-s400/journal.md`: the global S400 (product `0x3BD5`), the MAC broadcast in an unencrypted idle frame, weigh-ins in two encrypted frames.
**Conclusion:** All six scale features work. Shared changes this device needed: `HubCore/Keychain.swift` (device secrets; the spec had planned it inside XiaomiCloudKit), the HealthKit entitlement, and the Health usage texts in `Info.plist`. The bind key comes from the owner running Xiaomi Cloud Tokens Extractor, so HomeDeck has no Xiaomi sign-in yet; the fan's token came from the same run.
**Next:** The owner's review and merge; then the next device.
Article note: the owner pasted the extractor's whole output (keys, tokens, MACs) into the chat. Nothing was written to the repo; the values went into the git-ignored privacy-scan patterns so a commit containing them is refused.

## 2026-11-17: Scale profiles

**Tried:** The owner asked for a simple way to add several people to the scale. Added "Add person", moving a weigh-in between people, and removing a person, on branch `device/mi-scale-s400`; tested on the owner's iPhone.
**Device answered:** All three work. The owner flagged the Remove confirmation appearing in a corner; it is now a centred alert with Cancel.
**Conclusion:** No shared files changed. Open: the scale's number for a second real person is still unverified.
**Next:** The owner's review and merge.
Article note: the one usability report from the test was about where a button appeared, not about what it did.

## 2026-11-17: Xiaomi Fan 2 Pro

**Tried:** Built the fan module on branch `device/xiaomi-fan-2-pro` from the 2026-11-13 research, with the token and IP from the extractor the owner already ran for the scale. No Xiaomi sign-in in the app.
**Device answered:** See `docs/devices/xiaomi-fan-2-pro/journal.md`: the fan had to move to the phone's Wi-Fi first; after that every feature worked on the first try.
**Conclusion:** All eight fan features work. Shared changes: `NSLocalNetworkUsageDescription` in `Info.plist` (unicast UDP needs no Bonjour types or multicast entitlement), and `BigButton` moved from the WalkingPad screen to `App/UI/Glass.swift` for its second user. A fresh worktree needs the git-ignored `Config/Team.xcconfig` copied in, or phone signing fails.
**Next:** The owner's review and merge; then the next device.
Article note: with the token extractor, the cloud sign-in planned as a shared wave-1 module wasn't needed for either Xiaomi device.

## 2026-11-17: Philips 2000i AC2729

**Tried:** Built the purifier module on branch `device/philips-ac2729` from the 2026-11-13 research, probing the owner's unit from the Mac first with the research's stdlib script.
**Device answered:** See `docs/devices/philips-ac2729/journal.md`: like the fan, it was on another Wi-Fi at first; then its status subscriptions filled up during probing, which a restart cleared.
**Conclusion:** All twelve purifier features work. Shared changes: `Config/Secrets.xcconfig` (git-ignored, with a `.example`) included from `Signing.xcconfig` and passed through `Info.plist` as `PhilipsLANSecret`, by the owner's choice to keep the vendor's fixed LAN secret out of the public repo; the secret is in the privacy-scan patterns. README and `adding-a-device.md` mention the new file.
**Next:** The owner's review and merge; then the next device.
Article note: on the second Wi-Fi device, "is it on the same network as the phone?" was again the first question to ask.

## 2026-11-17: AENO kettle paused

**Tried:** Looked for the kettle on the LAN (Tuya broadcasts and TCP 6668) and checked what the open-source Tuya Bluetooth code needs.
**Device answered:** See `docs/devices/aeno-ek7s/journal.md`: not on the LAN; the owner reports it uses Bluetooth; Tuya Bluetooth needs the local key, UUID and device id from Tuya's cloud.
**Conclusion:** Paused by the owner's choice: they want to stay with the AENO app, and the remaining route (a full iPhone backup to look for the key in the AENO app's files) was declined. The catalog link changed from Wi-Fi to Bluetooth; README says "Paused".
**Next:** The next device.
Article note: the one device that needed a vendor cloud for its key, and no extractor exists for this white-label app, is where "no account" stopped.

## 2026-11-17: Zeppelin Pro Edition

**Tried:** Built the speaker module on branch `device/zeppelin-pro` from the 2026-11-13 research, probing the owner's speaker from the Mac first.
**Device answered:** See `docs/devices/zeppelin-pro/journal.md`: on the right network from the start; one crash (an `%en0` address suffix) and one volume bug (a stale echo in the reply), both fixed.
**Conclusion:** All seven speaker features work; firmware install untested (no update available). Shared changes: `NSBonjourServices` (`_eva-mesh._tcp`) and `NSAppTransportSecurity`/`NSAllowsLocalNetworking` in `Info.plist`; the round glass button moved from the WalkingPad screen to `App/UI/Glass.swift` as `RoundButton`.
**Next:** The owner's review and merge; the Dreame L40 is the last device.
Article note: asking "did you try X?" with the log open caught three untested features that had been reported as working.

## 2026-11-17: Dreame L40 Ultra CE

**Tried:** Built the robot module on branch `device/dreame-l40` through the Dreamehome cloud, after checking the owner's Dreamehome 2.6.7.0 APK still carries the open-source clients' constants.
**Device answered:** See `docs/devices/dreame-l40/journal.md`: model `r5021a`; seven features verified on the robot; mop functions untestable (broken water tank).
**Conclusion:** First cloud device. Shared changes: three Dreame constants added to the git-ignored `Config/Secrets.xcconfig` (and its `.example`), passed through `Info.plist` as `DreameSalt`, `DreameBasic`, `DreameKey`; they are in the privacy-scan patterns. The Dreamehome session (tokens only, no password) is stored in the Keychain.
**Next:** The owner's review and merge; rooms and map as a follow-up.
Article note: six devices in a day, and four of them needed one thing before any protocol work: being on the right network or in the right app.

## 2026-11-17: Dreame rooms and map

**Tried:** Rooms and map for the Dreame on branch `device/dreame-l40`, from Tasshack's map request and decoder.
**Device answered:** See `docs/devices/dreame-l40/journal.md`: the map comes from action `6.1` and a short-lived download link; the rooms are in a saved map embedded in the live one; room 5 cleaned on request.
**Conclusion:** Nine of eleven Dreame features work; schedules and wetness stay planned. Shared change: one more git-ignored constant, `DREAME_MAP_IV_HEX` (with its `.example` line and `Info.plist` key `DreameMapIV`), in the privacy-scan patterns.
**Next:** The owner's review and merge.
Article note: the room picker that worked was the map itself. The rooms had no names, so numbers on the map did what a list couldn't.

## 2026-11-17: Article draft

**Tried:** Drafted the article the spec plans, from the hub and device journals (their "Article note" lines), the protocol docs and their evidence labels, the README and the `phase-0-shell` history, in the style of the REX5 post: first person, bold run-in headings, a short table, a list of what isn't tested.
**Device answered:** n/a.
**Conclusion:** `docs/article/draft.md` is written for the owner to edit. Checking it against the sources removed four claims the sources don't support: "replaced six apps" (the six working devices use five vendor apps, and they are still needed for Wi-Fi setup), the kettle's Bluetooth as a fact (it is the owner's report, no scan), research "for every device" on day one (the kettle came two days later), and the research's wrong claims all being guesses (some came from open source or the spec). The HomeDeck repo link is a placeholder until the public repo exists.
**Next:** The owner edits and publishes.
Article note: an article drafted from evidence labels inherits their honesty only if every sentence is checked back against them; the first draft overclaimed four times.

## 2026-11-17: Add-device skill

**Tried:** Distilled `docs/adding-a-device.md`, this journal and the seven device journals and protocol docs into a Claude skill, `.claude/skills/add-device/SKILL.md`, with a small `mask.py` beside it that masks private values in anything a session prints, using the privacy scan's own pattern matching (the patterns file is never printed).
**Device answered:** n/a.
**Conclusion:** The skill covers research with evidence labels, probing from the Mac first, the kit, tests, device class and screen, the phone loop (`xcodebuild` to the phone, `devicectl` install, launch and log pull), finishing, the branch rules, and a table of what the devices did (wrong Wi-Fi, replies that echo stale values, full subscription slots, `%en0` addresses). It updates the checklist in two places: a fresh worktree copies the git-ignored config files in, and merges go into `phase-0-shell` while `main` doesn't exist. `mask.py --self-test` passes; a fresh agent applied the skill to a made-up device as a check.
**Next:** Wave 2 uses the skill and refines it.
Article note: across seven devices the most repeated lesson wasn't about protocols: first check the device is where the phone can reach it, and let the log, not the memory of the test, decide what works.
