extends RefCounted
## Daily and weekly challenges. They are picked from the date, so everyone gets the same set each day.
## Daily ones must be done in a single shift; weekly ones add up over every shift that week.

const DAILY_REWARD := {"wages": 150, "xp": 300}
const WEEKLY_REWARD := {"wages": 600, "xp": 1200}

# key: what to read from the shift summary. "min": needs at least n. Special keys are handled in _shift_value.
const DAILY_POOL := [
	{"id": "tickets", "text": "Write %d tickets in one shift", "key": "tickets", "n": [10, 12, 15]},
	{"id": "perfects", "text": "Get %d PERFECT writes in one shift", "key": "perfects", "n": [4, 6, 8]},
	{"id": "nopunch", "text": "Meet the quota without punching anyone", "key": "nopunch", "n": [1]},
	{"id": "punches", "text": "Punch %d drivers in one shift", "key": "punches", "n": [3, 5, 7]},
	{"id": "sports", "text": "Ticket %d sports cars in one shift", "key": "sports_tickets", "n": [2, 3, 4]},
	{"id": "wet", "text": "Write %d tickets in the rain, a storm or snow", "key": "wet_tickets", "n": [5, 8]},
	{"id": "combo", "text": "Hit a x3 combo", "key": "combo3", "n": [1]},
	{"id": "score", "text": "Score %d in one shift", "key": "score", "n": [2500, 3200, 4000]},
	{"id": "clamp", "text": "Clamp %d cars in one shift", "key": "clamps", "n": [2, 3], "rank": 1},
	{"id": "boss", "text": "Beat a boss driver", "key": "bosses", "n": [1]},
	{"id": "pickups", "text": "Grab %d coffees or energy drinks in one shift", "key": "pickups", "n": [2, 3]},
	{"id": "street", "text": "Deal with %d street events in one shift", "key": "street_events", "n": [2, 3]},
	{"id": "nohit", "text": "Meet the quota without getting hit", "key": "nohit", "n": [1]},
	{"id": "dodge", "text": "Dodge %d puddle splashes or pull off close calls", "key": "dodges", "n": [3, 5]},
	{"id": "golden", "text": "Find a Golden Ticket", "key": "collectibles", "n": [1]},
]
const WEEKLY_POOL := [
	{"id": "w_tickets", "text": "Write %d tickets this week", "key": "tickets", "n": [100, 150]},
	{"id": "w_punches", "text": "Punch %d drivers this week", "key": "punches", "n": [25, 40]},
	{"id": "w_stars", "text": "Earn %d stars this week", "key": "stars", "n": [10, 15]},
	{"id": "w_bosses", "text": "Beat %d boss drivers this week", "key": "bosses", "n": [3, 5]},
	{"id": "w_perfects", "text": "Get %d PERFECT writes this week", "key": "perfects", "n": [30, 50]},
	{"id": "w_street", "text": "Deal with %d street events this week", "key": "street_events", "n": [8, 12]},
	{"id": "w_shifts", "text": "Work %d shifts this week", "key": "shifts", "n": [10, 15]},
	{"id": "w_heckles", "text": "Get heckled %d times this week", "key": "heckles", "n": [60, 100]},
	{"id": "w_wave", "text": "Reach wave %d in Endless mode", "key": "wave", "n": [5, 7], "max": true},
]


static func day_index() -> int:
	return int(Time.get_unix_time_from_system() / 86400.0)


static func day_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


static func week_key() -> String:
	# Weeks start on Monday (1 Jan 1970 was a Thursday)
	return "W%d" % int((day_index() + 3) / 7)


static func _pick(pool: Array, count: int, key: String, rank: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var options := []
	for c in pool:
		if int(c.get("rank", 0)) <= rank:
			options.append(c)
	var out := []
	while out.size() < count and not options.is_empty():
		var c: Dictionary = options.pop_at(rng.randi() % options.size())
		var n: int = c.n[rng.randi() % c.n.size()]
		out.append({"id": c.id, "text": c.text % n if c.text.contains("%d") else c.text, "key": c.key, "n": n,
			"max": c.get("max", false)})
	return out


static func daily(rank: int) -> Array:
	return _pick(DAILY_POOL, 3, "day" + day_key(), rank)


static func weekly() -> Array:
	return _pick(WEEKLY_POOL, 3, "week" + week_key(), 0)


static func shift_value(c: Dictionary, r: Dictionary) -> int:
	match c.key:
		"nopunch":
			return 1 if r.get("passed", false) and int(r.get("punches", 0)) == 0 else 0
		"nohit":
			return 1 if r.get("passed", false) and int(r.get("hit", 0)) == 0 else 0
		"combo3":
			return 1 if float(r.get("best_combo", 1.0)) >= 3.0 else 0
		"shifts":
			return 1
	return int(r.get(c.key, 0))
