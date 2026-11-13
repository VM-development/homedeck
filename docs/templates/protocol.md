# <Device>: protocol

Every claim carries one evidence label: **verified on device**, **from APK**, **from open source**, or **guess**.
No real names, addresses, keys or tokens: use placeholders such as `<phone>`, `AA:BB:CC` or `<token>`.

## Device

- Model:
- Firmware tested:
- Vendor app and version (iOS and the Android APK studied):

## Transport

Bluetooth: services, characteristics and their properties. Wi-Fi: address discovery (Bonjour type, UDP broadcast, cloud), port, protocol.

## Keys and sessions

Pairing, tokens, encryption, and where each key comes from (device, vendor cloud, APK constant).

## Packet format

Byte layout with a worked example.

## Commands

| Name | Bytes or endpoint | Payload | Reply | Evidence |
|---|---|---|---|---|

## Pushed updates

What the device sends on its own, and when.

## Quirks

Behaviour that surprised us, with the log line or capture that shows it.

## Sources

Open-source projects (with links and licences), APK classes, own captures in `research/<device>/`.
