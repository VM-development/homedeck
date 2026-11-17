# Philips 2000i AC2729: journal

Entries are only ever appended; dead ends stay. No real names, addresses, ids or keys.

## 2026-11-13: APK and open-source pass (before HomeDeck code)

**Tried:** Read Air+ 3.21.0 (the MXCHIP CoAP stack, the key-dialect classes, discovery) and four open-source projects; wrote a stdlib probe with an offline self-test. Raw notes in `research/philips-ac2729/`.
**Device answered:** n/a.
**Conclusion:** Local encrypted CoAP with a fixed, already-public secret; no account needed. Open: which variant this unit uses, and whether empty user ids are accepted.
**Next:** Probe the owner's unit.

## 2026-11-17: Probe, build and test

**Tried:** Multicast discovery from the Mac, then a unicast `/sys/dev/info` sweep of the /24, then the probe's status read, then `PhilipsAirKit` (CoAP codec, cipher, state) and a screen with "Find my purifier".
**Device answered:**
- Nothing on the network at first: the purifier was on another Wi-Fi. The owner set it up again in Air+ on the phone's network; the sweep then found it (option "1", firmware 0.3.4). Multicast stayed silent.
- The first status read answered after about 4 s, and then status stopped answering although sync still did, even after 2 quiet minutes. The owner closed Air+ and unplugged the purifier; after that it pushed again (Max-Age 60). Five re-subscriptions from one fixed port and token, without cancelling, kept working, so the app uses that.
- On the phone: every control worked, each answered `success` and confirmed by the next push. Once, six commands in a row (unlock, light, timer) got `success` and weren't applied; power off three seconds later worked. Not reproduced from a Mac, also not after a 2-minute idle gap. The app now syncs before every command, as Air+ seems to; the retest (lock twice, light, tank) was clean.
- Tank out: `err` 32768, `wl` unchanged at 100.
**Conclusion:** All twelve features work (verified on device). The secret lives in the git-ignored `Config/Secrets.xcconfig` (the owner's choice); the tests use a made-up one.
**Next:** Hub review and merge. Open: the one unexplained burst of ignored commands.
Article note: the hardest part wasn't the encryption, which matched the APK byte for byte. It was the purifier going quiet after a few test subscriptions it never forgot.
