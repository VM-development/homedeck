# Post 8 of 10: AENO kettle, where "no account" stopped

Not every device ends with "it works". The kettle, an AENO EK7S, is paused, and I think that is worth a post too.

The AENO app is a white-label Tuya app. Most of it is Tuya's SDK, and the kettle's own screen isn't in the app at all: it is downloaded from Tuya's cloud at runtime. So unpacking the Android app told us almost nothing about the kettle.

Next, the network. Tuya Wi-Fi devices usually broadcast and have a known local port. We found no broadcast and no open port. The kettle seems to use Bluetooth instead. That is my report from the app, not confirmed with a scan.

Tuya's Bluetooth protocol is documented in open source. But it needs three values from Tuya's cloud, including the device's local key. There were three ways to get them:

Re-add the kettle in Tuya's own Smart Life app, which works with open-source extractors. That means giving up the AENO app.

Use the AENO app's own cloud keys from inside the app. Those are the vendor's private secrets, and the project's rule is to use only constants already published in open source. So no.

Dig the values out of a full iPhone backup. Possible, but more than I wanted for a kettle.

I want to keep the AENO app, and I declined the backup. So the kettle stops here, with its six features listed as planned.

Stopping well is part of the method. The kettle's journal keeps every dead end, the README says "Paused", and the notes say exactly what would restart it.

It also showed where the project's first rule ends. "Local control first, the cloud only once for a key" works until the key is held by a cloud with no published way in.

#SmartHome #IoT #Privacy

---
Screenshot: the Market entry for the kettle, 0 of 6 features working.
First comment: The code: https://github.com/VM-development/homedeck. An unofficial hobby project, not affiliated with AENO or Tuya.
