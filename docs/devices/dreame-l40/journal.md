# Dreame L40 Ultra CE: journal

Entries are only ever appended; dead ends stay. No real names, addresses, ids, tokens or keys.

## 2026-11-13: Open-source pass (before HomeDeck code)

**Tried:** Tasshack's integration, Valetudo, python-miio, Tasshack's docs and issues, the MIoT spec registries. Raw notes in `research/dreame-l40/`.
**Device answered:** n/a.
**Conclusion:** No local control for a Dreamehome robot; the Dreamehome cloud (password grant, MD5-signed JSON, one sendCommand endpoint) is the path. Open: whether the app key had rotated, and this exact model's values.
**Next:** Sign in and probe.

## 2026-11-17: App check, sign-in, probe and controls

**Tried:**
- Checked the owner's Dreamehome 2.6.7.0 APK for Tasshack's fixed constants and endpoints (by presence, nothing printed).
- `DreameKit` (signing, sign-in pieces, MIoT helpers, tests with made-up keys).
- A first build that signs in, finds the robot and logs every candidate property.
- Controls built from the values that answered.

**Device answered:**
- The APK still contains the salt, client blob, signing key, host, port and endpoints. Its version code is 102060700, newer than the one in Tasshack's table. The old map download endpoint isn't in it.
- Three sign-ins failed with "user password not match" before the owner's Dreamehome password worked. The account has one robot, `dreame.vacuum.r5021a`. 47 of 55 candidate properties answered, Do Not Disturb included; the map file name and mop-pad life didn't.
- On the phone, every command got `code 0` and moved the robot or set the value: start, pause, dock, stop, all four modes, suction, Do Not Disturb, empty the bin. Wash and dry were accepted, but the owner's water tank is broken, so no mop function could be checked by eye, and the wetness slider wasn't tried.

**Conclusion:**
- Seven of eleven features work: status, start/pause/dock, mode, suction, parts, base station and Do Not Disturb.
- Wetness, rooms, map and schedules stay planned.
- The Dreame constants are in the git-ignored `Config/Secrets.xcconfig`, as with Philips.

**Next:** Hub review and merge; then rooms and map (find where this model's map comes from).
Article note: the last device was the one the plan expected to be hardest, and it was the easiest to drive. Its value table answered the first probe almost completely. The hard part was getting the right password onto a Google-login account.
