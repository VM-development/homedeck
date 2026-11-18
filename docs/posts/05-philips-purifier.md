# Post 5 of 9: Philips purifier, a shared secret and a long memory

The Philips 2000i AC2729 purifies and humidifies. It speaks encrypted CoAP over UDP on the home network.

Its encryption key is derived from one fixed secret that every unit shares, and open source had already published it. So no account is needed at all. HomeDeck keeps that secret out of the public repo: it lives in a git-ignored config file, and the tests use a made-up one.

The first obstacle was familiar from the fan post: the purifier was on another Wi-Fi network. I set it up again in the Philips Air+ app, on the phone's network this time.

Then discovery. The purifier is supposed to answer a multicast request, but on iOS multicast needs a special Apple entitlement. Instead, HomeDeck sweeps the local network with a plain info request to each address and keeps the one that answers like a purifier.

The encryption matched the Android app byte for byte on the first attempt. The hard part was something else: status updates.

The purifier pushes its status to subscribers. During testing we subscribed a few times from changing ports. After that it stopped sending status to anyone, until I unplugged it. It seems to remember subscriptions and never forget them. The fix: subscribe from one fixed port with the same token every time, and cancel when the device is removed.

One more lesson in distrust. Once, six commands in a row were answered "success" and not applied. I couldn't reproduce it. So now every command is preceded by a message-counter sync, as the official app seems to do, and the screen shows the status the purifier pushes, not what we asked for.

And the water tank showed 100 % with the tank removed. The real signal is an error bit, so the screen now says "Empty or out" or "OK" instead of a fake number.

All twelve features of Air+ work, from modes and humidity to filter status and child lock.

#SmartHome #IoT #iOSDevelopment

---
Screenshot: the purifier screen with air quality, humidity and the mode menu.
First comment: The code: https://github.com/VM-development/homedeck. An unofficial hobby project, not affiliated with Philips.
