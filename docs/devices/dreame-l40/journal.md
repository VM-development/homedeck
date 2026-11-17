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

## 2026-11-17: Rooms and map

**Tried:**
- Searched the Dreamehome app for the map download path: not there, the vacuum panel is likely a runtime plugin.
- Followed Tasshack's map request (action `6.1`), `getDownloadUrl`, and the decoder; ported them to `DreameKit` (`DreameMap`, tests with a made-up encrypted map built with Python and openssl).
- A build that downloads, decodes and logs the map's structure without room names.

**Device answered:**
- Map request answered with the file name; the link and download worked first time; the file decrypted with the family IV.
- No `seg_inf` in the live frame: the rooms sit in the embedded saved map (`rism`). That gave 8 rooms without names, so the map shows each room's number and a matching colour, and tapping a room selects it.
- The live frame stores room × 4 per pixel (`fsm` = 1), one of Tasshack's three formats; all three are in the decoder.
- Orientation took two tries. The raw image looked wrong, and Tasshack's vertical flip was still upside down for the owner. A left-right mirror of the raw rows matches Dreamehome.
- Cleaning room 5 sent the robot there (`code 0`, seen by the owner).

**Conclusion:** Rooms and the map work (verified on device). Schedules, wetness, zones and go-to-point stay open.
**Next:** Hub review and merge.
Article note: the room list was one level deeper than expected. The live map carries a second, older-format map inside it, and the room data lives there.
