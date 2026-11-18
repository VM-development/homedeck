# A proposal to smart-home device makers: publish the protocol, lock it to the owner

HomeDeck is a hobby iPhone app that controls seven devices from seven makers, without their apps. None of them publishes how its device talks, so every protocol was worked out from open-source projects, the makers' Android apps and tests on the real devices. Along the way it became clear how each device keeps strangers out, and most do it badly in one of two opposite ways.

This folder is a proposal to fix both with one small step: describe the protocol in a published file, and lock it to the owner. It has four parts:

- this page;
- [format.md](format.md), the Open Local Control (OLC) format;
- [schema.json](schema.json) and [check.py](check.py), which check a file;
- [examples/](examples/), two of HomeDeck's devices described as they are today.

## What we found

| Device | Link | What stops a stranger | Result |
|---|---|---|---|
| WalkingPad C2 | Bluetooth | Nothing: no pairing, no key | Any phone in range can start the belt |
| Zeppelin Pro | Wi-Fi | Nothing: HTTPS with a self-signed certificate, no login | Anyone on the Wi-Fi can change the volume, sound, light and playback |
| Philips AC2729 | Wi-Fi | One secret shared by every unit, published in open-source code | Anyone on the Wi-Fi can control it |
| Xiaomi fan | Wi-Fi | A key per device | Safe from strangers. The owner can only get the key from Xiaomi's cloud, with an unofficial tool |
| Mi Scale S400 | Bluetooth | A key per device | Same as the fan |
| AENO kettle | Bluetooth, Wi-Fi | A key per device, from Tuya's cloud | Safe from strangers, and from the owner too: HomeDeck stopped here |
| Dreame L40 | Cloud only | The account; local control is switched off | Safe from strangers. Without the maker's cloud, nothing works |

Everything in this table is already public in open-source projects that control these devices.

Three devices are open to everyone in range. The other four are closed to strangers, but also to their owner, unless the owner goes through the maker's cloud. They are opposite failures, and one design fixes both: a key that is unique to each unit, that the owner can get from the device itself, and that nobody else has.

## The ask

1. **Publish an OLC file for each model**, next to the manual. Your own app was built from a protocol description; this is that description in a shared shape. [format.md](format.md) explains every key, and the two examples show how a Bluetooth device and a Wi-Fi device look.
2. **Reach the `owner-key` security level.** In short:
   - a setup code that is unique to each unit, printed on the label or shown on the display;
   - pairing that uses it: Bluetooth passkey, numeric comparison or out-of-band pairing (a QR code), or a PAKE such as SPAKE2+ on Wi-Fi;
   - a separate credential for each app the owner allows, and a way to remove each one;
   - authenticated encryption (AES-CCM, AES-GCM, ChaCha20-Poly1305 or TLS) with replay protection;
   - local control that keeps working with no internet.
3. **Ask for a button press on the device before risky actions**: starting a treadmill belt, heating a kettle.
4. **Close or protect everything else that listens**, such as a firmware update service: signed firmware only.
5. **Publish a vulnerability contact and the date security updates end.**

`check.py` works out a file's level and lists what is missing for `owner-key`. For the WalkingPad C2 today it lists eleven gaps, starting with "key is none: give every unit its own key". Here is the security part of the same pad at `owner-key`:

```json
"security": {
  "level": "owner-key",
  "key": { "unique": "per-device", "from": "pairing" },
  "pairing": "ble-oob",
  "setupCode": "label",
  "encryption": "ble-link-layer",
  "integrity": "aead",
  "freshness": "counter",
  "controllers": "many-revocable",
  "worksOffline": true,
  "buttonPressFor": ["start"],
  "otherInterfaces": [{ "what": "Firmware update service", "protection": "signed-firmware" }],
  "disclosure": { "contact": "https://example.com/security", "supportUntil": "2031-12" },
  "note": "A QR code on the label carries the out-of-band pairing data. The app asks the owner to press the pad's button before the belt starts."
}
```

## Why it is worth doing

- **People reverse engineer your device anyway.** Every device in the table already has open-source projects that control it. Hiding the protocol didn't keep it secret; it only made owners depend on unofficial tools. A published protocol behind a real key is safer than a hidden one behind a shared secret.
- **The rules are moving the same way.**
  - UK: the PSTI product security regime has applied since 29 April 2024. It bans universal default passwords and requires a published place to report security issues and a published support period.
  - EU radio equipment: the Radio Equipment Directive's cybersecurity rules (Delegated Regulation 2022/30, harmonised standards EN 18031-1 to -3) have applied since 1 August 2025 to radio equipment that reaches the internet, directly or through other equipment.
  - EU Cyber Resilience Act: vulnerability reporting has applied since 11 September 2026, and the main obligations apply from 11 December 2027. One of them is a support period whose end date is stated at purchase, normally at least five years.

  Much of this builds on ETSI EN 303 645, the consumer IoT baseline mapped below.
- **Use Matter and Bluetooth's own profiles where they fit.** Matter has covered fans, air purifiers and robot vacuums since version 1.2. It already gives you most of `owner-key`: a setup code checked with SPAKE2+, encrypted local control, and several apps at once. Bluetooth has standard services for treadmills (Fitness Machine) and scales (Weight Scale, Body Composition). The WalkingPad C2 uses neither, so apps that speak only the standard never see it. OLC is for everything else, such as kettles, which have no Matter device type as of Matter 1.6, and for the custom protocol you already ship.

## How `owner-key` maps to the baseline

ETSI EN 303 645 V3.1.3 (2024-09). "M" marks a mandatory provision, "R" a recommendation.

| `owner-key` asks for | ETSI EN 303 645 | Also in |
|---|---|---|
| A key unique to each unit, nothing secret shared by every unit | 5.4-3 (M): no hard-coded critical security parameters in software. 5.4-4 (M): parameters for communication are unique per device. 5.1-1 (M) says the same for passwords | UK PSTI (passwords), EU CRA |
| Pairing with a setup code before anything can be changed | 5.5-5 (M): security-relevant changes over a network only after authentication | EU CRA |
| Authenticated encryption with replay protection | 5.5-1 (M): best-practice cryptography | EU CRA |
| Local control with no internet | 5.9-2 (R) | |
| Close or protect everything else that listens | 5.6-1 (M): disable unused network interfaces. Signed firmware: section 5.3 | EU CRA |
| A vulnerability contact | 5.2-1 (M): a published vulnerability disclosure policy | UK PSTI, EU CRA |
| A support end date | Section 5.3 | UK PSTI, EU CRA |
| A button press before risky actions | Not in the baseline: added here for devices with moving parts or heat | |
| Several apps, each removable | Not in the baseline: added here so the owner isn't locked to one app | |

## Status

OLC 0.1 is a draft by one hobby project, written with Claude Code. HomeDeck is not affiliated with any maker named here. Comments and corrections are welcome as GitHub issues on [VM-development/homedeck](https://github.com/VM-development/homedeck).
