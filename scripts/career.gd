extends RefCounted
## Career data: ranks and their gadgets, Depot upgrades, weapons, special event shifts and boss drivers.

const RANKS := [
	{"name": "Trainee Warden", "xp": 0, "perk": "Your notepad and your fists"},
	{"name": "Warden", "xp": 1500, "perk": "Wheel CLAMP: clamp a bad parker on the spot"},
	{"name": "Senior Warden", "xp": 5000, "perk": "TOW TRUCK: call a truck to drag a car away"},
	{"name": "Sergeant Warden", "xp": 10000, "perk": "CAMERA VAN: a van that tickets cars near it"},
	{"name": "Inspector", "xp": 18000, "perk": "+1 use of every gadget, and the Inspector's Cap"},
	{"name": "Chief Parking Enforcer", "xp": 30000, "perk": "The Chief's uniform. The streets fear you."},
]

# Gadgets: [id, name, rank needed, uses per shift]
const GADGETS := [
	{"id": "clamp", "name": "Wheel Clamp", "rank": 1, "uses": 3, "points": 150},
	{"id": "tow", "name": "Tow Truck", "rank": 2, "uses": 1, "points": 250},
	{"id": "camera", "name": "Camera Van", "rank": 3, "uses": 1, "points": 80},
]

# Depot upgrades: cost per level
const UPGRADES := [
	{"id": "shoes", "name": "Turbo Shoes", "desc": "Walk and sprint 7% faster per level", "costs": [250, 600, 1200]},
	{"id": "book", "name": "Bigger Ticket Book", "desc": "Bigger green zone and quicker writing", "costs": [300, 700, 1400]},
	{"id": "megaphone", "name": "Megaphone", "desc": "Whistle reaches further and freezes drivers for longer", "costs": [250, 550, 1100]},
	{"id": "flask", "name": "Tea Flask", "desc": "More stamina for sprinting", "costs": [200, 450, 900]},
	{"id": "belt", "name": "Gadget Belt", "desc": "+1 use of every gadget per shift", "costs": [800, 1800]},
	{"id": "bike", "name": "Council Bike", "desc": "Sprint on a bike: much faster, half the stamina", "costs": [1500]},
]

# Melee weapons. knock = how far drivers fly; special effects are handled in main.gd
const WEAPONS := [
	{"id": "fists", "name": "Bare Fists", "cost": 0, "range": 1.9, "knock": 14.0, "cooldown": 0.45,
		"desc": "Old faithful.", "words": ["POW!", "BIFF!", "WALLOP!", "KAPOW!", "THWACK!"]},
	{"id": "newspaper", "name": "Rolled-up Newspaper", "cost": 300, "range": 2.0, "knock": 10.0, "cooldown": 0.25,
		"desc": "Quick little swats.", "words": ["SWAT!", "THWAP!", "BAD!", "SHOO!"]},
	{"id": "printer", "name": "Ticket Printer", "cost": 600, "range": 2.1, "knock": 16.0, "cooldown": 0.55,
		"desc": "Every hit on an angry driver prints them a fine (+75).", "words": ["PRINTED!", "BZZT-CLUNK!", "FINED!"]},
	{"id": "walkie", "name": "Walkie-Talkie", "cost": 900, "range": 2.0, "knock": 14.0, "cooldown": 0.5,
		"desc": "Calls for BACKUP: hits freeze every driver nearby.", "words": ["KSSHHH!", "OVER!", "10-4!", "COPY THAT!"]},
	{"id": "brolly", "name": "Brolly", "cost": 900, "range": 2.7, "knock": 13.0, "cooldown": 0.5,
		"desc": "Long reach, and blocks splashes from puddles.", "words": ["THWOCK!", "POKE!", "BROLLY'D!"]},
	{"id": "fish", "name": "Wet Fish", "cost": 1100, "range": 2.2, "knock": 20.0, "cooldown": 0.6,
		"desc": "A proper seaside slap. Drivers fly miles.", "words": ["SLAP!", "SPLOT!", "FISHED!", "COD!"]},
	{"id": "cone", "name": "Traffic Cone", "cost": 1500, "range": 2.4, "knock": 24.0, "cooldown": 0.75,
		"desc": "Slow, heavy and hilarious.", "words": ["BONG!", "CONED!", "DOINK!", "KER-BONG!"]},
]

# Rampage mode's baseball bat (not for sale: floor three drivers in a row to get it for a while)
const BAT := {"id": "bat", "name": "Baseball Bat", "cost": 0, "range": 2.6, "knock": 30.0, "cooldown": 0.32,
	"desc": "RAMPAGE!", "words": ["HOME RUN!", "BONK!", "KER-THWACK!", "BATTER UP!", "OUT OF THE PARK!"]}

# Special event shifts: a base level plus overrides (see main.gd / world.gd for the keys)
const EVENTS := [
	{"id": "ev_binstrike", "name": "Bin Strike", "base": "pleasant", "stars_needed": 3,
		"blurb": "The bins haven't been emptied for weeks. Rubbish bags slow you down and nobody parks properly.",
		"overrides": {"quota": 15, "yellow_chance": 0.6, "expired_chance": 0.55, "deco": "bins", "time": 180.0,
			"ambience": "city", "weathers": ["clear", "wind"]}},
	{"id": "ev_wedding", "name": "Wedding Day", "base": "posh", "stars_needed": 5,
		"blurb": "A big posh wedding. Wedding cars park anywhere. Ticket them for +200, but the guests get VERY angry.",
		"overrides": {"quota": 13, "deco": "wedding", "special_car": {"kind": "wedding", "chance": 0.4, "bonus": 200},
			"chase_bonus": 0.3, "weathers": ["clear", "clear", "wind"]}},
	{"id": "ev_matchday", "name": "Match Day", "base": "crossroads", "stars_needed": 8,
		"blurb": "The big match is on. Twice the traffic, twice the heckling, and fans parked everywhere.",
		"overrides": {"quota": 20, "max_cars": 24, "heckle_every": 3.5, "deco": "football", "yellow_chance": 0.5,
			"time": 200.0, "special_car": {"kind": "fan", "chance": 0.35, "bonus": 50}, "weathers": ["clear", "rain", "storm"]}},
	{"id": "ev_xmas", "name": "Christmas Market", "base": "snow", "stars_needed": 11,
		"blurb": "Late night Christmas shopping in the snow. Bring your torch, and watch out for Santa's sleigh.",
		"overrides": {"quota": 15, "deco": "xmas", "night": true, "sky": Color(0.05, 0.06, 0.16), "sun_energy": 0.3,
			"sun": Color(0.6, 0.65, 0.95), "ambient": Color(0.35, 0.4, 0.6), "music": "snow",
			"special_car": {"kind": "sleigh", "chance": 0.25, "bonus": 250}, "weathers": ["snow", "snow", "blizzard"]}},
]

const BOSSES := [
	{"id": "mayor", "name": "THE LORD MAYOR", "hp": 3, "bonus": 600, "kind": "limo", "voice": "boss_mayor",
		"intro": "The Lord Mayor's limo is on the double yellows!\nHis bodyguards won't like this...",
		"line": "Do you know who I am?!"},
	{"id": "vanman", "name": "WHITE VAN MAN", "hp": 2, "bonus": 450, "kind": "whitevan", "voice": "boss_vanman",
		"intro": "White Van Man is parking wherever he likes!\nHe moves on every few seconds. Catch him!",
		"line": "Leave it out, mate!"},
	{"id": "getaway", "name": "THE GETAWAY CAR", "hp": 2, "bonus": 500, "kind": "getaway", "voice": "boss_getaway",
		"intro": "A getaway car is idling on the yellows!\nDon't sprint near it or it'll bolt.",
		"line": "You'll never catch me!"},
]


static func rank_for(xp: int) -> int:
	var r := 0
	for i in RANKS.size():
		if xp >= int(RANKS[i].xp):
			r = i
	return r


static func upgrade(id: String) -> Dictionary:
	for u in UPGRADES:
		if u.id == id:
			return u
	return {}


static func weapon(id: String) -> Dictionary:
	for w in WEAPONS:
		if w.id == id:
			return w
	return WEAPONS[0]


static func event(id: String) -> Dictionary:
	for e in EVENTS:
		if e.id == id:
			return e
	return {}


static func boss(id: String) -> Dictionary:
	for b in BOSSES:
		if b.id == id:
			return b
	return BOSSES[0]
