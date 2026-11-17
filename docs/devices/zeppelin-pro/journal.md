# Bowers & Wilkins Zeppelin Pro Edition: journal

Entries are only ever appended; dead ends stay. No real names, addresses, ids or serials.

## 2026-11-13: Open-source pass (before HomeDeck code)

**Tried:** GitHub search and four open-source projects; the B&W product and app pages. Raw notes in `research/zeppelin-pro/`.
**Device answered:** n/a.
**Conclusion:** A local JSON API on HTTPS 42425 plus a WebSocket, and a StreamSDK settings API on port 80; no account. Open: the WebSocket path, and whether firmware changed anything.
**Next:** Probe the owner's speaker.

## 2026-11-17: Probe, build and test

**Tried:** Bonjour browse and resolve from the Mac, read-only GETs and `get_property` queries with the WebSocket open, the port-80 standby setting, a capture while AirPlay played; then `ZeppelinKit` and the screen.
**Device answered:**
- Found by `_eva-mesh._tcp` on the first try (on the right Wi-Fi this time). The API answered on 42425, not on the advertised 45525. Every value the open-source code describes was there; the WebSocket path is `/messages`.
- First phone build crashed: the found address carried `%en0`, and a force-unwrapped URL failed. Fixed (address from its bytes, no force-unwraps, old saved values cleaned).
- Mute didn't unmute and the volume slider jumped. From the Mac: the speaker ignores `muted: true`, and set_volume's `success` reply echoes the old volume before `volume_changed` brings the new one. Mute is now volume 0 with restore, and only `volume_changed` counts.
- Standby first showed no trace in the log (the owner's first answer covered more than was tried); a log line on tap showed it working next time: 600, 900 and 1200 set and read back.
**Conclusion:** All seven features work (verified on device), except that installing a firmware update was not tried (none was available). The feature "Standby and auto-wake" became "Auto standby": no auto-wake setting exists.
**Next:** Hub review and merge.
Article note: the worst bug here was a polite one: the speaker answers "success" to a volume change and, in the same breath, reports the old volume.
