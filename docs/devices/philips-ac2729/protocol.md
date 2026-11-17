# Philips 2000i AC2729: protocol

Every claim carries one evidence label: **verified on device**, **from APK**, **from open source**, or **guess**.
No real names, addresses, ids or keys: use placeholders such as `<ip>` or `<secret>`.

## Device

- AC2729/13, firmware 0.3.4, Wi-Fi module `AWS_Philips_AIR@91.1`, family code name "MicroMario" (**verified on device**).
- Its `/sys/dev/info` reply has `option` "1": the encrypted CoAP variant, not plain CoAP or the RSA/AES-GCM one (**verified on device**). Air+ 3.21.0 also has a legacy HTTP (DiComm) path for old firmware (**from APK**); this unit has no HTTP endpoint (**verified on device**).

## Transport

- CoAP over UDP to `<ip>:5683`, non-confirmable requests (**from open source**, **verified on device**). Paths: `/sys/dev/info` (plain), `/sys/dev/sync`, `/sys/dev/status` (Observe), `/sys/dev/control` (**from APK**, **verified on device**).
- Finding it: Air+ multicasts to `224.0.1.187`; that went unanswered from a Mac, and iOS needs Apple's multicast entitlement for it anyway. A unicast `GET /sys/dev/info` to each address of the /24 found it (**verified on device**); HomeDeck's "Find my purifier" does the same.
- It has to be on the phone's own Wi-Fi network. The owner's unit was on another network at first and had to be set up again in Air+ (**verified on device**).

## Keys and sessions

- Sync: POST `/sys/dev/sync` with 8 random uppercase hex characters; the reply is the device's 8-hex counter. The next command uses counter + 1 (wrapping from 2,000,000,000 to 1) (**from APK**, **verified on device**).
- Per message: MD5 of `<secret>` + counter hex, as 32 uppercase hex characters; the first 16 characters (as ASCII bytes) are the AES-128 key, the last 16 the IV; AES-CBC with PKCS#7; the wire text is `counter ‖ ciphertext hex ‖ SHA-256(counter ‖ ciphertext hex) hex` (**from APK**, **from open source**, **verified on device**).
- `<secret>` is one fixed string for every unit, already published in aioairctrl (MIT). By the owner's choice HomeDeck keeps it in the git-ignored `Config/Secrets.xcconfig`; the tests use a made-up one.
- The device numbers its own pushes with an unrelated counter, not from the client's sync value (**verified on device**; the research had guessed otherwise).
- Empty `DeviceId` and `EnduserId` are accepted: no account is needed (**verified on device**).
- HomeDeck syncs before every command. Air+ seems to do the same (it throttles syncs to one per 600 ms, **from APK**). One sync followed by several commands, also after 2 idle minutes, worked from a Mac (**verified on device**).

## Status pushes

- GET `/sys/dev/status` with Observe 0. The first push takes 2-10 s; after that the purifier pushes its whole state (about 40 keys) on every change and every few seconds while readings move, as NON messages with Max-Age 60 (**verified on device**).
- **Subscriptions fill up.** After several subscriptions from different ports without cancelling, the purifier still answered sync but sent no status at all, even after 2 quiet minutes; unplugging it cleared that (**verified on device**). Re-subscribing from the same port with the same token, five times without cancelling, kept working (**verified on device**), so HomeDeck uses a fixed local port (56830) and token, and cancels with Observe 1 when the purifier is removed.

## Commands (`{"state":{"desired":{"CommandType":"app","DeviceId":"","EnduserId":"", …}}}`)

The reply is plain `{"status":"success"}`; the change shows in the next push. All **verified on device**:

| What | Pairs |
|---|---|
| Power | `pwr` "1" / "0" |
| Mode | `mode` "P" auto, "A" allergen, "S" sleep; manual is `mode` "M" with `om` "1", "2", "3" or "t" (turbo) |
| Humidifier | `func` "P" (purify only) or "PH" with `rhset` 40 / 50 / 60 / 70 (int; 70 is Max) |
| Timer | `dt` 0-12 (int hours); `dtrs` reports minutes left (1 h read back as 60) |
| Display light | `aqil` 0 / 25 / 50 / 75 / 100 (int) with `uil` "0" / "1" |
| Child lock | `cl` true / false (JSON bool); remote commands still work while it is on |

## Readings

- `pm25` (µg/m³), `iaql` (allergen index), `rh` (%), `temp` (°C) (**verified on device**).
- Filters in hours left: `fltsts0` pre-filter clean (interval 360), `fltsts1` HEPA (type `A3`), `fltsts2` carbon (type `C7`), `wicksts` wick (**verified on device**: values read; not watched counting down).
- Water: lifting the tank out sets bit `0x8000` in `err`; putting it back clears it. `wl` stayed at 100 throughout, so it isn't a level (**verified on device**).
- `om` reads "s" in sleep mode, and also in auto mode on this unit; "0" while off (**verified on device**).

## Open

- Once, six commands in a row (unlock, light, timer) were answered "success" and not applied; the next command (power off) worked, and so did everything since. Not reproduced, also not after 2 idle minutes from a Mac.
- Pushes stop while HomeDeck is in the background; HomeDeck subscribes again when it comes back.

## Sources

Philips Air+ 3.21.0 for Android, aioairctrl (MIT), py-air-control (MIT), the philips-airpurifier-coap Home Assistant integration (no licence: facts only). No third-party code copied. Details in `research/philips-ac2729/notes.md` (git-ignored).
