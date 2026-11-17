# Xiaomi Smart Standing Fan 2 Pro: protocol

Every claim carries one evidence label: **verified on device**, **from APK**, **from open source**, or **guess**.
No real names, addresses, keys or tokens: use placeholders such as `<ip>` or `<token>`.

## Device

- Model `dmaker.fan.p33` (**verified on device**: the cloud device list from Xiaomi Cloud Tokens Extractor). Wi-Fi only, 2.4 GHz (**from APK**: `pid 0` in the device config; the band is a **guess**).
- Look-alikes with other property layouts: `dmaker.fan.p18`, `p30`, `p42` (Fan 2) (**from APK**). HomeDeck only knows p33.

## Transport

- UDP to `<ip>:54321`, one socket per request, 2-second wait (**from APK**, **verified on device**). No discovery: the owner enters the IP from the extractor output. iOS asks for Local Network access on the first packet (**verified on device**).
- The phone has to be on the fan's own network. Xiaomi Home also works from elsewhere because it goes through Xiaomi's cloud (**verified on device**: the owner's fan was on another network at first; nothing answered until it moved to the phone's Wi-Fi).

## Keys and packets

- Token: 16 bytes, shown as 32 hex characters by the extractor. AES key = MD5(token), IV = MD5(key ‖ token), AES-128-CBC with PKCS#7 (**from APK** `libmiio.so`, **from open source**, **verified on device**).
- Header, 32 bytes, big-endian: magic `21 31`, total length, device id (8 bytes), stamp (4 bytes), MD5 over the packet with the token in the checksum field (**from APK**, **verified on device**).
- Hello: `21 31 00 20` + 28 × `FF`; the reply carries the device id and stamp. HomeDeck sends a hello before every request and uses stamp + 1 (**verified on device**). The Xiaomi app instead reuses a stamp for up to 6 s (**from APK**).
- Worked example with a made-up token: `Packages/Tests/XiaomiFanKitTests/MiIOTests.swift` (vectors from `research/xiaomi/work-cloud-fan/demo_protocols.py`).

## Properties (MIoT `get_properties` / `set_properties`)

| siid.piid | Name | Values | Evidence |
|---|---|---|---|
| 2.1 | power | bool | verified on device |
| 2.2 | gear | 1-4 | verified on device |
| 2.3 | mode | 0 direct, 1 natural breeze | verified on device |
| 2.4 | oscillate | bool | verified on device |
| 2.5 | oscillation angle | 30, 60, 90, 120, 140 | 30 verified on device; the others from open source |
| 2.6 | speed | 1-100 | verified on device: writable, although the spec says read-only |
| 3.1 | off timer | minutes left, 0 = off | verified on device (set and counting; the auto-off itself was not waited for) |
| 4.1 | indicator light | bool | verified on device |
| 5.1 | beep | bool | verified on device |
| 6.2 | motor fault | 0 = none | read on device (always 0) |
| 7.1 | child lock | bool | verified on device |

- Gear and speed move together (**verified on device**): gear 1 = 1 %, gear 3 = 70 %, gear 4 = 100 %; writing a speed sets the gear (5 % reads as gear 1, 46-47 % as gear 2, 76 % as gear 3).
- Every write answered `code 0`. The fan never pushes changes over the LAN, so HomeDeck reads all eleven properties every 3 s while the screen is open (**from APK**: request/response only; the polling interval is a **guess** that felt right on device).

## Not used

- Actions (`toggle`, `toggle-mode`, `loop-gear`) and head nudge 6.1: the properties cover every feature (**from open source**, not tried).
- Cloud control (`/miotspec/prop/get|set`): needs Xiaomi sign-in inside HomeDeck; see `research/xiaomi/cloud-and-fan-notes.md`.

## Sources

python-miio (GPL-3.0, read only), hass-xiaomi-miot (Apache-2.0), Xiaomi-cloud-tokens-extractor (MIT), the MIoT spec mirror for `dmaker.fan.p33`, and Xiaomi Home for Android 11.7.623. No third-party code was copied. Details in `research/xiaomi/cloud-and-fan-notes.md` (git-ignored).
