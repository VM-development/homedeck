# Post 4 of 9: Xiaomi standing fan, the wrong Wi-Fi

The fan was supposed to be quick. The Xiaomi Smart Standing Fan 2 Pro speaks miIO: small encrypted UDP packets on the home network, with a token I already had from the scale post.

Nothing answered.

No reply to commands, no reply to the hello packet. And Xiaomi Home on my phone controlled the fan perfectly, which made it look like a protocol problem.

It wasn't. The fan was on a different Wi-Fi network than my phone. Xiaomi Home worked because it goes through Xiaomi's cloud, and the cloud doesn't care which network you're on. That hid the problem completely.

A ping and a broadcast hello from the Mac showed it in a minute. I moved the fan to the phone's Wi-Fi in the vendor app, which gave it a new token and address. After that, every feature worked on the first try: power, speed, modes, oscillation, the light, the buzzer, child lock and the timer. Eight of eight.

One detail from the device itself: Xiaomi's spec says the speed property is read-only. It isn't. Writing it works.

Two bugs came from the app, not the fan. The speed slider snapped back after I let go, because its binding read an old copy of the fan's state. And a late reply arriving after I removed the fan marked it "Offline". Both are now rules in the project's notes.

The fan taught the lesson that repeated most across all seven devices. Before any protocol work, ask: can the phone actually reach this device? Four of the seven needed something before the first command: the right Wi-Fi, the right app or the right password.

Not tested yet: the timer actually switching the fan off, and oscillation angles other than 30 degrees.

#SmartHome #Networking #iOSDevelopment

---
Screenshot: the fan screen with the speed slider and the toggle tiles.
First comment: The code: https://github.com/VM-development/homedeck. An unofficial hobby project, not affiliated with Xiaomi.
