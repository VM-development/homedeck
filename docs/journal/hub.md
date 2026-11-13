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
