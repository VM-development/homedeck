# Bowers & Wilkins Zeppelin Pro Edition: protocol

Every claim carries one evidence label: **verified on device**, **from APK**, **from open source**, or **guess**.
No real names, addresses, ids or serials: use placeholders such as `<ip>` or `<node>`. The speaker's room ("space") name is private too.

## Device

- Type `com.bowerswilkins.liberty.zpr`, software version `11211`, mesh protocol `mesh.0.4` (**verified on device**). B&W's app ("Music | Bowers & Wilkins", Android package `com.bowerswilkins.splice`) was not read; everything comes from open source and the speaker itself.
- No account and no cloud for anything below (**verified on device**).

## Finding it

- Bonjour `_eva-mesh._tcp` with TXT keys `typ`, `ver`, `swv`, `rl`, `mid`, `bid`, `spc`, `snm` (the room name), `fpp`, `cc`, `_d` (**verified on device**). The advertised port (45525) refuses HTTPS; the API is on 42425 (**verified on device**).
- HomeDeck browses `_eva-mesh._tcp` (Info.plist `NSBonjourServices`) and opens a UDP "connection" to the result, which resolves the service to an IPv4 address without needing an answer. Network.framework's address text can carry an interface suffix (`%en0`) that breaks a URL; HomeDeck builds the address from its four bytes (**verified on device**: the first build crashed on this).

## The stated API (HTTPS 42425, self-signed certificate)

- `GET /mesh/node` → `{"node_id": "<node>"}`; `GET /software/version`; `GET /1/mesh/nodes` (all mesh members with room name and type) (**verified on device**).
- Queries: `POST /mesh/node/<node>/channel/com.bowerswilkins.stated.service+provider/message` with `{"type":"query","method":{"name":…,"parameters":{…}}}` (**from open source**, **verified on device**).
- `get_property` answers 200 with `{"property","value"}` in the body; `get_volume`, the now-playing record and the source list answer 202 with an empty body, and the value arrives on the WebSocket (**verified on device**).
- WebSocket `wss://<ip>:42425/messages` (the open-source docs also name `/message`; `/messages` works). Envelope: `payload.args.message.method {name, parameters}`, with `payload.args.sendingNodeID`; every mesh member relays the others' messages, so filter by node (**verified on device**, **from open source**).
- HomeDeck accepts the self-signed certificate on first contact and pins its SHA-256 after that.

| What | Call | Notes (all **verified on device**) |
|---|---|---|
| Volume | `set_volume {value 0-100, source "", muted}`; pushes `volume_changed {value, muted}` | `muted: true` is ignored (the speaker keeps reporting `false`), so HomeDeck mutes by setting 0 and restoring. set_volume's own `success` reply carries the **old** volume, before `volume_changed` brings the new one: only `volume_changed` and the answer to `get_volume` count. |
| Bass, treble | `get_property` / `set_property` `liberty.property.gain.bass` / `.treble` | hundredths of a dB; -100 to +600 tried, 1 dB steps |
| Light | `liberty.lights.hardware-downlight` `{enabled, brightness 0.01-1, rgb {red, green, blue}, supported}` | on/off, brightness and colour all take |
| Transport | `send_command {command}` with `liberty.command.play_pause`, `next_track`, `previous_track` | worked with AirPlay as the source |
| Now playing | `liberty.oobed.audiotile`: a map keyed `<node>+<service>` with `title, artist, album, serviceName, state, duration, elapsedTime (ms), enabledPlaybackActions, sinkNodeIDs` | pushed about once a second while playing; `state` 1 = playing, 2 = paused; an empty map when nothing plays (an AirPlay session ended about 10 s after pausing) |
| Firmware | `check_software_update` → `{update_available, update_version, update_release_notes}` in the body; `start_software_update` | the check works ("up to date"); install not tried, as no update was available |

## Settings API (StreamSDK, plain HTTP 80)

- `GET /api/getData?path=settings:/system/maxIdleTime&roles=value` → `[{"type":"i32_","i32_":1200}]`; `GET /api/setData?path=…&role=value&value={"type":"i32_","i32_":N}` (**verified on device**).
- Auto standby is `maxIdleTime` in seconds. The SDK's own list offers 0, 300, 600, 900, 1800, but the speaker was at 1200 (20 min); 600, 900 and 1200 all take and read back (**verified on device**). HomeDeck offers Never, 5, 10, 15, 20, 30 min.
- No auto-wake setting was found (the settings catalog has none) (**from open source**). Needs the ATS `NSAllowsLocalNetworking` exception for plain HTTP.

## Sources

space192/zeppelin (Home Assistant integration, MIT), Oschangkai/bowerswilkins-local-api (docs), haroldxie2308/zeppelin-fix (settings catalog), MerlinMoelter/bw-formation. No code copied. Details in `research/zeppelin-pro/notes.md` (git-ignored).
