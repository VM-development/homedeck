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
