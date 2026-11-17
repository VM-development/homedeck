# Xiaomi Smart Standing Fan 2 Pro: journal

Entries are only ever appended; dead ends stay. No real names, addresses, keys or tokens.

## 2026-11-13: APK and open-source pass (before HomeDeck code)

**Tried:** Read Xiaomi Home for Android 11.7.623 (the miIO stack in Java and `libmiio.so`, the device config) and three open-source projects; wrote a Python packet builder with a made-up token. Raw notes in `research/xiaomi/`.
**Device answered:** n/a.
**Conclusion:** Local control is plain miIO over UDP with the fan's token; no vendor secret needed. Open: is speed 2.6 writable, and is the owner's fan really p33?
**Next:** Build it and probe on the owner's fan.

## 2026-11-17: Local control on the iPhone

**Tried:** `XiaomiFanKit` (miIO packets, the p33 property table, tests with the made-up-token vectors) and a fan screen polling every 3 s. Token and IP come from the extractor output the owner already had; the token goes to the Keychain. Added the Local Network usage text to `Info.plist`.
**Device answered:** Nothing at first: the IP the cloud listed was on another network than the phone's, and neither a ping nor a broadcast hello from the Mac found a miIO device on the phone's network. The fan worked in Xiaomi Home only because that goes through the cloud. The owner moved the fan to the phone's Wi-Fi in Xiaomi Home, entered the new token and IP, and the first read returned all eleven properties. Every write answered code 0: power, both modes, all gears, speed 1-100, oscillation, angle 30, timer 30 min, child lock, light, beep. The owner saw each change on the fan.
**Conclusion:** All eight features work (verified on device). Speed 2.6 is writable despite the spec. Two fixes during the test: a reply that arrived after the token was removed marked the fan "Offline" instead of "Not set up", and the slider snapped back on release because its binding read a copy of the state taken when the screen last drew.
**Next:** Hub review and merge. Open: the auto-off after the timer runs out, and angles other than 30.
Article note: the first failure wasn't the protocol. The fan was simply on a different Wi-Fi than the phone, which a Mac-side ping and broadcast hello showed in a minute.
