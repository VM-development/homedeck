# Device skill and LinkedIn series: design

Date: 2026-11-18. Approved by the owner in conversation, with two changes: keep `dexdump` for APKs, and mention REA.

## Part A: one skill for the whole device loop

The existing `.claude/skills/add-device` skill holds everything. A script in its folder, `hd.py` (Python 3, standard library only), does the work that was repeated by hand.

### One format: `device.json`

Each kit's `features.json` becomes `device.json`. It holds everything the Market and Home need:

```json
{
  "id": "zeppelin-pro",
  "name": "Zeppelin Pro Edition",
  "symbol": "hifispeaker",
  "link": "wifi",
  "category": "music",
  "features": [{ "id": "volume", "title": "Volume", "status": "working" }]
}
```

- HubCore decodes it. `DeviceCategory` and `Link` are `Codable` with lowercase raw values. The category title on screen is `rawValue.capitalized`.
- `DeviceKind(manifest: URL, makeDevice:)` replaces the init that took id, name, symbol, link, category and a features URL.
- Each kit's `Catalog.swift` exposes `manifest` (the bundled `device.json`) in place of `featuresURL`.
- `Package.swift` processes `device.json`.
- `DeviceRegistry` lines shrink to `DeviceKind(manifest: ZeppelinCatalog.manifest) { ZeppelinDevice() }`.
- The 7 existing devices are converted; the values move unchanged from the registry and `features.json`.
- `CatalogTests` decodes every `device.json`.

### Commands

| Command | Does |
|---|---|
| `hd.py new <id> --kit <Name> --name "<Display name>" --symbol <sf-symbol> --link bluetooth\|wifi --category <category> [--apk <file>]` | Creates `Packages/Sources/<Name>Kit/{Catalog.swift, device.json}` with no features yet, `Packages/Tests/<Name>KitTests/<Name>KitTests.swift`, `App/Devices/<Name>/<Name>Device.swift` (status `.notSetUp`, a screen with `DeviceHeader`), adds the kit and its test target to `Package.swift` and a line to `DeviceRegistry.swift`, and writes `docs/devices/<id>/{journal.md, protocol.md}` from `docs/templates/`. With `--apk`: copies the file into `research/<id>/apk/`, unzips an `.xapk` into its APKs, unzips the base APK, and runs Android build-tools' newest `dexdump -d` on each `classes*.dex` into `classes*.dex.txt`. Refuses if the id or kit already exists. |
| `hd.py phone [--phone <udid>]` | Finds the one connected iPhone (asks to pass `--phone` if several), copies `Config/Team.xcconfig` and `Config/Secrets.xcconfig` from the main checkout when run in a worktree that lacks them, builds, installs and launches. Prints only `error:` lines and the result. Never prints or writes the phone's identifier. |
| `hd.py log <id> [--phone <udid>]` | Copies `Documents/connection-log.jsonl` off the phone to `research/<id>/logs/<timestamp>.jsonl` and prints that device's lines through `mask.py`. |

### The skill text

- When the owner asks for a new device: ask for the display name, category and the vendor's Android app (`.apk` or `.xapk`, or skip), then run `hd.py new`.
- The phone loop section uses `hd.py phone` and `hd.py log` in place of the raw commands.
- APK step: `dexdump` and grep, as before. A note: REA (`morluto/rea`) can decompile APKs instead once its JADX bridge (`jadx-headless-mcp` 0.7.1 JAR, `REA_JADX_MCP_JAR`) is set up; it isn't set up here, and no HomeDeck device used it.
- `docs/adding-a-device.md` and the checklist say `device.json` in place of `features.json`.

### Check

- Package tests pass and the simulator build passes after the conversion.
- In a throwaway worktree: `hd.py new` for a dummy device, then package tests and the simulator build pass; then the worktree is removed.
- `hd.py phone` and `hd.py log walkingpad-c2` run once against the owner's iPhone.

## Part B: nine LinkedIn posts

Files `docs/posts/01-…md` to `09-…md`. Each: 250–400 words, first person in the owner's voice, short paragraphs, no tables, no emojis, three hashtags at the end, one screenshot idea, and a note to put the repo link in the first comment. Source: `docs/article/draft.md`, `docs/journal/hub.md`, `docs/devices/*/{journal,protocol}.md`. No personal data; the privacy scan runs before commit.

| # | Post |
|---|---|
| 1 | Seven vendor apps, one app: the plan, and Claude Code doing the reverse engineering |
| 2 | WalkingPad C2: three tests on the real pad beat eight open-source projects |
| 3 | Mi Scale S400: the scale says its own address out loud |
| 4 | Xiaomi fan: wrong Wi-Fi |
| 5 | Philips purifier: a secret shared by every unit, and a long memory |
| 6 | Zeppelin Pro: a polite liar |
| 7 | Dreame L40: the cloud one, and the map |
| 8 | AENO kettle: where "no account" stopped |
| 9 | How it was done, and the skill that now does it in three commands |

REA is mentioned honestly: the APKs were read with `dexdump` and grep. REA was connected but its Android decompiler wasn't set up, so it is named as the option for the next device (post 9, and briefly in post 1 where the tools are listed).

## Order

Part A first, because post 9 describes the skill. Then the posts. Commit on `phase-0-shell` after the owner's check; `main` and push only on the owner's yes.
