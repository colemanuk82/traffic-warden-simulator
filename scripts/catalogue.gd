extends RefCounted
## Every customisation item, and what it takes to unlock it.
## "req" is [stat, amount]. Stats: stars, tickets, punches, perfects, heckles, shifts, close_calls,
## or "level" with a level id (finish that level with at least one star).
## Career stats too: rank, bosses, collectibles, street_events, clamps.

const SLOTS := ["type", "skin", "hair", "hair_color", "uniform", "vest", "hat", "accessory"]
const SLOT_NAMES := {
	"type": "Character", "skin": "Skin tone", "hair": "Haircut", "hair_color": "Hair colour",
	"uniform": "Uniform", "vest": "Vest", "hat": "Hat", "accessory": "Accessory",
}

const ITEMS := {
	"type": [
		{"id": "classic", "name": "Classic Warden"},
		{"id": "big", "name": "Big Lad", "req": ["tickets", 15]},
		{"id": "beanpole", "name": "Beanpole", "req": ["stars", 2]},
		{"id": "shorty", "name": "Shorty", "req": ["shifts", 3]},
		{"id": "granny", "name": "Granny Warden", "req": ["perfects", 15]},
		{"id": "robot", "name": "Robo-Warden 3000", "req": ["stars", 10]},
		{"id": "alien", "name": "Space Warden", "req": ["stars", 15]},
	],
	"skin": [
		{"id": "s1", "name": "Rosy", "color": Color(1.0, 0.82, 0.72)},
		{"id": "s2", "name": "Peach", "color": Color(0.98, 0.76, 0.6)},
		{"id": "s3", "name": "Tan", "color": Color(0.86, 0.62, 0.45)},
		{"id": "s4", "name": "Olive", "color": Color(0.75, 0.56, 0.38)},
		{"id": "s5", "name": "Brown", "color": Color(0.55, 0.36, 0.24)},
		{"id": "s6", "name": "Deep", "color": Color(0.36, 0.23, 0.16)},
	],
	"hair": [
		{"id": "short", "name": "Short Back & Sides"},
		{"id": "bald", "name": "Shiny Bald"},
		{"id": "spiky", "name": "Spiky"},
		{"id": "afro", "name": "Afro"},
		{"id": "ponytail", "name": "Ponytail"},
		{"id": "bun", "name": "Top Bun"},
		{"id": "long", "name": "Long & Flowing"},
		{"id": "mohawk", "name": "Mohawk", "req": ["punches", 5]},
		{"id": "mullet", "name": "Mullet", "req": ["heckles", 20]},
		{"id": "quiff", "name": "Big Quiff", "req": ["tickets", 40]},
		{"id": "combover", "name": "Comb-Over", "req": ["shifts", 8]},
	],
	"hair_color": [
		{"id": "brown", "name": "Brown", "color": Color(0.4, 0.25, 0.13)},
		{"id": "black", "name": "Black", "color": Color(0.1, 0.09, 0.1)},
		{"id": "blonde", "name": "Blonde", "color": Color(0.98, 0.84, 0.45)},
		{"id": "ginger", "name": "Ginger", "color": Color(0.9, 0.45, 0.15)},
		{"id": "grey", "name": "Silver", "color": Color(0.78, 0.78, 0.8)},
		{"id": "pink", "name": "Bubblegum", "color": Color(1.0, 0.45, 0.75), "req": ["stars", 6]},
		{"id": "blue", "name": "Electric Blue", "color": Color(0.25, 0.55, 1.0), "req": ["close_calls", 10]},
		{"id": "green", "name": "Toxic Green", "color": Color(0.4, 0.95, 0.3), "req": ["punches", 25]},
		{"id": "gold", "name": "Golden", "color": Color(1.0, 0.78, 0.15), "req": ["collectibles", 6]},
	],
	"uniform": [
		{"id": "hivis", "name": "Hi-Vis Yellow", "jacket": Color(0.9, 0.95, 0.15), "trousers": Color(0.12, 0.13, 0.2), "stripe": Color(0.85, 0.85, 0.9)},
		{"id": "orange", "name": "Hi-Vis Orange", "jacket": Color(1.0, 0.5, 0.1), "trousers": Color(0.15, 0.15, 0.2), "stripe": Color(0.85, 0.85, 0.9)},
		{"id": "navy", "name": "Classic Navy", "jacket": Color(0.12, 0.16, 0.35), "trousers": Color(0.1, 0.1, 0.15), "stripe": Color(0.95, 0.8, 0.15)},
		{"id": "council", "name": "Council Green", "jacket": Color(0.2, 0.5, 0.3), "trousers": Color(0.15, 0.2, 0.15), "stripe": Color(0.95, 0.95, 0.6), "req": ["shifts", 2]},
		{"id": "pink", "name": "Pink Power", "jacket": Color(1.0, 0.5, 0.75), "trousers": Color(0.95, 0.95, 0.95), "stripe": Color(1, 1, 1), "req": ["stars", 4]},
		{"id": "camo", "name": "Combat Camo", "jacket": Color(0.35, 0.42, 0.25), "trousers": Color(0.3, 0.28, 0.2), "stripe": Color(0.2, 0.25, 0.15), "req": ["punches", 15]},
		{"id": "tux", "name": "Tuxedo", "jacket": Color(0.08, 0.08, 0.1), "trousers": Color(0.08, 0.08, 0.1), "stripe": Color(1, 1, 1), "req": ["level", "posh"]},
		{"id": "gold", "name": "Solid Gold", "jacket": Color(1.0, 0.8, 0.2), "trousers": Color(0.9, 0.7, 0.15), "stripe": Color(1, 1, 0.8), "req": ["stars", 18]},
		{"id": "chief", "name": "Chief's Uniform", "jacket": Color(0.08, 0.1, 0.22), "trousers": Color(0.06, 0.06, 0.1), "stripe": Color(1.0, 0.8, 0.2), "req": ["rank", 5]},
		{"id": "ticket", "name": "Golden Ticket Suit", "jacket": Color(1.0, 0.9, 0.35), "trousers": Color(0.95, 0.75, 0.2), "stripe": Color(0.9, 0.2, 0.2), "req": ["collectibles", 15]},
	],
	"vest": [
		{"id": "none", "name": "No Vest"},
		{"id": "utility", "name": "Utility Vest"},
		{"id": "tool", "name": "Tool Vest", "req": ["tickets", 30]},
		{"id": "radio", "name": "Radio Vest", "req": ["rank", 1]},
		{"id": "stab", "name": "Stab Vest", "req": ["punches", 20]},
		{"id": "tactical", "name": "Tactical Vest", "req": ["bosses", 3]},
		{"id": "fishing", "name": "Fishing Vest", "req": ["level", "seaside"]},
		{"id": "medal", "name": "Medal Sash", "req": ["street_events", 10]},
	],
	"hat": [
		{"id": "cap", "name": "Peaked Cap"},
		{"id": "none", "name": "No Hat"},
		{"id": "baseball", "name": "Baseball Cap"},
		{"id": "baseball_back", "name": "Backwards Cap", "req": ["shifts", 4]},
		{"id": "inspector", "name": "Inspector's Cap", "req": ["rank", 4]},
		{"id": "bobble", "name": "Bobble Hat", "req": ["level", "snow"]},
		{"id": "hardhat", "name": "Hard Hat", "req": ["tickets", 25]},
		{"id": "tophat", "name": "Top Hat", "req": ["stars", 8]},
		{"id": "cone", "name": "Traffic Cone", "req": ["heckles", 40]},
		{"id": "helmet", "name": "Bobby Helmet", "req": ["tickets", 80]},
		{"id": "crown", "name": "Royal Crown", "req": ["stars", 16]},
	],
	"accessory": [
		{"id": "none", "name": "Nothing"},
		{"id": "tache", "name": "Moustache"},
		{"id": "shades", "name": "Cool Shades", "req": ["stars", 1]},
		{"id": "beard", "name": "Big Beard", "req": ["shifts", 5]},
		{"id": "bowtie", "name": "Bow Tie", "req": ["perfects", 10]},
		{"id": "gloves", "name": "Boxing Gloves", "req": ["punches", 10]},
		{"id": "headphones", "name": "Headphones", "req": ["level", "city"]},
		{"id": "parrot", "name": "Pet Parrot", "req": ["level", "seaside"]},
		{"id": "scarf", "name": "Woolly Scarf", "req": ["level", "snow"]},
		{"id": "cape", "name": "Super Cape", "req": ["close_calls", 15]},
		{"id": "pigeon", "name": "Pet Pigeon", "req": ["street_events", 5]},
		{"id": "lanyard", "name": "Golden Lanyard", "req": ["collectibles", 10]},
	],
}

const STAT_WORDS := {
	"stars": "Earn %d stars", "tickets": "Write %d tickets", "punches": "Punch %d drivers",
	"perfects": "Get %d PERFECT writes", "heckles": "Get heckled %d times", "shifts": "Finish %d shifts",
	"close_calls": "Pull off %d close calls", "bosses": "Beat %d boss drivers", "collectibles": "Find %d Golden Tickets",
	"street_events": "Survive %d street events", "clamps": "Clamp %d cars", "pickups": "Grab %d coffees or energy drinks",
}
const RANK_WORDS := ["Trainee", "Warden", "Senior Warden", "Sergeant Warden", "Inspector", "Chief Parking Enforcer"]


static func items(slot: String) -> Array:
	return ITEMS[slot]


static func find(slot: String, id: String) -> Dictionary:
	for it in ITEMS[slot]:
		if it.id == id:
			return it
	return ITEMS[slot][0]


static func req_text(item: Dictionary, level_names: Dictionary) -> String:
	if not item.has("req"):
		return "Unlocked from the start"
	var r: Array = item.req
	if r[0] == "level":
		return "Finish %s" % level_names.get(r[1], r[1])
	if r[0] == "rank":
		return "Reach the rank of %s" % RANK_WORDS[int(r[1])]
	return STAT_WORDS[r[0]] % r[1]
