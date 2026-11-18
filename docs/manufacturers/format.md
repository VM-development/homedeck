# Open Local Control (OLC) 0.1

One JSON file per device model. It says how to talk to the device over Bluetooth or the home network, precisely enough to write an app from it, and how well the device keeps strangers out. The maker publishes it next to the manual, as `<maker>-<model>.olc.json`.

Two checks:

```bash
uvx check-jsonschema --schemafile docs/manufacturers/schema.json docs/manufacturers/examples/*.olc.json
python3 docs/manufacturers/check.py docs/manufacturers/examples/*.olc.json
```

The first checks the shape against [schema.json](schema.json). The second ([check.py](check.py), Python standard library only) decodes every example against its byte template, follows every reference, works out the security level from the security keys, and lists what is missing for `owner-key`.

The terms follow W3C's Web of Things Thing Description (properties, actions, messages, security), so an OLC file can be turned into a Thing Description where one is wanted. OLC adds three things: Bluetooth links, byte templates for binary protocols, and a security section that every file must fill in.

## Top level

| Key | Required | Holds |
|---|---|---|
| `olc` | yes | The format version, `"0.1"` |
| `device` | yes | `maker`, `model`, `firmware` (the versions the file was checked against), `category`, and optionally `manual` (a URL) |
| `links` | yes | How to reach the device |
| `security` | yes | How the device keeps strangers out |
| `messages` | yes | Every message on a link, with its exact bytes or JSON |
| `properties` | no | Values an app reads, writes or watches, such as speed |
| `actions` | no | Things an app triggers, such as start |
| `note` | no | Who wrote the file and from what, when it isn't the maker |

## Links

```json
{ "id": "ble", "type": "ble", "advertises": "FE00", "connections": 1,
  "services": [{ "uuid": "FE00", "characteristics": [{ "uuid": "FE01", "properties": ["read", "notify"] }] }] }
```

- `type`: `ble`, `http`, `https`, `websocket`, `coap`, `coaps`, `udp` or `tcp`.
- Bluetooth: `advertises` (the service UUID to scan for), `connections` (how many phones can be connected at once), and `services` with their characteristics. A characteristic's `properties` are `read`, `write`, `write-without-response`, `notify` and `indicate`.
- Network: `port`, and `discovery`, a list of ways to find the device. Each way is one of `{"bonjour": "_type._tcp"}`, `{"multicast": "<group address>"}`, `{"broadcast": <port>}`, `{"probe": "<request sent to each address>"}` or `{"manual": "<what the user types>"}`.
- TLS links (`https`, `websocket` over TLS, `coaps`): `certificate` is `ca`, `self-signed` or `pinned-at-pairing`.
- Any link can carry a `note`.

## Messages

A message is one thing sent on a link, named by its key in `messages`.

```json
"setSpeed": { "link": "ble", "to": "device", "characteristic": "FE02",
              "bytes": "F7 A2 01 {speed:u8*0.1} {sum8:1} FD",
              "examples": [{ "bytes": "F7 A2 01 19 BC FD", "fields": { "speed": 2.5 } }] }
```

| Key | Holds |
|---|---|
| `link` | A link id |
| `to` | `device` or `app` |
| `characteristic` | Bluetooth: the characteristic it is written to or notified on |
| `method`, `path` | HTTP and CoAP: the method (`GET`, `POST`, `PUT`, `DELETE`) and path. WebSocket: the path only |
| `observe` | `true` for a CoAP Observe request: its reply keeps coming |
| `reply` | The name of the message that answers this one |
| `encrypted` | `true` when the body is wrapped as `security.envelope` describes |
| `bytes` | A byte template (below) |
| `json`, `fields` | A JSON body: `json` is its fixed part, `fields` maps each property id to a JSON Pointer (RFC 6901) inside it |
| `text` | A plain-text body, described in words |
| `examples` | Real exchanges with private values replaced: `bytes` or `json`, and the `fields` they hold |
| `note` | Anything else an implementer must know |

A message has at most one of `bytes`, `json` and `text`. A message with none has an empty body.

### Byte templates

Tokens separated by spaces. Offsets count bytes from 0.

| Token | Meaning |
|---|---|
| `F7` | A fixed byte, two hex digits |
| `??` | A byte whose meaning isn't known; any value |
| `{name:type}` | A field. Types: `u8`, `i8`, and `u16`, `i16`, `u24`, `i24`, `u32`, `i32` each followed by `be` (big-endian) or `le` (little-endian), such as `u24be` |
| `{name:type*k}` | A scaled field: value = number on the wire × k. `{speed:u8*0.1}` reads `19` (25) as 2.5 |
| `{sum8:N}` | A checksum byte: the sum of the bytes from offset N up to this byte, mod 256 |
| `{xor8:N}` | A checksum byte: the XOR of the bytes from offset N up to this byte |

A field named after a property carries that property. Other names (a counter, a group byte) are allowed. Templates are fixed length in 0.1; variable-length messages are for a later version.

### Example fields

In `examples`, `fields` holds each value after scaling and before the enum lookup: `"speed": 2.5`, `"state": 1`, `"power": "1"`.

## Properties

```json
{ "id": "speed", "title": "Belt speed", "type": "number", "unit": "km/h", "max": 6.0, "step": 0.1,
  "read": "status", "write": "setSpeed", "note": "Accepted only while the belt runs; 0 stops it." }
```

- `type`: `number`, `integer`, `boolean`, `string` or `enum`. An enum lists its `values` as `{"wire": <value>, "means": "<text>"}`. The wire value keeps its JSON type, so `"1"` is not `1`.
- `unit`, `min`, `max`, `step`: optional.
- `read`: the message the value arrives in. The message whose `reply` names it is how to ask for it; if no message does, the device sends it on its own.
- `write`: the message that sets it.

## Actions

```json
{ "id": "start", "title": "Start the belt", "send": "start", "risky": true }
```

`send` names the message. `risky` is `true` when triggering the action unexpectedly could hurt someone or damage something: moving parts, heat, water.

## Security

Every file states one `level`. `check.py` works the level out from the other keys and fails a file whose stated level doesn't match.

| Level | Means |
|---|---|
| `open` | No key: anyone in range can control the device |
| `shared-secret` | Locked, but every unit uses the same key |
| `per-device-key` | Each unit has its own key, but not every `owner-key` requirement holds. Often the key comes only from the maker's cloud |
| `owner-key` | Every requirement in the right-hand column below holds |

| Key | Values | `owner-key` needs |
|---|---|---|
| `key` | `{"unique": "none" \| "per-model" \| "per-device", "from": "none" \| "app" \| "vendor-cloud" \| "device" \| "pairing"}`: whether the key differs per unit, and where an app gets it | `per-device`, from `device` or `pairing`, so no cloud is involved |
| `pairing` | `none`, `ble-just-works`, `ble-passkey`, `ble-numeric-comparison`, `ble-oob`, `setup-code-pake`, `shared-secret`, `vendor-account` | `ble-passkey`, `ble-numeric-comparison`, `ble-oob` or `setup-code-pake` |
| `setupCode` | `none`, `label`, `display`, `box`: where the owner finds the code that proves they hold the device | Not `none` |
| `encryption` | `none`, `tls`, `ble-link-layer`, `aes-cbc`, `aes-ccm`, `aes-gcm`, `chacha20-poly1305` | Not `none` |
| `integrity` | `none`, `unkeyed-hash`, `keyed-hash`, `aead`: whether a stranger can change a message without it being noticed | `keyed-hash` or `aead` |
| `freshness` | `none`, `unauthenticated-counter`, `counter`, `nonce`, `tls`: whether an old message can be sent again | `counter`, `nonce` or `tls` |
| `controllers` | `anyone`, `one`, `many`, `many-revocable`: how many apps the owner can allow | `many-revocable` |
| `worksOffline` | `true` or `false`: whether local control works with no internet | `true` |
| `buttonPressFor` | Action ids that only run after a button press on the device | Every `risky` action |
| `otherInterfaces` | `[{"what": "<text>", "protection": "none" \| "unknown" \| "same" \| "signed-firmware"}]`: anything else listening, such as a firmware update service | Nothing with `none` or `unknown` |
| `disclosure` | `{"contact": "<URL or null>", "supportUntil": "<YYYY-MM or null>"}`: where to report a vulnerability, and until when the model gets security updates | Both filled |
| `envelope` | Text: how encrypted messages are wrapped, precisely enough to implement | |
| `note` | Text | |

TLS links count too: `owner-key` needs `certificate` to be `pinned-at-pairing`, or `ca`.

A device with no local link (one that only works through its maker's cloud) has nothing for OLC to describe.
