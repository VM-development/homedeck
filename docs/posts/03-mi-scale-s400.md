# Post 3 of 10: Mi Scale S400, the scale that says its address out loud

My scale, a Mi Body Composition Scale S400, never connects to anything. Each weigh-in is broadcast as Bluetooth advertisements, and the measurement frames are encrypted.

To decrypt them you need two things. A 16-byte key that lives in Xiaomi's cloud. And the scale's MAC address, because it is part of the encryption nonce.

The key was a one-time job: I ran the open-source Xiaomi Cloud Tokens Extractor on my Mac. The same run also gave me the standing fan's token, so the shared Xiaomi sign-in module in my plan was never needed.

The MAC was the real puzzle. iOS doesn't show apps the MAC addresses of Bluetooth devices, and the encrypted measurement frames don't carry it. How does an iPhone get an address it can't see?

The answer turned out to be simple: when someone steps on, the scale's first frame is unencrypted and includes its own MAC. The scale says its address out loud. HomeDeck learns it from that frame.

One more gap: Apple's CryptoKit has no AES-CCM, the mode the scale uses. So HomeDeck builds it on CommonCrypto's AES block function, checked against published test vectors.

Weigh-ins go to Apple Health. Later I added profiles, so a few people can use one scale.

A privacy note. At one point I pasted the extractor's whole output, keys and tokens included, into the chat. Nothing went into the repo. The values went into a git-ignored list that the privacy scan checks before every push, so a commit containing any of them is refused.

Not tested yet: a weigh-in with the phone locked, and HomeDeck's body composition, an estimate from published equations, against Xiaomi's own numbers.

#Bluetooth #Privacy #iOSDevelopment

---
Screenshot: the scale screen with a weigh-in and the profile picker (no real names).
First comment: The code: https://github.com/VM-development/homedeck. An unofficial hobby project, not affiliated with Xiaomi.
