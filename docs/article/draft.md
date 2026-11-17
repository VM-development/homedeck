# I built one iPhone app for my home devices

After my [REX5 earbuds app](https://github.com/VM-development/noble-rex5-custom-app), I looked at the rest of my phone: a walking pad, a scale, a fan, an air purifier, a speaker, a robot vacuum and a kettle, each with its own vendor app. So I built HomeDeck, one iPhone app with one module per device. Every module was reverse engineered and tested on the real device, with Claude Code doing most of the reverse engineering and the typing. I did the walking, the weighing and the unplugging. Six devices work. The kettle is paused.

**The plan.** Local control first. A vendor's cloud is allowed only where it is the only way, and ideally only once, to fetch a device's key. Each device gets its own Swift package target for its protocol code, tested on the Mac without the phone. A Market tab lists every device's features and how many of them work, read from one `features.json` per device. Day one was the plan, the app shell and the research for the first six devices. Building and testing the six devices took two more days.

**What each device turned out to speak:**

| Device | Speaks | Key | Working |
|---|---|---|---|
| WalkingPad C2 | KingSmith's own Bluetooth LE protocol | none | 5 of 5 |
| Mi Body Composition Scale S400 | encrypted Bluetooth advertisements only | bind key from Xiaomi's cloud, once | 6 of 6 |
| Xiaomi Smart Standing Fan 2 Pro | miIO over UDP on the home network | token from Xiaomi's cloud, once | 8 of 8 |
| Philips 2000i AC2729 purifier | encrypted CoAP over UDP | one fixed secret shared by every unit | 12 of 12 |
| Bowers & Wilkins Zeppelin Pro | HTTPS JSON API and a WebSocket, plus plain HTTP for settings | none | 7 of 7 |
| Dreame L40 Ultra CE robot | the Dreamehome cloud only | account sign-in | 9 of 11 |
| AENO EK7S kettle | Tuya over Bluetooth | local key from Tuya's cloud | paused |

## Device by device

**WalkingPad C2: the log beat open source.** Eight open-source projects already described the protocol, but they left ten open questions about this model. Three short tests on the real pad closed six of them. The C2 needs no handshake, has no standard fitness (FTMS) service, and uses belt state 4 for standby. It also never returned a stored walk: three tries, three answers of zeros. So HomeDeck records walks itself, counters at stop minus counters at start. It polls every 0.75 s and kept going with the phone locked.

**Mi Scale S400: the scale says its address out loud.** The scale never connects. Each weigh-in is two encrypted advertisement frames. Decrypting them needs a 16-byte key from Xiaomi's cloud and the scale's MAC address, which is part of the nonce. iOS doesn't show apps MAC addresses, and the measurement frames don't carry it. The answer was simple: when someone steps on, the scale's first frame is unencrypted and includes its MAC. For the key I ran the open-source Xiaomi Cloud Tokens Extractor once on my Mac. The same run gave me the fan's token, so the Xiaomi sign-in module in the plan was never built. CryptoKit has no AES-CCM, so HomeDeck builds it on CommonCrypto's AES block function. Weigh-ins go to Apple Health.

**Xiaomi fan: wrong Wi-Fi.** Local control is plain miIO over UDP with the fan's token. At first nothing answered. The fan was on a different network than the phone, and Xiaomi Home worked only because it goes through the cloud. A ping and a broadcast hello from the Mac showed that in a minute. After I moved the fan to the phone's Wi-Fi, every feature worked on the first try. The speed property is writable, although the spec says it is read-only.

**Philips purifier: wrong Wi-Fi again, and a long memory.** The purifier speaks encrypted CoAP. Its key comes from one fixed secret that every unit shares and that open source had already published, so no account is needed. It too was on another network and had to be set up again in Air+. Multicast discovery stayed silent, so HomeDeck sweeps the local network with a plain info request to each address. The encryption matched the Android app byte for byte. The hard part was status updates: after a few test subscriptions from changing ports, the purifier stopped sending status at all until I unplugged it. Re-subscribing from one fixed port with the same token works, so that is what the app does.

**Zeppelin Pro: a polite liar.** No account, no cloud: a local JSON API over HTTPS, a WebSocket for updates, found over Bonjour. The Bonjour record advertises a port that isn't the API. The first phone build crashed because the found address carried an interface suffix (`%en0`) that broke a URL. Then the volume slider jumped. The speaker answers a volume change with "success" and, in the same reply, the old volume, before a separate push brings the new one. It also ignores the mute flag, so mute is volume 0 and a restore. Auto standby lives in a second, plain-HTTP settings API.

**Dreame robot: the cloud one.** I expected it to be the hardest, and it was the easiest to drive. Robots bound to the Dreamehome app switch their local API off, so HomeDeck signs in to Dreame's cloud. It is the only vendor account in the app, and only the session tokens are stored, in the Keychain. The open-source client's fixed constants were still in the current Android app, and 47 of 55 candidate values answered the first probe. The map was harder. The value that should name the map file doesn't answer, and the old download endpoint is gone from the app. A map request action returns the file name, a short-lived link gives the file, and it is AES-encrypted and zlib-compressed. The rooms weren't in the live map at all. They sit in a second, older-format saved map embedded inside it. The rooms have no names, so the map itself became the room picker, with a number and a colour per room. Getting it the right way round took two tries: it is the raw image mirrored left to right.

**AENO kettle: where "no account" stopped.** The AENO app is a white-label Tuya app, and the kettle's screen is downloaded from Tuya's cloud at runtime, so the app names no kettle features. I looked for the kettle on the network: no Tuya broadcast, no open Tuya port. It uses Bluetooth instead: that is my report, not confirmed with a scan. Tuya's Bluetooth protocol needs three values from Tuya's cloud, including the local key. The ways to get them were to re-add the kettle in Tuya's own Smart Life app, to use the AENO app's own cloud keys (vendor secrets, so no), or to dig through a full iPhone backup. I want to keep the AENO app and declined the backup, so the kettle is paused. Two Wi-Fi devices had simply been on another network; the third wasn't on Wi-Fi at all.

## How it was done

- **Research before code.** For each device: open-source projects first, then the vendor's Android app only for the gaps. Apps were decompiled and read, never run, and never committed.
- **One device at a time.** The plan was up to four parallel sessions per wave. I switched to one device at a time, each in its own git branch and worktree, merged only on my yes. Half of the prep list for the waves disappeared, because it existed only to stop parallel sessions from editing the same lines.
- **Every feature on the real device.** The app logs every exchange, tagged by device. After each test the log was copied off the phone and read. The log, not my memory of the test, decides what is marked working. Twice my ticks disagreed with it: a 12-second walk can't show distance, which counts in 10 m steps, and one walk was saved but not ticked. Asking "did you try this?" with the log open caught three speaker features I had reported as working without trying them.
- **Evidence labels.** Every claim in a device's protocol notes carries one label: verified on device, from APK, from open source, or guess. Several claims from the research didn't survive the real device: the pad's Bluetooth name, how the purifier numbers its messages, the fan's "read-only" speed, and a guess that the robot has no Do Not Disturb.
- **A journal per device.** Entries are only appended, and dead ends stay. Lines marked "Article note" became this post.
- **Privacy before the first line of app code.** The repo will be public. A git-ignored file lists my real values: Wi-Fi name, addresses, device names, tokens, keys. A scan searches every file for each of them as text, as hex with or without spaces, and as base64, refuses photo files, and runs before every push. Device keys live in the iPhone Keychain. The two vendor secrets, Philips' shared secret and Dreame's app constants, live in a git-ignored config file, and the tests use made-up ones. When I pasted the extractor's whole output into the chat, the values went into the scan's list and nowhere else.

**Plans that changed.** REX5 was meant to move in as the first device. At the first phone test I kept it as its own app: a working app doesn't need to move. The "Send wishlist" button passed code review but was invisible on the phone, because iOS hides bottom toolbars in a tab-bar app. And the shared Xiaomi sign-in, planned for the first wave, was never needed.

**Not done or not tested yet:**

- All devices: the first Wi-Fi setup still happens in the vendor apps.
- Scale: a weigh-in with the phone locked; which profile the scale gives a second real person; HomeDeck's body composition, which is an estimate from published equations, against Xiaomi's.
- Fan: the timer actually switching it off; oscillation angles other than 30 degrees.
- Purifier: once, six commands in a row were answered "success" and not applied. I couldn't reproduce it.
- Speaker: installing a firmware update, since none was available.
- Robot: anything with water, because my water tank is broken; mop wash and dry were accepted but not checked by eye; schedules aren't decoded; another robot may need its map rotated differently.
- Kettle: everything.

The code will be on GitHub: `<HomeDeck repo link>`. It's an unofficial hobby project, not affiliated with any of the device makers. Thanks to the open-source work it stands on: ph4-walkingpad, xiaomi-ble, python-miio, Xiaomi Cloud Tokens Extractor, aioairctrl, space192/zeppelin, Tasshack's dreame-vacuum and tinytuya.

---

Notes for the owner, delete before publishing:

- The HomeDeck link is a placeholder until the public repo exists.
- No screenshots yet. The rules allow app screens only: no Home Screen, no device or room names.
- Not covered: the Claude skill the spec planned to distill from the checklist and journals.
- Facts worth a second look before publishing: "three speaker features" (from the hub journal), and the timeline, which comes from commit dates.
