# Post 7 of 9: Dreame L40, the cloud one

I expected the robot vacuum, a Dreame L40 Ultra, to be the hardest device. It was the easiest one to drive, and the hardest one to draw.

Robots bound to the Dreamehome app switch their local API off. So this is the one device where HomeDeck signs in to a vendor cloud. It is the only vendor account in the app, and only the session tokens are stored, in the iPhone Keychain, never my password. My account used Google sign-in, so I first had to set a password in the Dreame app.

For the gaps I gave Claude the Dreamehome Android app as an .xapk file. The open-source client for these robots (Tasshack's dreame-vacuum) uses fixed app constants, and they were still in the current Android app. The robot's value table answered the first probe almost completely: 47 of 55 candidate values.

The map was the hard part. The value that should name the map file doesn't answer, and the old download endpoint is gone from the app. What works: a map request action returns a file name, a short-lived link gives the file, and the file is AES-encrypted and zlib-compressed.

The rooms weren't in that map at all. The live map carries a second, older-format saved map inside it, and the room data lives there.

The rooms also have no names. A list of "Room 1, Room 2" is useless when you can't tell which is the kitchen. So the map itself became the room picker: each room has a number and a colour on the map, and you tap the rooms to clean.

Getting the map the right way round took two tries. It is the raw image mirrored left to right.

Nine of eleven features work. Mop water level waits for a new water tank (mine is broken), and schedules aren't decoded yet.

#ReverseEngineering #SmartHome #iOSDevelopment

---
Screenshot: the robot screen with the coloured, numbered room map.
First comment: The code: https://github.com/VM-development/homedeck. An unofficial hobby project, not affiliated with Dreame.
