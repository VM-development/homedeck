# Mi Body Composition Scale S400: journal

Entries are only ever appended; dead ends stay. No real names, addresses, keys or tokens.

## 2026-11-13: APK and open-source pass (before HomeDeck code)

**Tried:** Read Xiaomi Home for Android 11.7.623 (frame parser, beacon-key source, standard auth) and eight open-source S400 projects. Wrote a Python decoder that decrypts the published S400 frames. Raw notes stayed in `research/xiaomi/`.
**Device answered:** n/a.
**Conclusion:** The S400 broadcasts each weigh-in as an encrypted MiBeacon v5 frame (service data FE95, object 0x6E16: profile, weight, heart rate, impedance, timestamp). Decrypting needs the 16-byte bind key from the Xiaomi cloud and the scale's MAC, which measurement frames don't carry; CryptoKit has no AES-CCM, so it is built on CommonCrypto (from APK, from open source).
**Next:** Listen on the iPhone.

## 2026-11-16: First weigh-in heard

**Tried:** HomeDeck's scale module scans every advertisement in the foreground and logs each new S400 frame (MAC bytes blanked). The owner closed Xiaomi Home, opened the scale screen and weighed in barefoot.
**Device answered:**
- `1059d53b2axxxxxxxxxxxx`: frame control 0x5910 (MAC included, no object, not encrypted, standard auth, v5), product 0x3BD5 (`yunmai.scales.ms104`, the global S400).
- `4859d53b2b…` and `4859d53b2c…`: two encrypted measurement frames, 24 bytes each, about a second apart.
**Conclusion:** iOS delivers the FE95 service data with a foreground scan (verified on device). The scale's idle frame carries its MAC, so HomeDeck can learn it instead of asking the owner (verified on device). The Swift AES-CCM decrypts all five published test frames.
**Next:** The owner gets the bind key from the Xiaomi cloud; HomeDeck decrypts the frames it heard before the key was entered.

## 2026-11-16: Bind key, weight and heart rate

**Tried:** The owner ran Xiaomi Cloud Tokens Extractor on the Mac (the first attempt failed: a Terminal in a deleted folder and an Intel-only `curl` first on the PATH; a one-line `uv run` of the single script worked). Checked the key offline against the two captured frames, then the owner pasted it into HomeDeck and weighed in for about 20 seconds.
**Device answered:** Both earlier frames decrypted offline (profile 1, weight and 50 kHz impedance; then 250 kHz impedance; no heart rate). On the phone, the new weigh-in decrypted with weight, heart rate and both impedances. The scale's timestamp matched the phone's clock.
**Conclusion:** Decryption on the iPhone, the learned MAC, weight and heart rate work (verified on device). Two bugs: the setup screen didn't switch after Save (the key wasn't observed), and frames heard before an app reinstall were lost, as expected. Frames also arrived with the `FE95` scan filter, so the foreground "scan everything" mode was dropped.
**Next:** People, body composition and Apple Health.

## 2026-11-16: People, body composition and Apple Health

**Tried:** Added a person per scale slot (name, height, birth year, sex) kept on the phone, body composition from published equations, a trend chart, and saving to Apple Health 20 s after a weigh-in's last frame (HealthKit entitlement and usage text added). The owner filled in Person 1, allowed Health, and weighed in.
**Device answered:** Weigh-in with weight, heart rate and both impedances; "saved the weigh-in to Apple Health" 21 s later. The owner saw the body composition card, the trend chart and the new weight in the Health app.
**Conclusion:** All six features work (verified on device). Body composition is an estimate; it hasn't been compared with Xiaomi Home's figures.
**Next:** Hub review and merge. Open: a locked-phone weigh-in (background capture) and a comparison with Xiaomi Home's body composition.
Article note: the key question from the research, "how does an iPhone get the MAC it can't see?", had the simplest answer: the scale says it out loud in its first, unencrypted frame.

## 2026-11-17: More people on one scale

**Tried:** "Add person" in the People card (the next free number, so the second person added matches the scale's person 2), tapping a weigh-in to move it to another person or to Guest, a Guest chip when there are guest weigh-ins, and Remove in the person editor (their weigh-ins move to Guest). The owner first saw the Remove confirmation in the top-left corner (a confirmation dialog anchored to the whole form), so it became a centred alert with Cancel and Remove.
**Device answered:** On the owner's iPhone: a person added and named, a weigh-in moved to them and shown under their chip, the person removed after the alert. The log kept "removed profile 2"; the move lines had been trimmed by then, because the WalkingPad's polling fills the 500-line log.
**Conclusion:** Profiles work (owner verified on screen). Not checked: which number the scale gives a second real person. If it marks everyone as person 1 or as Guest, weigh-ins have to be moved by hand until HomeDeck matches people by weight.
**Next:** Weigh a second person and read the profile number from the log.
