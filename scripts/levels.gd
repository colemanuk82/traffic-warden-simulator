extends RefCounted
## Level definitions. Roads are centre-line polylines on the ground plane (x, z) that run off the
## edge of the map; "bounds" is the part the warden can walk in. Cars drive on the left.
## "paths" are footpaths and alleys (shortcuts between the streets) that only the warden can use.

const LEVELS := [
	{
		"id": "pleasant", "name": "Pleasant Street", "theme": "suburb", "music": "street", "ambience": "birds",
		"blurb": "A long, sunny suburban street. Nice and easy.",
		"roads": [[Vector2(-120, 0), Vector2(120, 0)], [Vector2(-120, -34), Vector2(120, -34)]],
		"paths": [Rect2(-36, -26, 4, 18), Rect2(30, -26, 4, 18), Rect2(-4, -26, 4, 18)],
		"bounds": Rect2(-72, -42, 144, 51), "start": Vector2(0, 5.5),
		"time": 200.0, "quota": 13, "two_star": 2400, "three_star": 3900, "stars_needed": 0,
		"max_cars": 20, "heckle_every": 8.0,
		"sky": Color(0.55, 0.78, 0.95), "ground": Color(0.45, 0.72, 0.35), "sun": Color(1, 0.97, 0.9), "sun_energy": 1.15,
		"ambient": Color(0.75, 0.78, 0.88),
		"weathers": ["clear", "clear", "rain", "wind"],
	},
	{
		"id": "crossroads", "name": "Market Crossroads", "theme": "town", "music": "street", "ambience": "city",
		"blurb": "Four busy roads meet in the town centre.",
		"roads": [[Vector2(-120, 0), Vector2(120, 0)], [Vector2(0, -120), Vector2(0, 120)]],
		"paths": [Rect2(26, 8, 4, 30), Rect2(8, 34, 22, 4), Rect2(-30, -38, 4, 30), Rect2(-30, -38, 22, 4)],
		"bounds": Rect2(-62, -62, 124, 124), "start": Vector2(6, 6),
		"time": 200.0, "quota": 15, "two_star": 2900, "three_star": 4600, "stars_needed": 1,
		"max_cars": 22, "heckle_every": 6.5,
		"sky": Color(0.6, 0.75, 0.9), "ground": Color(0.62, 0.6, 0.58), "sun": Color(1, 0.92, 0.8), "sun_energy": 1.1,
		"ambient": Color(0.78, 0.76, 0.8),
		"weathers": ["clear", "rain", "fog", "storm"],
	},
	{
		"id": "seaside", "name": "Seaside Prom", "theme": "seaside", "music": "seaside", "ambience": "waves",
		"blurb": "The promenade bends up the hill. Watch the seagulls.",
		"roads": [[Vector2(-120, 0), Vector2(26, 0), Vector2(26, -120)]],
		"paths": [Rect2(-10, -42, 4, 34), Rect2(-10, -42, 28, 4)],
		"bounds": Rect2(-75, -72, 111, 81), "start": Vector2(0, 5.5),
		"time": 210.0, "quota": 16, "two_star": 3000, "three_star": 4800, "stars_needed": 3,
		"max_cars": 21, "heckle_every": 6.5,
		"sky": Color(0.5, 0.82, 1.0), "ground": Color(0.95, 0.86, 0.6), "sun": Color(1, 0.96, 0.85), "sun_energy": 1.25,
		"ambient": Color(0.8, 0.82, 0.9),
		"weathers": ["clear", "wind", "rain", "storm"],
	},
	{
		"id": "snow", "name": "Snowy Village", "theme": "snow", "music": "snow", "ambience": "wind",
		"blurb": "A U-shaped lane round the frozen village green.",
		"roads": [[Vector2(-30, 120), Vector2(-30, -26), Vector2(30, -26), Vector2(30, 120)]],
		"paths": [Rect2(-22, -10, 44, 4), Rect2(-2, -18, 4, 8)],
		"bounds": Rect2(-62, -56, 124, 96), "start": Vector2(-24, 0),
		"time": 210.0, "quota": 16, "two_star": 3000, "three_star": 4800, "stars_needed": 6,
		"max_cars": 21, "heckle_every": 6.5,
		"sky": Color(0.75, 0.82, 0.9), "ground": Color(0.95, 0.97, 1.0), "sun": Color(0.9, 0.93, 1.0), "sun_energy": 0.9,
		"ambient": Color(0.8, 0.85, 0.95),
		"weathers": ["snow", "snow", "blizzard", "fog"],
	},
	{
		"id": "city", "name": "Neon City", "theme": "city", "music": "night", "ambience": "city",
		"blurb": "A grid of streets under the neon lights. Busy, busy, busy.",
		"roads": [[Vector2(-120, -19), Vector2(120, -19)], [Vector2(-120, 19), Vector2(120, 19)],
			[Vector2(-19, -120), Vector2(-19, 120)], [Vector2(19, -120), Vector2(19, 120)]],
		"paths": [Rect2(-11, 4, 22, 3), Rect2(4, -11, 3, 22)],
		"bounds": Rect2(-66, -66, 132, 132), "start": Vector2(-13, 13),
		"time": 230.0, "quota": 18, "two_star": 3500, "three_star": 5500, "stars_needed": 9,
		"max_cars": 28, "heckle_every": 4.5,
		"sky": Color(0.06, 0.05, 0.16), "ground": Color(0.16, 0.16, 0.2), "sun": Color(0.55, 0.5, 0.9), "sun_energy": 0.35,
		"ambient": Color(0.35, 0.35, 0.6), "night": true,
		"weathers": ["rain", "clear", "storm", "fog"],
	},
	{
		"id": "posh", "name": "Posh Avenue", "theme": "posh", "music": "posh", "ambience": "birds",
		"blurb": "Mansions, fountains and very important people. Ticket them anyway.",
		"roads": [[Vector2(-120, -20), Vector2(0, -20), Vector2(0, 20), Vector2(120, 20)]],
		"paths": [Rect2(-38, -12, 4, 16), Rect2(-38, 0, 30, 4), Rect2(8, -4, 30, 4), Rect2(34, -4, 4, 16)],
		"bounds": Rect2(-72, -48, 144, 96), "start": Vector2(-6, 0),
		"time": 230.0, "quota": 18, "two_star": 3600, "three_star": 5700, "stars_needed": 12,
		"max_cars": 24, "heckle_every": 5.5,
		"sky": Color(0.98, 0.78, 0.55), "ground": Color(0.4, 0.62, 0.3), "sun": Color(1, 0.8, 0.55), "sun_energy": 1.2,
		"ambient": Color(0.9, 0.75, 0.65),
		"weathers": ["clear", "fog", "wind", "rain"],
	},
	{
		"id": "supermarket", "name": "SuperSave Car Park", "theme": "carpark", "music": "street", "ambience": "city",
		"blurb": "A huge supermarket car park. Trolleys, parent bays and people who park across two spaces.",
		"roads": [[Vector2(-120, -14), Vector2(120, -14)], [Vector2(-120, 16), Vector2(120, 16)],
			[Vector2(-34, -120), Vector2(-34, 120)], [Vector2(34, -120), Vector2(34, 120)]],
		"paths": [Rect2(-26, -6, 52, 4)],
		"open": [Rect2(-34, -14, 68, 30)],
		"bounds": Rect2(-62, -30, 124, 62), "start": Vector2(0, -4),
		"time": 230.0, "quota": 19, "two_star": 3800, "three_star": 5900, "stars_needed": 14,
		"max_cars": 30, "heckle_every": 5.0, "yellow_chance": 0.3,
		"sky": Color(0.62, 0.78, 0.92), "ground": Color(0.32, 0.32, 0.35), "sun": Color(1, 0.96, 0.88), "sun_energy": 1.1,
		"ambient": Color(0.78, 0.8, 0.86),
		"weathers": ["clear", "rain", "wind", "storm"],
	},
	{
		"id": "multistorey", "name": "Multi-Storey", "theme": "multistorey", "music": "metal", "ambience": "city",
		"blurb": "A split-level concrete car park. Up the ramps from Level 2 to the roof, torch in hand.",
		"roads": [[Vector2(-120, -18), Vector2(50, -18), Vector2(50, 18), Vector2(-120, 18)]],
		"paths": [],
		"open": [Rect2(-62, -10, 42, 20), Rect2(-8, -10, 30, 20), Rect2(34, -10, 16, 20)],
		"terrain": {"type": "decks", "knots": [[-20, 0.0], [-8, 3.2], [22, 3.2], [34, 6.4]],
			"names": ["LEVEL 2", "LEVEL 3", "ROOF"]},
		"bounds": Rect2(-62, -30, 120, 60), "start": Vector2(-40, 0),
		"time": 230.0, "quota": 19, "two_star": 3900, "three_star": 6100, "stars_needed": 17,
		"max_cars": 28, "heckle_every": 5.5, "yellow_chance": 0.45, "expired_chance": 0.45,
		"sky": Color(0.05, 0.05, 0.07), "ground": Color(0.42, 0.42, 0.44), "sun": Color(0.7, 0.72, 0.8), "sun_energy": 0.35,
		"ambient": Color(0.4, 0.42, 0.5), "night": true,
		"weathers": ["clear", "clear", "fog"],
	},
	{
		"id": "halloween", "name": "Spooky Hollow", "theme": "halloween", "season": "halloween", "music": "spooky", "ambience": "wind",
		"blurb": "Halloween night. Kids in costumes knock for sweets: hand one over for a treat, or get TRICKED!",
		"roads": [[Vector2(-120, 0), Vector2(120, 0)], [Vector2(-20, 120), Vector2(-20, 30), Vector2(20, 30), Vector2(20, 120)]],
		"paths": [Rect2(-26, 8, 4, 14), Rect2(-2, 8, 4, 14), Rect2(22, 8, 4, 14)],
		"bounds": Rect2(-70, -24, 140, 84), "start": Vector2(-6, 5.5),
		"time": 230.0, "quota": 19, "two_star": 3900, "three_star": 6100, "stars_needed": 6,
		"max_cars": 26, "heckle_every": 5.0, "night": true,
		"sky": Color(0.1, 0.04, 0.18), "ground": Color(0.2, 0.22, 0.13), "sun": Color(0.7, 0.55, 1.0), "sun_energy": 0.4,
		"ambient": Color(0.45, 0.32, 0.6),
		"weathers": ["clear", "fog", "fog", "storm"], "fog_color": Color(0.22, 0.3, 0.24),
		"peds": ["ghost", "witch", "pumpkin", "skeleton", "vampire"], "ped_count": 5, "sweets": 3,
		"special_car": {"kind": "hearse", "chance": 0.12, "bonus": 150},
		"heckle_voice": "hheckle",
		"heckle_lines": ["IT'S HALLOWEEN, GIVE US A BREAK!", "NICE COSTUME! OH WAIT...", "TRICK OR TREAT, JOBSWORTH!",
			"BOO! GET A PROPER JOB!", "YOU'RE SCARIER THAN A GHOST!", "GO HAUNT SOMEONE ELSE!",
			"EVEN ZOMBIES HATE YOU!", "SPOOKY JOBSWORTH!"],
		"driver_shouts": [["It's HALLOWEEN, mate!", "driver_hween"], ["You absolute ghoul!", "driver_ghoul"]],
	},
	{
		"id": "xmas", "name": "Christmas Eve", "theme": "xmas", "season": "xmas", "music": "xmaseve", "ambience": "city",
		"blurb": "Last-minute shoppers park anywhere. Santa flies over dropping presents, and sometimes lands on the yellows!",
		"roads": [[Vector2(-120, 0), Vector2(120, 0)], [Vector2(36, -120), Vector2(36, 120)]],
		"paths": [Rect2(-56, 8, 4, 30), Rect2(-56, 34, 84, 4)],
		"open": [Rect2(-30, -36, 58, 28)],
		"bounds": Rect2(-70, -44, 140, 86), "start": Vector2(-6, -5.5),
		"time": 230.0, "quota": 20, "two_star": 4100, "three_star": 6400, "stars_needed": 9,
		"max_cars": 28, "heckle_every": 4.5, "night": true, "yellow_chance": 0.45,
		"sky": Color(0.06, 0.08, 0.22), "ground": Color(0.93, 0.95, 1.0), "sun": Color(0.7, 0.75, 1.0), "sun_energy": 0.45,
		"ambient": Color(0.45, 0.5, 0.7),
		"weathers": ["snow", "snow", "clear", "clear", "blizzard"],
		"peds": ["drunk", "caroller", "elf"], "ped_count": 4, "flyover": true,
		"special_car": {"kind": "sleigh", "chance": 0.1, "bonus": 250},
		"heckle_voice": "xheckle",
		"heckle_lines": ["COME ON, IT'S CHRISTMAS!", "COME ON MATE, IT'S CHRISTMAS!", "BAH HUMBUG!",
			"YOU'RE ON THE NAUGHTY LIST!", "HAVE A HEART, IT'S CHRISTMAS EVE!", "ALRIGHT, SCROOGE!",
			"SANTA'S WATCHING YOU!", "HO HO NO!", "IT'S CHRISTMAS, YOU GRINCH!", "NO PRESENTS FOR YOU!"],
		"driver_shouts": [["Come on, it's CHRISTMAS!", "driver_xmas"], ["You Grinch!", "driver_grinch"]],
	},
	{
		"id": "hilltop", "name": "Hilltop Village", "theme": "hills", "music": "rock", "ambience": "birds",
		"blurb": "Rolling hills, stone cottages and sheep. The drivers up here think the rules don't apply.",
		"roads": [[Vector2(-120, 2), Vector2(120, 2)], [Vector2(8, 2), Vector2(8, -120)]],
		"paths": [Rect2(-40, -40, 4, 34), Rect2(-40, -40, 40, 4), Rect2(30, -30, 4, 24)],
		"terrain": {"type": "hills", "amp": 4.5, "wave": Vector2(84, 110)},
		"bounds": Rect2(-72, -64, 144, 74), "start": Vector2(14, 7.5),
		"time": 230.0, "quota": 20, "two_star": 4200, "three_star": 6600, "stars_needed": 26,
		"max_cars": 24, "heckle_every": 5.0,
		"sky": Color(0.55, 0.8, 1.0), "ground": Color(0.4, 0.68, 0.3), "sun": Color(1, 0.96, 0.85), "sun_energy": 1.2,
		"ambient": Color(0.78, 0.82, 0.9),
		"weathers": ["clear", "wind", "rain", "fog"],
	},
	{
		"id": "steep", "name": "Steep Street", "theme": "terraces", "music": "rock2", "ambience": "city",
		"blurb": "Painted terraces up a really steep hill. Mind the handbrakes.",
		"roads": [[Vector2(-20, 120), Vector2(-20, -120)], [Vector2(20, -120), Vector2(20, 120)],
			[Vector2(-120, -32), Vector2(120, -32)]],
		"paths": [Rect2(-12, 4, 24, 4), Rect2(-12, -64, 24, 4)],
		"terrain": {"type": "hills", "amp": 0.9, "wave": Vector2(60, 70), "rise": 0.16},
		"bounds": Rect2(-52, -76, 104, 100), "start": Vector2(-16, 6),
		"time": 230.0, "quota": 21, "two_star": 4400, "three_star": 6900, "stars_needed": 29,
		"max_cars": 28, "heckle_every": 4.8,
		"sky": Color(0.6, 0.78, 0.95), "ground": Color(0.5, 0.62, 0.42), "sun": Color(1, 0.94, 0.85), "sun_energy": 1.1,
		"ambient": Color(0.78, 0.8, 0.88),
		"weathers": ["clear", "rain", "wind", "storm"],
	},
]


static func count() -> int:
	return LEVELS.size()


static func get_level(i: int) -> Dictionary:
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]


static func names() -> Dictionary:
	var d := {}
	for l in LEVELS:
		d[l.id] = l.name
	return d


static func index_of(id: String) -> int:
	for i in LEVELS.size():
		if LEVELS[i].id == id:
			return i
	return 0
