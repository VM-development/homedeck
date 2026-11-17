# AENO EK7S kettle: journal

Entries are only ever appended; dead ends stay. No real names, addresses, ids or keys.

## 2026-11-17: Looking for the kettle, then pausing

**Tried:**
- Listened 20 s on the Mac for Tuya LAN broadcasts (UDP 6666, 6667, 7000, decrypted with the public broadcast key from tinytuya, MIT), and scanned the /24 for Tuya's TCP port 6668.
- Read how the open-source Tuya Bluetooth integration (PlusPlus-ua/ha_tuya_ble, MIT) logs in.
**Device answered:**
- Nothing on the network: no broadcast and no host with TCP 6668 open. The Mac's firewall was on, which can drop broadcasts, but the port scan doesn't depend on them.
- The owner reports that the kettle is controlled over Bluetooth (not verified with a Bluetooth scan). The catalog entry now says Bluetooth instead of Wi-Fi.
- Tuya Bluetooth needs three values from Tuya's cloud: the device's UUID, device id and local key. The login key is MD5 of the local key's first 6 characters; each session key is MD5 of those 6 characters plus a random value from the kettle (from open source).
**Conclusion:** Local control, Bluetooth or Wi-Fi, needs the kettle's key from Tuya's cloud. The owner wants to keep the AENO app, so these routes stay closed:
- Re-adding the kettle in Tuya's Smart Life app and reading the key there: declined.
- Using AENO's own app keys from its APK to ask the cloud: not done, those are vendor secrets.

An iPhone backup might hold the key in the AENO app's files. The owner declined the full backup it needs.
**Next:** Paused. Restart from here if the owner changes the app or finds the key.
Article note: two Wi-Fi devices had simply been on another network; the third device wasn't on Wi-Fi at all.
