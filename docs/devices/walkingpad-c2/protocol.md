# WalkingPad C2: protocol

Every claim carries one evidence label: **verified on device**, **from APK**, **from open source**, or **guess**.
No real names, addresses, keys or tokens: use placeholders such as `<phone>`, `AA:BB:CC` or `<token>`.

## Device

- Model: KingSmith WalkingPad C2. Advertises as `KS-BDC2` (**verified on device**).
- Firmware tested: not read (Device Information is there but HomeDeck doesn't read it).
- Vendor app: KS Fit. Its APK wasn't needed: the open-source protocol covered every feature HomeDeck uses.

## Transport

Bluetooth Low Energy, no pairing or bonding (**verified on device**).

| Service | Characteristics | Use |
|---|---|---|
| `FE00` | `FE01` read, notify; `FE02` write without response | the whole protocol |
| Device Information (`180A`) | model, serial, firmware and other strings | not used |
| `F000FFC0-0451-4000-B000-000000000000` | `…FFC1`, `…FFC2` write, notify | Texas Instruments firmware update; not used |

All **verified on device**. There is no FTMS (`1826`) service. Scan by the `FE00` service, not by name.

## Keys and sessions

None. After subscribing to `FE01` the pad answers the first status request; the profile-and-beep handshake some projects send first isn't needed on the C2 (**verified on device**). The pad talks to one phone at a time, so KS Fit must be closed (**from open source**, matches the owner's setup).

## Packet format

- Command (phone to pad, `FE02`): `F7 <group> <payload> <checksum> FD`, checksum = sum of group and payload bytes mod 256. Example: set speed 2.5 km/h = `F7 A2 01 19 BC FD` (**verified on device**).
- Reply (pad to phone, `FE01`): 20 bytes, `F8 <type> … <checksum> FD`, checksum = sum of bytes 1 to 17 mod 256 (**verified on device**).
- Numbers over one byte are 3 bytes, big-endian (**verified on device**).

## Commands

| Name | Bytes | Payload | Reply | Evidence |
|---|---|---|---|---|
| Ask status | `F7 A2 00 00 A2 FD` | none | status frame | verified on device |
| Start belt | `F7 A2 04 01 A7 FD` | none | countdown states 9, 8, 7, then 1 | verified on device |
| Set speed | `F7 A2 01 <v> <crc> FD` | v = km/h x 10; accepted only while running | status speed follows | verified on device (2.0, 2.5) |
| Stop belt | `F7 A2 01 00 A3 FD` | speed 0 | belt ramps down to state 0 | verified on device |
| Set mode | `F7 A2 02 <m> <crc> FD` | 0 automatic, 1 manual, 2 standby | status mode byte follows | verified on device (all three) |
| Ask settings | `F7 A6 00 00 00 00 00 A6 FD` | none | `F8 A6` frame: max 6.0 km/h, start 2.0 km/h, sensitivity 2, display mask `1F` | verified on device (reply); field meaning from open source |
| Ask newest stored walk | `F7 A7 AA FF 50 FD` | none | `F8 A7` frame of zeros, "0 stored", even right after 12 s and 2 min walks | verified on device |

Start from standby is ignored by the pad, so HomeDeck switches to manual first and starts one poll later (**from open source**; the order worked on the device).

## Pushed updates

None: the pad only answers requests. HomeDeck asks for status every 0.75 s and sends commands in the next slot, so writes stay at least 0.75 s apart (**verified on device**: polling kept running with the phone locked for 30 s, since the app has the Bluetooth background mode).

Status frame `F8 A2`, byte offsets:

| Bytes | Field | Example (`f8a20114010000850000060000ad00000300f3fd`) |
|---|---|---|
| 2 | belt state: 0 stopped, 1 running, 4 standby, 7 to 9 countdown | 1 |
| 3 | speed, 0.1 km/h | 2.0 km/h |
| 4 | mode: 0 automatic, 1 manual, 2 standby | manual |
| 5-7 | time, seconds | 133 s |
| 8-10 | distance, 10 m | 60 m |
| 11-13 | steps | 173 |
| 14 | the speed last set from the phone, 0.1 km/h; 0 after stop | 0 here, `19` while 2.5 was set |
| 16 | 3 after a start from the phone (button code per open source) | 3 |

All **verified on device** except byte 16's meaning (**guess**).

## Quirks

- The pad stores no walks HomeDeck can read (`F8 A7` is always zeros), so HomeDeck records a walk itself: counters when the belt starts, minus counters when it stops (**verified on device**: 124 s, 60 m, 164 steps saved).
- Time, distance and steps don't reset between walks; standby resets them. After about 10 minutes idle the pad goes to standby by itself (**verified on device**).
- Right after start the speed reads 3.0, then settles to the 2.0 km/h start speed within two seconds (**verified on device**).
- iOS restored the connection itself after an app reinstall ("restored by iOS" in the log) (**verified on device**).

## Sources

Read only, never run; HomeDeck's code and this document are written from the behaviour, not copied:
- MIT: ph4r05/ph4-walkingpad (origin of the protocol), indiefan/king_smith, mcdax/hass-walkingpad, mcdax/walkingpad-controller.
- Apache 2.0: klassm/walkingpad_macos_client.
- No licence file: z0vsky/pad2pod, k0siara/walkingpad-macos, asynchroza/walkingpad-c2-reverse-engineer-bluetooth.
- GPL 3, reference only: DorianRudolph/QWalkingPad.
- Official C2 product page and FAQ (walkingpad.com).
- Own captures: the HomeDeck connection log, kept in `research/walkingpad-c2/`.
