# Post 9 of 9: How it was done, and the tool that does it now

Seven devices in, here is what made the work hold together, and what I automated at the end.

Research before code. Open source first, the vendor's Android app only for the gaps. Apps were unpacked and read with Android's dexdump and text search, never installed or run. REA, an MCP server for reverse engineering, would decompile them into readable code; I had it connected but not set up for Android, and dexdump was enough. Next time I'll try it.

One device at a time. The plan said four parallel sessions. I switched to one device at a time, each in its own git branch and worktree, merged only on my yes. Half of the preparation list disappeared, because it existed only to stop parallel sessions from editing the same lines.

Every feature on the real device. The app logs every exchange, tagged by device. The log decides what is marked working, not my memory of the test. That caught me more than once.

Evidence labels. Every claim in a device's protocol notes says where it came from: verified on device, from the APK, from open source, or a guess. Several research claims didn't survive the real device.

Privacy before the first line of app code. The repo is public. A git-ignored list holds my real values: network names, addresses, tokens, keys. A scan searches every file for each of them, as text, hex and base64, before every push.

Journals. Each device has an append-only journal, dead ends included. Its "article note" lines became this series.

What I automated: the steps I repeated for every device are now one Claude Code skill with three commands. "new" asks for the vendor's Android app, then creates the device's package, tests, screen, catalog entry and notes, and unpacks and dumps the app. "phone" builds, installs and launches on my iPhone. "log" pulls the connection log and shows one device's lines with private values masked.

Every device is now described by one file in one format. The next device starts with three commands.

#ClaudeCode #iOSDevelopment #ReverseEngineering

---
Screenshot: the Market tab, every device with its "working" count.
First comment: The code and the skill: https://github.com/VM-development/homedeck. Thanks to the open-source work it stands on: ph4-walkingpad, xiaomi-ble, python-miio, Xiaomi Cloud Tokens Extractor, aioairctrl, space192/zeppelin, Tasshack's dreame-vacuum and tinytuya.
