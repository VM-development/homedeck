# Post 6 of 10: Zeppelin Pro, a polite liar

The Bowers & Wilkins Zeppelin Pro needed no account and no cloud. It has a local JSON API over HTTPS, a WebSocket that pushes changes, and it announces itself on the network with Bonjour.

Nice on paper. Every one of those had a catch.

Bonjour advertises a port, but the API isn't on it. It was on a different port, found by probing.

The first phone build crashed. The address Bonjour handed over carried an interface suffix, "%en0", and building a URL from it failed. Now the address is built from its raw bytes, and the code has no force-unwraps on that path.

The speaker uses a self-signed certificate, so HomeDeck pins it on first use and refuses anything else after that.

Then the volume slider jumped back and forth. Here is why: when you change the volume, the speaker answers "success" and, in the same reply, reports the old volume. A separate push brings the new value a moment later. The app believed the reply. Now it trusts only the change event.

The speaker also ignores the "muted" flag in its own API. So in HomeDeck, mute is volume 0, and unmute restores the previous level.

Auto standby wasn't in that API at all. It lives in a second, plain-HTTP settings service on another port.

This device also caught me. I reported the speaker's features as tested. Claude went through them one by one with the log open and asked "did you try this?". Three of them had no trace in the log: I hadn't actually tried them. We tested them properly before marking anything working.

Seven of seven features work. Installing a firmware update isn't tested, because none was available.

#SmartHome #APIs #iOSDevelopment

---
Screenshot: the speaker screen with now playing, volume and the light controls.
First comment: The code: https://github.com/VM-development/homedeck. An unofficial hobby project, not affiliated with Bowers & Wilkins.
