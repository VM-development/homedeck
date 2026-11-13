# HomeDeck shell: journal

Entries are only ever appended. No real names, addresses, keys or tokens: use placeholders such as `<phone>`.

## 2026-11-13: Spec, plan and privacy guard

**Tried:** Designed HomeDeck with the owner (spec in docs/superpowers/specs), wrote the Phase 0 plan, then built the privacy scan first, before any device code exists.
**Device answered:** n/a.
**Conclusion:** The scan finds a private value written as hex inside a commit, so the pre-push hook blocks it (verified locally).
**Next:** HubCore's catalog types.
Article note: the privacy guard came before the first line of app code, because six parallel sessions will push to a public repo.
