# WalkingPad C2: journal

Entries are only ever appended; dead ends stay. No real names, addresses, keys or tokens.

## 2026-11-13: Open-source pass (before HomeDeck code)

**Tried:** Read eight open-source projects that talk to KingSmith pads (Python, Home Assistant, two macOS Swift apps), the official C2 product page and FAQ. Raw notes and a Python codec stayed in `research/walkingpad-c2/`.
**Device answered:** n/a.
**Conclusion:** Every C2 project uses KingSmith's own protocol on service FE00: commands `F7 … FD` to FE02 without response, status `F8 A2 …` notifications on FE01. Open: whether the C2 also has FTMS, whether a profile-and-beep handshake is needed, the standby code, and how stored walks are read (from open source).
**Next:** Try it on the real pad.

## 2026-11-16: Mac probe blocked

**Tried:** A read-only probe from the Mac with a Python Bluetooth library.
**Device answered:** n/a. macOS killed the process at the first scan: the app running the shell has no Bluetooth permission.
**Conclusion:** The owner chose to probe from the iPhone instead of granting Terminal Bluetooth access.
**Next:** Build the module with every exchange logged and test on the phone.

## 2026-11-16: First connection from HomeDeck

**Tried:** The module scans for FE00, discovers every service, polls status first and sends the profile-and-beep handshake only if the pad stays silent, then asks for settings and the newest stored walk. The owner pressed Start, changed the speed twice and pressed Stop.
**Device answered:**
- Advertised as `KS-BDC2` (not `KS-BLC2` as one source said). Services: FE00 (FE01 read, notify; FE02 write without response), Device Information, and `F000FFC0-0451-4000-B000-000000000000` (Texas Instruments firmware-update service). No FTMS.
- First status, before any handshake: `f8a204000200000000000000000000000000a8fd` (belt state 4, mode 2: standby).
- Settings: `f8a600000000003c1400021f00003c00000053fd` (max 6.0 km/h, start 2.0 km/h, sensitivity 2, all display items).
- Newest stored walk, before and after the walk: all zeros, "0 more stored".
- Start: mode manual (`f8a2 00 00 01 …`), then countdown states 9, 8, 7, then running at 3.0, 2.5, 2.0 km/h; speed 2.5 and 2.0 accepted while running (byte 14 follows the set speed); stop ramps the belt down to state 0.
- Ten minutes idle later the pad went to standby by itself and its time and step counters reset to zero.
**Conclusion:** The handshake isn't needed on this pad (verified on device). Standby is belt state 4 on the C2. Start, speed and stop work. A 14-second walk left no stored record; whether longer walks do is still open.
**Next:** Test the Auto and Standby modes and a two-minute walk, then ask for stored walks again.
Article note: one phone test answered four of the ten open questions the open-source pass left.

## 2026-11-16: Modes and a short walk

**Tried:** The owner switched Auto, Standby and Manual from the Mode card, then started a walk, stopped it and asked for the newest stored walk.
**Device answered:** Each mode command was confirmed by the next status (`f8a2 00 00 00 …` auto, `… 01 …` manual, `f8a2 04 00 02 …` standby). The walk lasted 12 s, so distance stayed 0 (it counts in 10 m steps). Stored walk: zeros again.
**Conclusion:** All three modes work (verified on device). The owner reported that distance counted, but the log shows the walk was too short for it to move. Over three tries the pad never returned a stored walk, so HomeDeck records walks itself.
**Next:** A real two-minute walk, with the phone locked for part of it.

## 2026-11-16: Two-minute walk, phone locked

**Tried:** HomeDeck now saves a walk when the belt stops (counters at stop minus counters at start). The owner walked about two minutes, locked the phone for 30 s in the middle, then stopped.
**Device answered:** Status every 0.75 s with no gap over 2.5 s for the whole walk, including the locked part. Last running frame `f8a20114010000850000060000ad00000300f3fd` (133 s, 60 m, 173 steps on the pad's counters). Saved walk: 124 s, 60 m, 164 steps (the counters had carried 12 s and 10 steps over from the earlier walk). The stored-walk request after it: zeros. The owner saw the walk in the Walks card.
**Conclusion:** Live stats including distance, background polling while locked, and walk history all work (verified on device). All five features are working. Removed the probe-only code: the handshake fallback, the settings request and the stored-walk requests.
**Next:** Hub review, then merge.
Article note: the owner's ticks and the log disagreed twice (distance on a 12-second walk; a walk that was saved but not ticked). The log, not the memory of the test, decides what is marked working.
