# Post 2 of 9: WalkingPad C2, where the log beat open source

The first device was my walking pad, a WalkingPad C2.

This was the easy start: eight open-source projects already describe its Bluetooth protocol. But they disagree, and they describe other models. After reading all of them, Claude listed ten open questions about this exact model.

Three short tests on the real pad closed six of them.

The C2 needs no handshake before it accepts commands. It has no standard fitness (FTMS) Bluetooth service, so apps that only speak FTMS will never see it. Its belt reports state 4 for standby, which no project documented.

And one answer changed the design. The protocol has a command that should return stored walks. Three tries, three answers of all zeros. The pad keeps nothing for apps. So HomeDeck records walks itself: the pad's counters at stop minus its counters at start, saved on the phone.

The app polls the pad every 0.75 seconds, and it kept going with the phone locked in my pocket.

The test also taught me something about testing. I ticked features as working while walking. Then we compared my ticks with the app's connection log, and they disagreed twice. A 12-second walk can't show distance, because the pad counts distance in 10-metre steps. And one walk had been saved but I hadn't ticked it.

From then on, the rule for every device: the log decides what works, not my memory of the test.

All five features of the pad's app work: start and stop, speed, modes, live stats and walk history.

#Bluetooth #ReverseEngineering #iOSDevelopment

---
Screenshot: the WalkingPad screen during a walk (speed, time, distance).
First comment: The code: https://github.com/VM-development/homedeck. An unofficial hobby project, not affiliated with KingSmith.
