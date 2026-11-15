# HomeDeck

One iPhone app for my Bluetooth and Wi-Fi home devices, replacing their separate vendor apps. Each device is reverse-engineered and built as its own module, the same way as my [REX5 earbuds app](https://github.com/VM-development/noble-rex5-custom-app). The whole process is journaled in `docs/` for an article.

It isn't affiliated with any of the device makers.

## Devices

| Device | Link | Status |
|---|---|---|
| WalkingPad C2 | Bluetooth | Planned |
| Mi Body Composition Scale S400 | Bluetooth | Planned |
| Philips 2000i AC2729 | Wi-Fi | Planned |
| Bowers & Wilkins Zeppelin Pro Edition | Wi-Fi | Planned |
| Xiaomi Smart Standing Fan 2 Pro | Wi-Fi | Planned |
| Dreame L40 Ultra | Wi-Fi | Planned |
| AENO EK7S smart kettle | Wi-Fi | Planned |

The app's Market tab shows every feature of every device and whether it works yet. The Noble FoKus Rex5 earbuds keep their own [REX5 app](https://github.com/VM-development/noble-rex5-custom-app).

## How it's built

- `App/`: the SwiftUI shell (Home, Market, Settings) and each device's screens in `App/Devices/`.
- `Packages/`: one Swift package with `HubCore` (the device contract, feature choices, shared log) and one target per device for its protocol code, tested with `swift test`.
- `docs/adding-a-device.md`: the checklist each device follows; `docs/devices/<id>/` holds its protocol doc and journal.

## Build

You need Xcode 27 and an iPhone on iOS 26 or later.

```bash
cp Config/Team.xcconfig.example Config/Team.xcconfig   # then put your team ID in it
git config core.hooksPath hooks                         # privacy check before every push
open HomeDeck.xcodeproj
```

```bash
cd Packages && swift test
```

## License

[MIT](LICENSE). Device and brand names are trademarks of their owners.
