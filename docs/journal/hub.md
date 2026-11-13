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
