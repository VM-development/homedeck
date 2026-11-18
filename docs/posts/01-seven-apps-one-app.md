# Post 1 of 10: Seven vendor apps, one app

My phone had a separate app for almost every device at home: a walking pad, a scale, a standing fan, an air purifier, a speaker, a robot vacuum and a kettle. Seven apps, seven accounts, seven ways to do the same thing.

So I built HomeDeck: one iPhone app with one module per device. Every module was reverse engineered and tested on the real device. Claude Code did most of the reverse engineering and the typing. I did the walking, the weighing and the unplugging.

The rules I set on day one:

Local control first. A vendor's cloud is allowed only where it is the only way in, and ideally only once, to fetch a device's key.

Each device gets its own Swift package for its protocol code, tested on the Mac without the phone.

Each device is described by one file: its name, icon, how it connects, its category and every feature its vendor app has, marked working or planned. The app's Market tab reads those files and shows how many features actually work.

Day one was the plan, the app shell and the research. Building and testing six devices took two more days. Six work. The kettle is paused, and that story gets its own post.

How the reverse engineering worked: open-source projects first, then the vendor's Android app only for the gaps. The apps were unpacked and read with Android's own dexdump tool and plain text search, never installed or run. I also had REA, an MCP server for reverse engineering, connected to Claude, but never set up its Android decompiler: dexdump and grep were enough for these seven.

Over the next posts: one post per device, what it turned out to speak and what surprised me. Then a last post on how the work was organised, and the tool that now does the repetitive part.

#iOSDevelopment #ReverseEngineering #ClaudeCode

---
Screenshot: the Home tab, devices grouped by category (no device or room names visible).
First comment: The code: https://github.com/VM-development/homedeck. An unofficial hobby project, not affiliated with any of the device makers.
