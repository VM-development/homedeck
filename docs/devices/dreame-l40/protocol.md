# Dreame L40 Ultra CE: protocol

Every claim carries one evidence label: **verified on device**, **from APK**, **from open source**, or **guess**.
No real names, addresses, ids, tokens or keys: use placeholders such as `<did>` or `<token>`.

## Device and path

- Cloud model `dreame.vacuum.r5021a`, one of the ids Tasshack's docs give for the L40 Ultra CE (**verified on device**). No public MIoT spec exists for it.
- No local control: robots bound to the Dreamehome app switch their local API off, and post-2022 Dreame robots can't join Mi Home (**from open source**: Tasshack's docs and issues). HomeDeck uses the Dreamehome cloud, the first device that needs a vendor account.

## Dreamehome cloud

- Host `https://<region>.iot.dreame.tech:13267` (EU account: `eu`) (**from APK**, **verified on device**). Apple's TLS stack (`URLSession`) is accepted (**verified on device**).
- Sign-in: `POST /dreame-auth/oauth/token`, form `grant_type=password&scope=all&platform=ANDROID&type=account&username=<url-encoded>&password=<md5(password + salt)>`; refresh with `grant_type=refresh_token…`. A Google/Apple account needs a password set in the Dreamehome app first; a wrong password answers `401 user password not match` (**verified on device**).
- Headers: `User-Agent: Dart/3.9 (dart:io)`, `dreame-meta: cv=a_102060700;canvasHash=…;webglHash=…;visitorIdHash=…`, `authorization: Basic <client blob>`, `tenant-id` (`000000` before sign-in), `dreame-rlc` (AES-128-ECB of `region|lang|country` under the signing key, after sign-in), `dreame-auth: <access token>` (**from open source**, **verified on device**).
- Every JSON body is signed: `sign` = MD5(canonical string of the sorted parameters + milliseconds + signing key), plus `timestamp` (**from open source**, **verified on device**; rules pinned in `Packages/Tests/DreameKitTests`).
- Robot: `POST /dreame-user-iot/iotuserbind/device/listV2` (no body), then `…/device/info {"did"}` for `bindDomain`. Commands: `POST /dreame-iot-com-<first label of bindDomain>/device/sendCommand` with `{"did","id","data":{"did","id","method","params"}}`; the reply's `data.result` is the MIoT result. `80001` means the robot didn't answer (**from open source**, **verified on device**).
- The fixed salt, client blob and signing key are published in Tasshack/dreame-vacuum (MIT) and all three are inside Dreamehome for Android 2.6.7.0 (versionCode 102060700, Oct 2026) unchanged (**from APK**, checked by presence without printing them). HomeDeck keeps them in the git-ignored `Config/Secrets.xcconfig`; the tests use made-up ones. Map download (`getOss1dDownloadUrl`) is not in 2.6.7.0, so maps may have moved (**from APK**).

## MIoT values on this robot

All **verified on device** (read, and for writes `code 0`):

| What | Address | Notes |
|---|---|---|
| State | `2.1` | 1 cleaning … 6 charging, 13 charged (Tasshack's list) |
| Error | `2.2` | 0 = none |
| Battery, charging | `3.1`, `3.2` | |
| Last clean time, area | `4.2` (min), `4.3` (m²) | |
| Suction | `4.4` | 0 quiet, 1 standard, 2 strong, 3 turbo |
| Cleaning mode | `4.23`, low two bits | packed with the mop-wash interval in the next byte (5122 = vacuum only, interval 20). Mop-lift robot: 2 vacuum, 1 mop, 0 both, 3 mop after vacuum; written with Tasshack's split/combine |
| Water | `4.5` = 2 (three levels) and `28.1` = 25 (wetness 1–32) | both answer; writing not tested (the owner's water tank is broken) |
| Dock | `4.25` mop dock state, `15.5` auto-empty state, `15.1` auto-empty on | |
| Do not disturb | `5.1` on/off, `5.2`, `5.3` "HH:MM" | the CE has it, unlike Tasshack's guess from capability flags |
| Lifetime | `12.1` first use, `12.2` minutes, `12.3` count, `12.4` m² | |
| Parts, % and hours left | brush `9.2`/`9.1`, side brush `10.2`/`10.1`, filter `11.1`/`11.2`, sensors `16.1`/`16.2`, wheel `30.2`/`30.1` | mop pads (`18.x`), `17.x`, `32.x` don't answer |
| Actions | start `2.1`, pause `2.2`, dock `3.1`, stop `4.2`, mop wash `4.4` with piid 10 "2,1", dry "3,1", empty bin `15.1` | all `code 0`; wash and dry not checked by eye |
| Also read | `4.11` resume after charge, `4.12` carpet boost, `4.27` child lock, `4.28` carpet sensitivity, `4.37` auto detergent, `4.40`, `4.46`, `7.1` volume, `8.1` time zone, `27.x` | |
| No answer | `4.10`, `6.3` (map file name), `17.x`, `18.x`, `32.x` | |

## Map and rooms

All **verified on device** unless marked:
- The map file name isn't a readable property (`6.3` gives no answer). Action `6.1` with piid 2 = `{"req_type":1,"frame_type":"I","force_type":1}` returns it: `out` has piid 3 = `<file>,<key>` (32 characters on this robot), piid 1 (inline map, empty here) and piid 5 (**from open source** for the shape).
- `POST /dreame-user-iot/iotfile/getDownloadUrl {did, model, filename: <file>, region}` returns a short-lived link; a plain GET gives the file (about 21 KB). The main Dreamehome app doesn't contain this path: the robot's panel is probably a plugin loaded at runtime (**guess**). `getOss1dDownloadUrl` is kept as a fallback (**from open source**, not needed here).
- Decoding as in the kit's `DreameMap`: URL-safe base64, AES-256-CBC (key = first 32 hex characters of SHA-256 of `<key>`, IV = the L40 family's fixed string, git-ignored as `DREAME_MAP_IV_HEX`), zlib, a 27-byte header, one byte per pixel, JSON.
- This robot's live frame: 154 × 522 pixels of 5 cm, JSON with `fsm` = 1, so each pixel stores room × 4 (63 wall, 62 floor; low bits 3 = carpet). The rooms (`seg_inf`) aren't in the live frame but in the saved map it carries under `rism` (base64 + zlib, not encrypted; 224 × 592 here): 8 rooms, ids 1–8, no names or types set, so they show as Room 1–8. The ids match the live frame's room pixels.
- Drawn the Tasshack way the image was upside down for the owner; the owner's Dreamehome shows it mirrored left to right relative to the raw rows (Tasshack's flip plus a 180° turn). Dreamehome lets owners rotate the map, so another robot may need its rotation setting read.
- Room cleaning: action `4.1` with piid 1 = 18 and piid 10 = `{"selects":[[room, 1, suction, water, 1], …]}`; `clean rooms [5]` sent the robot to that room.

## Not done

- Schedules (`8.2`): format not decoded.
- Zone cleaning, go-to-point, map editing.

## Sources

Tasshack/dreame-vacuum (MIT), Hypfer/Valetudo, FnrDev/DreameBar (licence unclear: learned from, not copied), Dreamehome for Android 2.6.7.0 (owner-supplied APK, read for strings only). Details in `research/dreame-l40/notes.md` (git-ignored).
