# Post 10 of 10: A proposal to device makers

Building HomeDeck meant learning how seven devices talk. It also showed how they keep strangers out. Mostly, they don't.

My walking pad has no pairing and no key. Any phone in Bluetooth range can start the belt. My speaker answers anyone on the Wi-Fi. My purifier encrypts its messages, but with one secret that every unit shares, and that secret is published in open-source code.

The other four fail the opposite way. The fan, the scale and the kettle each have their own key, but I can only get it from the maker's cloud, with unofficial tools. The robot vacuum works only through the maker's cloud.

Open to everyone, or closed to the owner. One design fixes both: a key unique to each unit, which the owner gets from the device itself and nobody else has.

So I wrote a proposal, with Claude Code. It has two parts.

The first is a format, Open Local Control. One JSON file per model, published next to the manual, describes every Bluetooth characteristic or network message down to the byte and the checksum. That's precise enough to build an app from.

The second is a security level that every file must state: open, shared secret, per-device key, or owner key. Owner key means a setup code on the label or display, proper pairing, a separate credential for each app the owner allows, authenticated encryption, local control with no internet, and a button press on the device before risky actions like starting a treadmill belt.

A small checker reads a file, works out its level and lists what's missing. For my walking pad as it is today, it lists eleven gaps.

This isn't only my wish list. ETSI EN 303 645, the UK's PSTI rules and the EU's Cyber Resilience Act already push the same way, and the CRA's main obligations apply from December 2027. Where Matter fits, use Matter: it already does most of this. The format is for everything it doesn't cover.

If you build devices, I'd value your view: what would stop you from publishing a file like this?

#IoTSecurity #SmartHome #Bluetooth

---
Screenshot: the checker's output for the walking pad: "level open" and its list of gaps.
First comment: The proposal, the format and the checker: https://github.com/VM-development/homedeck/tree/main/docs/manufacturers. An unofficial hobby project, not affiliated with any maker named.
