# Mi Body Composition Scale S400: protocol

Every claim carries one evidence label: **verified on device**, **from APK**, **from open source**, or **guess**.
No real names, addresses, keys or tokens: use placeholders such as `<phone>`, `AA:BB:CC` or `<token>`.
The owner's own measurements (weight, heart rate, impedance) are health data and stay out of this file too.

## Device

- Model: Xiaomi Body Composition Scale S400 (MJTZC01YM), cloud model `yunmai.scales.ms104`, MiBeacon product id `0x3BD5` (**verified on device**).
- Other S400 product ids HomeDeck accepts: `0x30D9`, `0x48CF`, `0x4FC2`, `0x4B05` (S400 Pro), `0x78BD` (global S400 Pro, untested) (**from APK**: the bundled product catalogue).
- Vendor app: Xiaomi Home. Its Android APK (11.7.623) was read for the frame parser and the bind-key source; the S400's own plugin is downloaded at runtime and isn't in the APK.

## Transport

Bluetooth advertisements only; HomeDeck never connects. Each frame is service data under the 16-bit UUID `FE95` (**verified on device**). iOS delivers it to a scan filtered on `FE95` (**verified on device**), which also allows background scanning (not yet tested with the phone locked).

The scale wakes when someone steps on it and sends (**verified on device**):
1. an unencrypted idle frame that includes the MAC (frame control `0x5910`);
2. an encrypted measurement frame: weight, 50 kHz impedance, heart rate;
3. an encrypted frame with the 250 kHz impedance only, about a second later, same timestamp.

No "reset" frame was seen on stepping off, though open source describes one.

## Keys and sessions

- **Bind key** (16 bytes): from the Xiaomi cloud, `/v2/device/blt_get_beaconkey` (**from APK**). The owner gets it with Xiaomi Cloud Tokens Extractor and pastes it into HomeDeck, which keeps it in the Keychain. It changes when the scale is reset or re-added in Xiaomi Home (**from open source**).
- **MAC** (6 bytes, part of the nonce): measurement frames don't carry it, but the idle frame does; HomeDeck learns it from there (**verified on device**), so the owner never types it.

## Packet format

MiBeacon frame, little-endian (**from APK** and **from open source**, offsets **verified on device**):

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | frame control: bit 3 encrypted, 4 MAC included, 5 capability, 6 object, 10-11 auth mode, 12-15 version |
| 2 | 2 | product id |
| 4 | 1 | frame counter (new value per frame; adverts repeat it) |
| 5 | 6 | MAC, byte-reversed (when bit 4 is set) |
| … | n | encrypted objects |
| end-7 | 3 | extended counter |
| end-4 | 4 | CCM tag |

Encryption: AES-128-CCM, 4-byte tag, AAD = the single byte `0x11`, 12-byte nonce = MAC reversed + product id + frame counter + extended counter (**from open source**, **verified on device**). CryptoKit has no CCM, so HomeDeck builds it on CommonCrypto's AES block function.

Worked example: the published test frame in Bluetooth-Devices/xiaomi-ble (made-up MAC `8C:D0:B2:F6:BE:EF`, public test key) decrypts to object `0x6E16` = profile 1, 69.9 kg, 92 bpm, 543.2 ohm. `Packages/Tests/MiScaleKitTests` checks it and four more published frames.

## Commands

None: the scale only broadcasts.

| Object | Payload (9 bytes) | Evidence |
|---|---|---|
| `0x6E16` measurement | profile slot u8; u32 with bits 0-10 weight in 0.1 kg, 11-17 heart rate minus 50 (0 or 127 = none), 18-31 impedance in 0.1 ohm; u32 timestamp (Unix, the scale's clock) | from open source, verified on device |

## Pushed updates

See Transport. A weigh-in is grouped by its timestamp; HomeDeck saves it to Apple Health 20 s after its last frame.

## Quirks

- Heart rate appears only after about 20 s barefoot; the first weigh-in had none (**verified on device**).
- Two weigh-ins seven minutes apart reported identical impedances at both frequencies; the scale may reuse a recent measurement (**guess**).
- The scale's clock matched the phone's within seconds (**verified on device**); HomeDeck falls back to the phone's time if they differ by more than two days.
- Xiaomi Home must be closed during a weigh-in: while it's connected, the scale may stop broadcasting (**from open source**; not tested).
- Body composition is HomeDeck's estimate: fat-free mass and body water from Sun et al. 2003 (NHANES III), skeletal muscle from Janssen et al. 2000, bone as 5% of lean mass (a rough ratio, **guess**). Xiaomi's own formula isn't public; the scale computes its own figures and stores them for Xiaomi Home over a logged-in GATT connection (**from open source**), which HomeDeck doesn't use.

## Sources

- APK: Xiaomi Home for Android 11.7.623 (beacon parser, beacon-key request, product catalogue), notes in `research/xiaomi/`.
- Apache 2.0: Bluetooth-Devices/xiaomi-ble (frame layout, `0x6E16`, test frames used in HomeDeck's tests), nokistin/xiaomi-s400-live, snelstim/ha-xiaomi-s400, jaydeethree/Home-Assistant-xiaomi-s400-scale.
- MIT: PiotrMachowski/Xiaomi-cloud-tokens-extractor (the owner runs it to get the bind key), AlexxIT/SmartScaleConnect.
- GPL 3, read for facts only: KristianP26/ble-scale-sync, RobertWojtowicz/export2garmin, oliexdev/openScale.
- Papers: Sun SS et al., Am J Clin Nutr 2003;77:331-340. Janssen I et al., J Appl Physiol 2000;89:465-471.
