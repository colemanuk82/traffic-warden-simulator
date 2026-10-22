extends Node3D
## Traffic Warden Sim: runs one shift. Game.mode picks what kind:
## career (a level), event (a special event shift), endless (waves until you miss the quota),
## coop (two players, one shared quota) or race (two players, most tickets wins).

const Levels := preload("res://scripts/levels.gd")
const Career := preload("res://scripts/career.gd")
const Util := preload("res://scripts/util.gd")
const WorldScript := preload("res://scripts/world.gd")
const WardenScript := preload("res://scripts/warden.gd")
const CarScript := preload("res://scripts/car.gd")
const DriverScript := preload("res://scripts/driver.gd")
const PedestrianScript := preload("res://scripts/pedestrian.gd")
const StreetEventScript := preload("res://scripts/street_event.gd")
const HudScript := preload("res://scripts/hud.gd")
const PauseScript := preload("res://scripts/pause_handler.gd")
const WeatherScript := preload("res://scripts/weather.gd")

# Scoring rules (from the design doc)
const BASE_POINTS := 100
const PERFECT_BONUS := 50
const WRONG_PENALTY := 150
const HIT_PENALTY := 50
const CLOSE_CALL_BONUS := 25
const PUNCH_BONUS := 50
const PRINTER_BONUS := 75
const SPLASH_PENALTY := 20
const COMBO_WINDOW := 10.0
const COMBO_STEPS := [1.0, 1.5, 2.0, 3.0]
const CHASE_CHANCE := 0.4
const STUN_TIME := 3.0
const CLAMP_TIME := 25.0
const CAMERA_VAN_TIME := 25.0
const CAMERA_VAN_RANGE := 11.0
const TOW_RANGE := 7.0
const COLLECTIBLES_PER_LEVEL := 3
const WAVE_TIME := 60.0

# Ticket mini-game
const TICKET_RANGE := 3.2
const GREEN_SIZE := 0.16
const NEEDLE_SPEED := 1.5
const PERFECT_WRITE_TIME := 0.5
const SLOPPY_WRITE_TIME := 1.5

const CAMERA_OFFSET := Vector3(0, 17, 12.8)
const CAMERA_OFFSET_SPLIT := Vector3(0, 19, 11.5)
const WET := ["rain", "storm", "snow", "blizzard"]


## Everything that belongs to one warden: their score, combo, ticket writing and gadgets.
class Player extends RefCounted:
	var index := 0
	var warden
	var camera: Camera3D
	var viewport_offset := Vector2.ZERO
	var score := 0
	var tickets := 0
	var perfects := 0
	var punches := 0
	var close_calls := 0
	var wrong := 0
	var hit := 0
	var combo_index := 0
	var combo_timer := 0.0
	var best_combo := 1.0
	var writing := false
	var write_car = null
	var write_phase := ""
	var needle := 0.0
	var needle_dir := 1.0
	var green_start := 0.4
	var green_size := 0.16
	var write_progress := 0.0
	var write_duration := 1.0
	var write_perfect := false
	var gadgets: Array = []  # gadget ids this warden can use
	var gadget_i := 0
	var uses := {}
	var shake := 0.0
	var sweets := 0  # Halloween: one sweet per trick-or-treater gets you a treat


var rng := RandomNumberGenerator.new()
var level: Dictionary
var mode := "career"
var world
var weather
var weather_kind := "clear"
var hud
var camera: Camera3D  # player 1's camera
var warden  # player 1's warden (cars and the HUD use it in single player)
var players: Array = []
var focus: Node3D  # weather follows this (the middle of both players)
var cars_root: Node3D
var spots: Array[Dictionary] = []

var state := "intro"  # intro, playing, results
var intro_left := 3.0
var time_left := 180.0
var elapsed := 0.0
var quota := 10
var heckles := 0
var spawn_timer := 3.0
var spawn_every := Vector2(1.5, 3.5)
var heckle_timer := 4.0
var heckle_every := 7.0
var bus_timer := 12.0
var warned_time := false
var chase_chance := CHASE_CHANCE
var max_cars := 13
var quota_time := -1.0

# Career extras tracked for challenges and results
var shift := {"bosses": 0, "clamps": 0, "tows": 0, "cameras": 0, "street_events": 0, "pickups": 0,
	"splashes": 0, "zaps": 0, "dodges": 0, "sports_tickets": 0, "wet_tickets": 0, "collectibles": 0}

# Bosses
var boss_time := -1.0
var boss_car = null
var boss: Dictionary = {}
var boss_timer := 0.0
var boss_escapes := 0
var boss_guards := false
var boss_respawn := -1.0

# Street events, pickups, collectibles and pedestrians
var street_timer := 30.0
var street_event = null
var pickup_timer := 15.0
var pickups: Array = []
var collectibles: Array = []  # [node, index]
var camera_vans: Array = []
var ped_target := 2

# Pacing: the first career levels add one new thing at a time, and nothing big happens in the
# opening seconds of a shift, so a new player can learn spotting, ticketing and running first.
const QUIET_START := 30.0  # no street events, bosses or pickups before this
const EVENT_GAP := 40.0  # minimum seconds between big moments (street events and bosses)
var features := {}
var last_big := -999.0  # elapsed time of the last street event or boss
var wildlife  # birds and cats
var training := false  # Training Day: a short coached first shift
var coach_step := -1
var coach_t := 0.0

# Christmas Eve: Santa's sleigh flies over and drops presents
var sleigh_timer := 18.0
var flyover: Node3D = null
var fly_dir := Vector3.RIGHT
var fly_drop := 0.0

# Endless mode
var wave := 1
var wave_left := WAVE_TIME
var wave_tickets := 0
var wave_quota := 4


func _ready() -> void:
	rng.randomize()
	mode = Game.mode
	level = Game.play_level()
	time_left = level.time
	quota = level.quota
	max_cars = level.max_cars
	heckle_every = level.heckle_every
	chase_chance = CHASE_CHANCE + float(level.get("chase_bonus", 0.0))
	if mode == "coop":
		quota = int(ceil(quota * 1.6))
		max_cars += 6
	elif mode == "race":
		max_cars += 6
	elif mode == "endless":
		time_left = WAVE_TIME
		wave_quota = _wave_quota(1)

	training = Game.training and mode == "career"
	if training:
		level = level.duplicate(true)
		level.name = "Training Day"
		level.weathers = ["clear"]
		level.id = "training"
		time_left = 150.0
		quota = 3
		max_cars = 14
		level.time = 150.0
	features = _features()
	if training:
		features = {"hecklers_full": false, "events": [], "boss": false, "storms": false}
		heckle_every = 9999.0
	if not features.hecklers_full:
		heckle_every *= 2.2

	world = WorldScript.new()
	world.name = "World"
	add_child(world)
	world.build(level, rng)
	spots = world.spots

	cars_root = Node3D.new()
	cars_root.name = "Cars"
	add_child(cars_root)
	focus = Node3D.new()
	add_child(focus)

	var two := mode in ["coop", "race"]
	if two:
		Game.setup_two_player_inputs()
	for i in (2 if two else 1):
		_add_player(i, two)
	warden = players[0].warden
	camera = players[0].camera

	var options: Array = level.get("weathers", ["clear"])
	if not features.storms:
		# Thunder, lightning and blizzards wait until the player has a few levels under their belt
		var calm := options.filter(func(k: String) -> bool: return not k in ["storm", "blizzard"])
		options = calm if not calm.is_empty() else ["clear"]
	weather_kind = options[rng.randi() % options.size()]
	weather = WeatherScript.new()
	weather.main = self
	add_child(weather)
	weather.setup(weather_kind, world, focus)
	for p in players:
		p.warden.speed_mult = weather.speed_mult()
		p.warden.grip = weather.grip()
		p.warden.set_torch(level.get("night", false))
	if weather_kind in ["rain", "storm"]:
		world.build_road_puddles()

	hud = HudScript.new()
	hud.main = self
	add_child(hud)
	var info: Dictionary = WeatherScript.INFO[weather_kind]
	var mode_name: String = {"career": "", "event": "Special event", "endless": "Endless", "coop": "Co-op", "race": "Ticket Race"}[mode]
	var weather_name: String = info.name
	if weather_kind == "clear" and level.get("night", false):
		weather_name = "Night"
	hud.set_level_info("%s  -  %s%s" % [level.name, weather_name, ("  -  " + mode_name) if mode_name != "" else ""])
	var pause = PauseScript.new()
	pause.main = self
	add_child(pause)

	var open_spots := spots.duplicate()
	open_spots.shuffle()
	for i in mini(int(max_cars * 0.6), open_spots.size()):
		_spawn_car(open_spots[i], true)

	_plan_boss()
	if mode in ["career", "endless"] and not level.has("event") and not training:
		_spawn_collectibles()
	ped_target = int(level.get("ped_count", {"city": 4, "town": 3}.get(level.theme, 2))) + (1 if level.has("event") else 0) + (1 if two else 0)
	if not features.hecklers_full:
		ped_target = 1
	if training:
		ped_target = 0
	for i in ped_target:
		_spawn_pedestrian()
	wildlife = preload("res://scripts/wildlife.gd").spawn(self)
	preload("res://scripts/dogwalker.gd").spawn_some(self, 1 if training or level.theme in ["carpark", "multistorey", "city"] else 3)
	street_timer = rng.randf_range(QUIET_START + 15.0, QUIET_START + 35.0)
	pickup_timer = rng.randf_range(QUIET_START, QUIET_START + 15.0)
	heckle_timer = rng.randf_range(8.0, 14.0) if features.hecklers_full else rng.randf_range(25.0, 35.0)

	Audio.play_music(_music())
	var amb: String = weather.ambience()
	Audio.play_ambience(amb if amb != "" else level.ambience)
	var tip: String = info.tip
	var goal := "Ticket %d bad parkers" % quota
	if mode == "endless":
		goal = "Wave 1: ticket %d in a minute.\nMiss a wave and it's over!" % wave_quota
	elif mode == "race":
		goal = "Most tickets wins!"
	elif mode == "coop":
		goal = "Work together: %d tickets" % quota
	if training:
		goal = "Learn the ropes: ticket 3 bad parkers"
		tip = ""
	hud.banner("%s\n%s%s" % [level.name.to_upper(), goal, ("\n" + tip) if tip != "" else ""], 2.2)
	_update_hud()


func _music() -> String:
	match mode:
		"endless":
			return "endless"
		"coop", "race":
			return "versus"
	return level.get("music_event", level.music) if not level.has("event") else {
		"ev_wedding": "wedding", "ev_matchday": "matchday", "ev_xmas": "xmas", "ev_binstrike": "street"}.get(level.event, level.music)


func _add_player(i: int, two: bool) -> void:
	var p := Player.new()
	p.index = i
	var w = WardenScript.new()
	w.name = "Warden%d" % (i + 1)
	w.main = self
	if two:
		w.player = i + 1
		w.outfit = Game.outfit if i == 0 else Game.outfit2
		w.weapon_id = Game.weapon if i == 0 else Game.weapon2
	else:
		w.weapon_id = Game.weapon
	add_child(w)
	var start: Vector2 = level.start + Vector2(i * 3.0, 0)
	w.position = world.nearest_walkable(Vector3(start.x, 0, start.y))
	p.warden = w
	var cam := Camera3D.new()
	cam.fov = 50.0
	cam.rotation_degrees = Vector3(-53, 0, 0) if not two else Vector3(-59, 0, 0)
	if two:
		var container := SubViewportContainer.new()
		container.stretch = true
		container.position = Vector2(i * 642, 0)
		container.size = Vector2(638, 720)
		var layer := CanvasLayer.new()
		layer.layer = -1
		add_child(layer)
		layer.add_child(container)
		var vp := SubViewport.new()
		vp.handle_input_locally = false
		vp.msaa_3d = Viewport.MSAA_2X
		container.add_child(vp)
		vp.add_child(cam)
		p.viewport_offset = container.position
	else:
		add_child(cam)
	cam.current = true
	cam.position = w.position + _cam_offset()
	p.camera = cam
	p.green_size = GREEN_SIZE + 0.03 * Game.upgrade_level("book")
	p.sweets = int(level.get("sweets", 0))
	for g in Career.GADGETS:
		var n := Game.gadget_uses(g.id)
		if n > 0:
			p.gadgets.append(g.id)
			p.uses[g.id] = n
	players.append(p)


func _cam_offset() -> Vector3:
	var base := CAMERA_OFFSET_SPLIT if players.size() > 1 or mode in ["coop", "race"] else CAMERA_OFFSET
	return base * Game.camera_zoom()


# ---------------------------------------------------------------- helpers used by cars, drivers and pedestrians

func all_wardens() -> Array:
	var out := []
	for p in players:
		out.append(p.warden)
	return out


func nearest_warden(pos: Vector3):
	var best = null
	var best_d := INF
	for p in players:
		var d: float = p.warden.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = p.warden
	return best


func player_of(w) -> Player:
	for p in players:
		if p.warden == w:
			return p
	return players[0]


func ground_speed(pos: Vector3) -> float:
	return world.speed_at(pos)


func total_score() -> int:
	var n := 0
	for p in players:
		n += p.score
	return n


func total_tickets() -> int:
	var n := 0
	for p in players:
		n += p.tickets
	return n


func _sum(key: String) -> int:
	var n := 0
	for p in players:
		n += int(p.get(key))
	return n


# ---------------------------------------------------------------- spawning

func _spawn_car(spot: Dictionary, already_parked: bool, kind := "", boss_def := {}) -> void:
	var car = CarScript.new()
	car.main = self
	car.spot = spot
	car.lane = spot.lane
	car.start_parked = already_parked
	car.kind = kind
	car.boss = boss_def
	car.expired_chance = float(level.get("expired_chance", 0.35))
	if kind == "" and level.has("special_car") and rng.randf() < float(level.special_car.chance):
		car.kind = level.special_car.kind
	if not already_parked and weather_kind in ["rain", "storm"] and rng.randf() < 0.3:
		car.splasher = true
	spot.car = car
	cars_root.add_child(car)
	if not boss_def.is_empty():
		boss_car = car


func _spawn_passer(heckler: bool, kind := "") -> void:
	var car = CarScript.new()
	car.main = self
	car.lane = world.lanes[rng.randi() % world.lanes.size()]
	car.heckler = heckler
	car.kind = kind
	# Themed levels mix their own voiced heckles in with the usual ones
	if level.has("heckle_lines") and rng.randf() < 0.65:
		car.heckle_lines = level.heckle_lines
		car.heckle_voice = level.get("heckle_voice", "heckle")
	if weather_kind in ["rain", "storm"] and rng.randf() < 0.6:
		car.splasher = true
	# Don't pop out on top of another car at the lane start
	for c in get_tree().get_nodes_in_group("cars"):
		if c.lane == car.lane and c.is_moving() and c.s < 12.0:
			car.free()
			return
	cars_root.add_child(car)


func _parked_count() -> int:
	var n := 0
	for c in get_tree().get_nodes_in_group("cars"):
		if c.spot != null:
			n += 1
	return n


func _open_spot(no_bus_stop := false):
	var open_spots: Array[Dictionary] = []
	for s in spots:
		if s.car == null and not (no_bus_stop and s.type == "busstop"):
			open_spots.append(s)
	if open_spots.is_empty():
		return null
	var spot: Dictionary = open_spots[rng.randi() % open_spots.size()]
	for c in get_tree().get_nodes_in_group("cars"):
		if c.lane == spot.lane and c.is_moving() and c.s < 9.0:
			return null
	return spot


func _try_spawn() -> void:
	if _parked_count() >= max_cars:
		return
	var spot = _open_spot()
	if spot != null:
		_spawn_car(spot, false)


func _spawn_driver(car, target) -> void:
	var d = DriverScript.new()
	d.main = self
	d.car = car
	d.target = target
	if car.boss.get("id", "") == "vanman":
		d.hp = 2
		d.chase_speed = 6.3
	d.santa = car.kind == "sleigh"
	add_child(d)
	var along: Vector3 = car.spot.dir * rng.randf_range(9.0, 13.0) * (1.0 if rng.randf() < 0.5 else -1.0)
	var p: Vector3 = car.spot.pos + car.spot.normal * 4.4 + along
	if not world.is_walkable(p):
		p = car.spot.pos + car.spot.normal * 4.4
	d.global_position = p
	car.waiting_for_driver = true
	if d.santa:
		_popup("HO HO HO-HOLD ON!", Color(1, 0.35, 0.3), d.global_position, 30)
		Audio.voice("santa_hohoho", d.pitch)
	elif car.kind == "motorbike":
		_popup("Hey, that's my BIKE!", Color(1, 0.35, 0.3), d.global_position, 30)
		Audio.voice("driver_bike", d.pitch, 1.0, true, int(d.female))
	else:
		_popup("Oi! That's MY car!", Color(1, 0.35, 0.3), d.global_position, 30)
		Audio.voice("driver_oi", d.pitch, 1.0, true, int(d.female))


func _spawn_bodyguards(car) -> void:
	for i in 2:
		var d = DriverScript.new()
		d.main = self
		d.car = null
		d.bodyguard = true
		d.chase_speed = 5.4
		d.chase_left = 12.0
		d.target = nearest_warden(car.global_position)
		add_child(d)
		d.global_position = car.spot.pos + car.spot.normal * 2.0 + car.spot.dir * (2.5 if i == 0 else -2.5)
	_popup("BODYGUARDS!", Color(1, 0.4, 0.9), car.global_position + Vector3(0, 3, 0), 44)


func _spawn_pedestrian() -> void:
	var p = PedestrianScript.new()
	p.main = self
	var kinds: Array = level.get("peds", ["drunk", "geezer", "stag"])
	p.kind = kinds[rng.randi() % kinds.size()]
	var pos: Vector3 = world.random_walk_point(rng, warden.global_position if warden else Vector3.ZERO, 14.0, true)
	p.position = pos
	add_child(p)


# ---------------------------------------------------------------- main loop

func _process(delta: float) -> void:
	_update_cameras(delta)
	_update_spot_labels()
	if state == "intro":
		var before := int(ceil(intro_left))
		intro_left -= delta
		var now := int(ceil(intro_left))
		if now != before and now > 0 and now <= 3:
			Audio.sfx("beep")
		if intro_left <= 0.0:
			state = "playing"
			Audio.sfx("whistle_long")
			Audio.voice("announce_go")
			hud.banner("GO!", 0.6, true)
		return
	if state == "results":
		return

	elapsed += delta
	time_left -= delta
	if time_left <= 30.0 and not warned_time and mode != "endless":
		warned_time = true
		hud.banner("30 SECONDS LEFT!", 1.2, true)
		Audio.sfx("beep_go")
	if time_left <= 0.0:
		time_left = 0.0
		if mode == "endless" and _next_wave():
			pass
		else:
			_end_shift()
			return
	for p in players:
		if p.combo_timer > 0.0:
			p.combo_timer -= delta
			if p.combo_timer <= 0.0:
				p.combo_index = 0
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = rng.randf_range(spawn_every.x, spawn_every.y)
		_try_spawn()
	heckle_timer -= delta
	if heckle_timer <= 0.0:
		heckle_timer = rng.randf_range(heckle_every * 0.6, heckle_every * 1.4)
		_spawn_passer(rng.randf() < 0.7)
	if world.bus_stops > 0:
		bus_timer -= delta
		if bus_timer <= 0.0:
			bus_timer = rng.randf_range(18.0, 28.0)
			_spawn_passer(false, "bus")
	if get_tree().get_nodes_in_group("pedestrians").size() < ped_target and rng.randf() < delta * 0.1:
		_spawn_pedestrian()

	if training:
		_update_coach(delta)
	_update_boss(delta)
	_update_flyover(delta)
	_update_street(delta)
	_update_pickups(delta)
	_update_collectibles(delta)
	_update_camera_vans(delta)
	for p in players:
		_update_ticketing(p, delta)
	_update_hud()


func _update_hud() -> void:
	var show_time := time_left
	hud.update_stats(show_time, total_score(), total_tickets() if mode != "endless" else wave_tickets,
		quota if mode != "endless" else wave_quota)
	for p in players:
		hud.update_player(p.index, {
			"score": p.score, "tickets": p.tickets,
			"combo": COMBO_STEPS[p.combo_index] if p.combo_index > 0 else 1.0, "combo_frac": p.combo_timer / COMBO_WINDOW,
			"stamina": p.warden.stamina_frac(), "exhausted": p.warden.exhausted,
			"gadget": p.gadgets[p.gadget_i] if not p.gadgets.is_empty() else "",
			"uses": int(p.uses.get(p.gadgets[p.gadget_i], 0)) if not p.gadgets.is_empty() else 0,
			"boost": p.warden.boost_timer, "soaked": p.warden.soak_timer > 0.0,
			"sweets": p.sweets if level.has("sweets") else -1,
		})
	if not boss.is_empty() and is_instance_valid(boss_car):
		hud.set_boss(boss.name, int(boss_car.boss.hp), int(boss.hp))
	else:
		hud.set_boss("", 0, 0)


func _update_cameras(delta: float) -> void:
	var mid := Vector3.ZERO
	for p in players:
		var target: Vector3 = p.warden.global_position + _cam_offset()
		p.camera.position = p.camera.position.lerp(target, 1.0 - exp(-6.0 * delta))
		p.shake = move_toward(p.shake, 0.0, delta * 1.5)
		var amount: float = p.shake if Game.settings.shake else 0.0
		p.camera.h_offset = rng.randf_range(-1.0, 1.0) * amount
		p.camera.v_offset = rng.randf_range(-1.0, 1.0) * amount
		mid += p.warden.global_position
	focus.global_position = mid / players.size()


func _shake(p: Player, amount: float) -> void:
	p.shake = maxf(p.shake, amount)


func _shake_all(amount: float) -> void:
	for p in players:
		_shake(p, amount)


func _update_spot_labels() -> void:
	for spot in spots:
		var label: Label3D = spot.label
		if label == null:
			continue
		var car = spot.car
		if car == null or not is_instance_valid(car) or not car.is_parked():
			label.visible = false
			continue
		var w = nearest_warden(label.global_position)
		label.visible = w.global_position.distance_to(label.global_position) < 12.0
		if car.meter_time > 0.0:
			label.text = "PAID %ds" % int(ceil(car.meter_time))
			label.modulate = Color(0.45, 1, 0.5)
		else:
			label.text = "EXPIRED"
			label.modulate = Color(1, 0.35, 0.3)


# ---------------------------------------------------------------- endless waves

func _wave_quota(n: int) -> int:
	return 3 + n


func _next_wave() -> bool:
	## End of a wave in endless mode. Returns false if the quota was missed (game over).
	if wave_tickets < wave_quota:
		return false
	var bonus := 100 * wave
	players[0].score += bonus
	wave += 1
	wave_tickets = 0
	wave_quota = _wave_quota(wave)
	time_left = WAVE_TIME
	max_cars = mini(max_cars + 2, spots.size())
	spawn_every *= 0.88
	heckle_every = maxf(heckle_every * 0.9, 2.5)
	chase_chance = minf(chase_chance + 0.04, 0.8)
	Audio.sting("quota")
	Audio.voice("announce_wave")
	hud.banner("WAVE %d!  +%d\nTicket %d in a minute" % [wave, bonus, wave_quota], 2.0)
	if wave % 3 == 0 and boss.is_empty():
		boss_time = elapsed + 8.0
	return true


# ---------------------------------------------------------------- ticketing

func _update_ticketing(p: Player, delta: float) -> void:
	var w = p.warden
	if p.writing and w.is_busy():
		_cancel_write(p, "Dropped the notepad!")
	if not p.writing:
		var target = _find_ticket_target(p)
		var punchable = _find_punch_target(w)
		if punchable != null:
			hud.set_hint(p.index, "Punch!", "punch")
		elif target != null:
			hud.set_hint(p.index, "Write ticket", "ticket")
		elif not p.gadgets.is_empty() and _gadget_target(p) != null:
			hud.set_hint(p.index, Career.GADGETS[_gadget_index(p.gadgets[p.gadget_i])].name, "gadget")
		else:
			hud.set_hint(p.index, "")
		if target != null and not w.is_busy() and w.pressed("ticket"):
			_start_write(p, target)
		return

	hud.set_hint(p.index, "")
	if not is_instance_valid(p.write_car) or not p.write_car.is_parked():
		_cancel_write(p, "They drove off!")
		return
	if p.write_phase == "needle":
		p.needle += p.needle_dir * NEEDLE_SPEED * delta
		if p.needle >= 1.0:
			p.needle = 1.0
			p.needle_dir = -1.0
		elif p.needle <= 0.0:
			p.needle = 0.0
			p.needle_dir = 1.0
		if w.pressed("ticket"):
			var size: float = _green_for(p)
			p.write_perfect = p.needle >= p.green_start and p.needle <= p.green_start + size
			var speedup := 1.0 - 0.12 * Game.upgrade_level("book")
			p.write_duration = (PERFECT_WRITE_TIME if p.write_perfect else SLOPPY_WRITE_TIME) * speedup
			p.write_phase = "writing"
			p.write_progress = 0.0
			Audio.sfx("scribble", 1.4 if p.write_perfect else 1.0)
			if p.write_perfect:
				Audio.sfx("ding")
				_popup("PERFECT!", Color(0.4, 1, 0.45), w.global_position + Vector3(0, 2.5, 0))
			else:
				_popup("Scribble...", Color(0.85, 0.85, 0.85), w.global_position + Vector3(0, 2.5, 0), 26)
	else:
		p.write_progress += delta / p.write_duration
		if p.write_progress >= 1.0:
			_finish_write(p)
			return
	hud.set_ticket_ui(p.index, true, p.needle, p.green_start, _green_for(p), p.write_phase, p.write_progress)


func _green_for(p: Player) -> float:
	var size := p.green_size
	if is_instance_valid(p.write_car) and p.write_car.boss.get("id", "") == "getaway":
		size *= 0.6
	return size


func _being_written(car) -> bool:
	for p in players:
		if p.writing and p.write_car == car:
			return true
	return false


func _find_ticket_target(p: Player):
	var best = null
	var best_d := TICKET_RANGE
	for car in get_tree().get_nodes_in_group("cars"):
		if car.spot == null or not car.is_parked() or car.ticketed or _being_written(car):
			continue
		var d: float = p.warden.global_position.distance_to(car.global_position)
		if d < best_d + (1.5 if car.car_length > 6.0 else 0.0):
			best_d = d
			best = car
	return best


func _find_punch_target(w):
	var origin: Vector3 = w.global_position
	var best = null
	var best_d: float = float(w.weapon.range) + 0.6
	for d in get_tree().get_nodes_in_group("drivers"):
		if not d.can_be_punched():
			continue
		var dist: float = origin.distance_to(d.global_position)
		if dist < best_d:
			best_d = dist
			best = d
	return best


func _start_write(p: Player, car) -> void:
	p.writing = true
	p.write_car = car
	p.write_phase = "needle"
	p.needle = 0.0
	p.needle_dir = 1.0
	p.green_start = rng.randf_range(0.2, 0.75)
	p.write_progress = 0.0
	p.warden.locked = true
	p.warden.face_towards(car.global_position)
	Audio.sfx("tick")


func _cancel_write(p: Player, message: String) -> void:
	p.writing = false
	p.write_car = null
	p.warden.locked = false
	hud.set_ticket_ui(p.index, false, 0.0, 0.0, 0.0, "", 0.0)
	if message != "":
		_popup(message, Color(1, 0.6, 0.3), p.warden.global_position + Vector3(0, 2.5, 0), 28)


func _finish_write(p: Player) -> void:
	var car = p.write_car
	var perfect := p.write_perfect
	_cancel_write(p, "")
	car.give_ticket()
	Audio.sfx("stamp", rng.randf_range(0.95, 1.05))
	var pos: Vector3 = car.global_position + Vector3(0, 2.2, 0)

	if not car.is_illegal():
		p.score -= WRONG_PENALTY
		p.wrong += 1
		_break_combo(p)
		var why: String = "Blue badge holder!" if car.blue_badge else "Legal car"
		_popup("WRONG! %s  -%d" % [why, WRONG_PENALTY], Color(1, 0.3, 0.25), pos, 34)
		Audio.sfx("wrong")
		_shake(p, 0.25)
		car.leave_after(rng.randf_range(2.0, 4.0))
		return
	if perfect:
		p.perfects += 1
	_score_ticket(p, car, BASE_POINTS + (PERFECT_BONUS if perfect else 0), "STAMP!")
	if not car.boss.is_empty():
		return
	if rng.randf() < chase_chance or (car.kind == "wedding"):
		_spawn_driver(car, p.warden)
	else:
		car.leave_after(rng.randf_range(3.0, 6.0))


## Points, combo, quota and boss damage for a ticket, however it was written (pen, clamp, tow, camera van).
func _score_ticket(p: Player, car, base: int, word: String, combo := true, damage := 1) -> void:
	var pos: Vector3 = car.global_position + Vector3(0, 2.2, 0)
	p.tickets += 1
	wave_tickets += 1
	if combo:
		if p.combo_timer > 0.0:
			p.combo_index = mini(p.combo_index + 1, COMBO_STEPS.size() - 1)
		else:
			p.combo_index = 0
		p.combo_timer = COMBO_WINDOW
	var mult: float = COMBO_STEPS[p.combo_index] if combo else 1.0
	p.best_combo = maxf(p.best_combo, mult)
	var bonus := 0
	if level.has("special_car") and car.kind == level.special_car.kind:
		bonus = int(level.special_car.bonus)
	var points := int(round((base + bonus) * mult))
	p.score += points
	_popup("%s  +%d" % [word, points], Color(1, 0.9, 0.2), pos, 44)
	if bonus > 0:
		_popup("%s BONUS!" % car.kind.to_upper(), Color(1, 0.5, 0.9), pos + Vector3(0, 1.2, 0), 30)
	if combo and p.combo_index > 0:
		_popup("COMBO x%s" % str(mult), Color(1, 0.6, 0.15), pos + Vector3(0, -1.2, 0), 30)
		Audio.sfx("combo", 1.0 + p.combo_index * 0.1)
	if car.kind == "sports":
		shift.sports_tickets += 1
	if weather_kind in WET:
		shift.wet_tickets += 1
	_shake(p, 0.15)
	if mode != "endless" and mode != "race" and total_tickets() == quota:
		quota_time = elapsed
		hud.banner("QUOTA MET!  Keep going for stars", 2.0)
		Audio.sting("quota")
		Audio.voice("announce_quota")
	elif rng.randf() < 0.2:
		Audio.voice(["warden_niceday", "warden_gotcha", "warden_rules"][rng.randi() % 3])
	if not car.boss.is_empty():
		_hit_boss(p, car, damage)


func _break_combo(p: Player) -> void:
	p.combo_index = 0
	p.combo_timer = 0.0


# ---------------------------------------------------------------- gadgets: clamp, tow truck, camera van

func _gadget_index(id: String) -> int:
	for i in Career.GADGETS.size():
		if Career.GADGETS[i].id == id:
			return i
	return 0


func _gadget_target(p: Player):
	var id: String = p.gadgets[p.gadget_i]
	if int(p.uses.get(id, 0)) <= 0 or id == "camera":
		return null
	var reach := TICKET_RANGE + 0.5 if id == "clamp" else TOW_RANGE
	var best = null
	var best_d := reach
	for car in get_tree().get_nodes_in_group("cars"):
		if car.spot == null or not car.is_parked() or car.ticketed or not car.is_illegal() or _being_written(car):
			continue
		var d: float = p.warden.global_position.distance_to(car.global_position)
		if d < best_d:
			best_d = d
			best = car
	return best


func next_gadget(w) -> void:
	var p := player_of(w)
	if p.gadgets.size() < 2:
		if p.gadgets.is_empty():
			_popup("No gadgets yet. Get promoted!", Color(0.8, 0.8, 0.8), w.global_position + Vector3(0, 2.6, 0), 24)
		return
	p.gadget_i = (p.gadget_i + 1) % p.gadgets.size()
	Audio.sfx("ui_move")
	_popup(Career.GADGETS[_gadget_index(p.gadgets[p.gadget_i])].name, Color(0.6, 0.9, 1), w.global_position + Vector3(0, 2.6, 0), 28)


func use_gadget(w) -> void:
	var p := player_of(w)
	if p.gadgets.is_empty():
		_popup("No gadgets yet. Get promoted!", Color(0.8, 0.8, 0.8), w.global_position + Vector3(0, 2.6, 0), 24)
		return
	var id: String = p.gadgets[p.gadget_i]
	if int(p.uses.get(id, 0)) <= 0:
		_popup("Out of %ss!" % Career.GADGETS[_gadget_index(id)].name, Color(1, 0.6, 0.3), w.global_position + Vector3(0, 2.6, 0), 28)
		Audio.sfx("wrong", 1.2, 0.5)
		return
	if p.writing:
		_cancel_write(p, "")
	var g: Dictionary = Career.GADGETS[_gadget_index(id)]
	if id == "camera":
		p.uses[id] -= 1
		shift.cameras += 1
		_deploy_camera_van(p)
		return
	var car = _gadget_target(p)
	if car == null:
		_popup("Nothing to %s here" % ("clamp" if id == "clamp" else "tow"), Color(0.85, 0.85, 0.85), w.global_position + Vector3(0, 2.6, 0), 26)
		return
	p.uses[id] -= 1
	if id == "clamp":
		shift.clamps += 1
		Audio.sfx("clamp")
		_score_ticket(p, car, int(g.points), "CLAMPED!", true, 1)
		car.clamp_wheel(CLAMP_TIME)
		if not car.boss.is_empty() and is_instance_valid(car):
			boss_timer = -10.0  # a clamped boss can't drive off for a while
	else:
		shift.tows += 1
		Audio.sfx("tow")
		_score_ticket(p, car, int(g.points), "TOWED!", true, 2)
		# A boss with tickets left shrugs off the tow truck; anyone else gets dragged away
		if car.boss.is_empty():
			car.tow_away()


func _deploy_camera_van(p: Player) -> void:
	var w = p.warden
	var van := Node3D.new()
	van.position = w.global_position + w.facing * 1.5
	add_child(van)
	var white := Util.mat(Color(0.95, 0.95, 0.95), true)
	van.add_child(Util.box(Vector3(4.2, 1.8, 2.0), white, Vector3(0, 1.2, 0)))
	van.add_child(Util.box(Vector3(4.24, 0.3, 2.04), Util.mat(Color(1, 0.85, 0.1)), Vector3(0, 1.0, 0)))
	van.add_child(Util.box(Vector3(0.6, 0.5, 0.5), Util.mat(Color(0.15, 0.15, 0.2), true), Vector3(0.5, 2.4, 0)))
	van.add_child(Util.sphere(0.18, Util.glow(Color(1, 0.2, 0.2), 3.0), Vector3(0.5, 2.4, 0.3)))
	van.add_child(Util.label3d("CAMERA ENFORCEMENT", 34, Color(0.1, 0.1, 0.2), Vector3(0, 1.6, 1.02)))
	for x in [-1.3, 1.3]:
		for z in [-1.0, 1.0]:
			var wheel := Util.cylinder(0.38, 0.28, Color(0.1, 0.1, 0.1), Vector3(x, 0.38, z), true)
			wheel.rotation_degrees.x = 90.0
			van.add_child(wheel)
	var ring := Util.torus(CAMERA_VAN_RANGE - 0.2, CAMERA_VAN_RANGE, Util.glow(Color(1, 0.3, 0.3), 1.5), Vector3(0, 0.08, 0))
	van.add_child(ring)
	var label := Util.label3d("", 40, Color(1, 0.4, 0.4), Vector3(0, 3.3, 0))
	van.add_child(label)
	van.scale = Vector3(1, 0.01, 1)
	create_tween().tween_property(van, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	camera_vans.append({"node": van, "left": CAMERA_VAN_TIME, "tick": 1.5, "player": p, "label": label, "ring": ring})
	_popup("CAMERA VAN DEPLOYED!", Color(1, 0.5, 0.4), van.position + Vector3(0, 3, 0), 36)
	Audio.sfx("whoosh")


func _update_camera_vans(delta: float) -> void:
	for v in camera_vans.duplicate():
		v.left -= delta
		v.tick -= delta
		v.label.text = "REC %ds" % int(ceil(v.left))
		v.ring.rotation.y += delta
		if v.tick <= 0.0:
			v.tick = 3.0
			var best = null
			var best_d := CAMERA_VAN_RANGE
			for car in get_tree().get_nodes_in_group("cars"):
				if car.spot == null or not car.is_parked() or car.ticketed or not car.is_illegal() or _being_written(car):
					continue
				var d: float = v.node.position.distance_to(car.global_position)
				if d < best_d:
					best_d = d
					best = car
			if best != null:
				Audio.sfx("camera")
				best.give_ticket()
				_flash_at(best.global_position)
				_score_ticket(v.player, best, Career.GADGETS[2].points, "SNAPPED!", false)
				if best.boss.is_empty():
					best.leave_after(rng.randf_range(2.0, 4.0))
		if v.left <= 0.0:
			camera_vans.erase(v)
			var tw := create_tween()
			tw.tween_property(v.node, "scale", Vector3(1, 0.01, 1), 0.3)
			tw.tween_callback(v.node.queue_free)


func _flash_at(pos: Vector3) -> void:
	var f := Util.sphere(1.0, Util.glow(Color(1, 1, 1), 6.0), pos + Vector3(0, 2.0, 0))
	add_child(f)
	var tw := create_tween()
	tw.tween_property(f, "scale", Vector3.ONE * 2.0, 0.12)
	tw.tween_callback(f.queue_free)


# ---------------------------------------------------------------- bosses

## What this shift is allowed to throw at the player. Career levels unlock one thing at a time:
## 1 Pleasant Street: cars, drivers and the ticket needle (plus the odd heckler)
## 2 Market Crossroads: hecklers in full, pigeons
## 3 Seaside Prom: runaway trolleys and the ice cream van, bosses
## 4 Snowy Village onwards: everything, including storms and blizzards
func _features() -> Dictionary:
	var index := Levels.index_of(level.id)
	var all := mode != "career" or index >= 3
	return {
		"hecklers_full": all or index >= 1,
		"events": ["pigeons", "trolley", "icecream"] if (all or index >= 2) else (["pigeons"] if index >= 1 else []),
		"boss": all or index >= 2,
		"storms": all,
	}


## True while something big is already going on, or one has only just finished.
func _busy_for_big_moment() -> bool:
	if elapsed < QUIET_START or elapsed - last_big < EVENT_GAP:
		return true
	if not boss.is_empty() or street_event != null:
		return true
	return false


## Training Day: one tip at a time, moving on when the player has done it.
func _update_coach(delta: float) -> void:
	coach_t += delta
	var p: Player = players[0]
	var w = p.warden
	var next := coach_step
	match coach_step:
		-1:
			if elapsed > 2.5:
				next = 0
		0:
			# Near a bad parker yet?
			for car in get_tree().get_nodes_in_group("cars"):
				if car.spot != null and car.is_parked() and car.is_illegal() and not car.ticketed \
						and car.global_position.distance_to(w.global_position) < 5.0:
					next = 1
		1:
			if p.writing:
				next = 2
		2:
			if p.tickets >= 1:
				next = 3
			elif not p.writing and coach_t > 1.0:
				next = 1
		3:
			if coach_t > 7.0 or p.tickets >= 2:
				next = 4
		4:
			if coach_t > 7.0 or p.tickets >= 2:
				next = 5
		5:
			if total_tickets() >= quota:
				next = 6
		6:
			if coach_t > 2.5:
				time_left = minf(time_left, 0.05)
				next = 7
	if next == coach_step:
		return
	coach_step = next
	coach_t = 0.0
	match coach_step:
		0:
			hud.coach("Walk to a car with a red  !  over it: it's parked illegally", "move")
		1:
			hud.coach("Stand next to it and press Ticket", "ticket")
		2:
			hud.coach("Press Ticket again to stop the needle in the GREEN", "ticket")
		3:
			hud.coach("Nice! Drivers come running back. Hold Sprint to leg it!", "sprint")
		4:
			hud.coach("Cars inside the white lines with a PAID tag are legal. Leave them be!", "")
		5:
			hud.coach("Ticket %d bad parkers to finish your training" % quota, "ticket")
		6:
			hud.coach("")
			hud.banner("TRAINING COMPLETE!\nYou're ready for your first beat", 2.4)
		7:
			pass


func _plan_boss() -> void:
	var index := Levels.index_of(level.id)
	match mode:
		"career":
			if features.boss:
				boss_time = level.time * rng.randf_range(0.3, 0.5)
		"event":
			boss_time = level.time * rng.randf_range(0.3, 0.45)
		"coop", "race":
			if rng.randf() < 0.6:
				boss_time = level.time * rng.randf_range(0.3, 0.5)


func _update_boss(delta: float) -> void:
	if boss.is_empty():
		if boss_time >= 0.0 and elapsed >= boss_time:
			if _busy_for_big_moment():
				return
			boss_time = -1.0
			last_big = elapsed
			_start_boss()
		return
	if boss_respawn >= 0.0:
		boss_respawn -= delta
		if boss_respawn <= 0.0:
			boss_respawn = -1.0
			_place_boss_car()
		return
	if not is_instance_valid(boss_car):
		return
	if not boss_car.is_parked():
		return
	boss_timer += delta
	match boss.id:
		"mayor":
			if not boss_guards:
				for w in all_wardens():
					if w.global_position.distance_to(boss_car.global_position) < 9.0:
						boss_guards = true
						_spawn_bodyguards(boss_car)
						boss_car.shout(boss.line)
						Audio.voice(boss.voice)
						break
		"vanman":
			if boss_timer > 14.0 and not _being_written(boss_car):
				_relocate_boss("See ya, jobsworth!")
		"getaway":
			for w in all_wardens():
				if w.is_sprinting() and w.global_position.distance_to(boss_car.global_position) < 9.0 and not _being_written(boss_car) and not boss_car.clamped:
					_relocate_boss("SPOTTED YOU!")
					return
			if boss_timer > 20.0 and not _being_written(boss_car):
				_relocate_boss("Too slow!")


func _start_boss() -> void:
	var b: Dictionary = Career.BOSSES[rng.randi() % Career.BOSSES.size()].duplicate()
	boss = b
	boss_escapes = 0
	boss_guards = false
	hud.banner("BOSS INCOMING!\n%s" % b.intro, 3.0)
	Audio.voice("announce_boss")
	Audio.sting("boss")
	Audio.play_music("boss")
	_place_boss_car()


func _place_boss_car() -> void:
	var spot = _open_spot(true)
	if spot == null:
		boss_respawn = 2.0
		return
	var def: Dictionary = boss.duplicate()
	if is_instance_valid(boss_car) and not boss_car.boss.is_empty():
		def.hp = boss_car.boss.hp
	elif boss.has("hp_left"):
		def.hp = boss.hp_left
	boss_timer = 0.0
	_spawn_car(spot, false, boss.kind, def)


func _relocate_boss(line: String) -> void:
	boss_car.shout(line)
	boss_car.relocate()
	boss_timer = -999.0
	Audio.voice(boss.voice)


func _hit_boss(p: Player, car, damage: int) -> void:
	car.boss.hp = int(car.boss.hp) - damage
	if int(car.boss.hp) > 0:
		car.ticketed = false
		car.ticket_slip.visible = false
		_popup("%d MORE!" % int(car.boss.hp), Color(1, 0.4, 0.9), car.global_position + Vector3(0, 3.4, 0), 44)
		car.shout(boss.line)
		Audio.voice(boss.voice)
		if boss.id == "vanman":
			_spawn_driver(car, p.warden)
			car.waiting_for_driver = false
			_relocate_boss("Right, that's it!")
		elif boss.id == "getaway" and not car.clamped:
			_relocate_boss("You'll never catch me!")
		return
	# Beaten!
	var bonus := int(boss.bonus)
	p.score += bonus
	shift.bosses += 1
	_popup("BOSS BEATEN!  +%d" % bonus, Color(1, 0.4, 0.9), car.global_position + Vector3(0, 3.6, 0), 52)
	hud.banner("%s\nBEATEN!  +%d" % [boss.name, bonus], 2.0)
	Audio.sting("win")
	Audio.play_music(_music())
	_shake_all(0.5)
	if not car.towed:
		car.leave_after(2.5)
	car.boss = {}
	boss = {}
	last_big = elapsed
	boss_car = null


func on_car_gone(car) -> void:
	if car == boss_car and not boss.is_empty():
		boss_escapes += 1
		if boss.id == "getaway" and boss_escapes >= 4:
			hud.banner("THE GETAWAY CAR GOT AWAY!", 2.0)
			Audio.play_music(_music())
			boss = {}
			last_big = elapsed
			boss_car = null
			return
		boss.hp_left = car.boss.hp
		boss_car = null
		boss_respawn = 2.5


func on_bus_blocked(car) -> void:
	_popup("BUS BLOCKED!", Color(1, 0.4, 0.3), car.global_position + Vector3(0, 3.0, 0), 34)


# ---------------------------------------------------------------- street events, pickups and collectibles

func _update_street(delta: float) -> void:
	if street_event != null:
		if not is_instance_valid(street_event):
			street_event = null
		return
	street_timer -= delta
	if street_timer <= 0.0:
		if features.events.is_empty() or _busy_for_big_moment():
			street_timer = 5.0
			return
		street_timer = rng.randf_range(45.0, 70.0)
		last_big = elapsed
		var e = StreetEventScript.new()
		e.main = self
		e.kind = features.events[rng.randi() % features.events.size()]
		add_child(e)
		street_event = e


func on_street_event_done(e, w, points: int, text: String) -> void:
	last_big = elapsed
	if w != null:
		var p := player_of(w)
		p.score += points
		shift.street_events += 1
		_popup("%s  +%d" % [text, points], Color(0.5, 1, 0.8), e.global_position + Vector3(0, 2.8, 0), 40)
		Audio.sfx("combo", 1.2)


func _update_pickups(delta: float) -> void:
	pickup_timer -= delta
	if pickup_timer <= 0.0 and pickups.size() < 2:
		pickup_timer = rng.randf_range(16.0, 28.0)
		_spawn_pickup()
	for pk in pickups.duplicate():
		pk.left -= delta
		var n: Node3D = pk.node
		n.rotation.y += delta * 2.0
		n.position.y = world.height_at(n.position) + 0.6 + sin(elapsed * 3.0 + pk.phase) * 0.15
		if pk.left <= 0.0:
			pickups.erase(pk)
			n.queue_free()
			continue
		for w in all_wardens():
			if w.global_position.distance_to(Vector3(n.position.x, w.global_position.y, n.position.z)) < 1.3:
				pickups.erase(pk)
				n.queue_free()
				shift.pickups += 1
				player_of(w).score += 10
				match pk.kind:
					"coffee":
						w.boost(1.3, 9.0, false)
						_popup("COFFEE! Speed up!", Color(0.9, 0.7, 0.45), w.global_position + Vector3(0, 2.6, 0), 34)
						Audio.sfx("slurp")
					"energy":
						w.boost(1.5, 6.0, true)
						_popup("ENERGY DRINK! ZOOM!", Color(0.4, 1, 0.4), w.global_position + Vector3(0, 2.6, 0), 36)
						Audio.sfx("slurp")
					"sweets":
						player_of(w).sweets += 3
						_popup("BUCKET OF SWEETS!  +3", Color(1, 0.6, 0.15), w.global_position + Vector3(0, 2.6, 0), 36)
						Audio.sfx("rattle", 1.3)
					"present":
						_open_present(w)
				break


func _spawn_pickup() -> void:
	var kind := "coffee" if rng.randf() < 0.6 else "energy"
	if level.has("sweets") and rng.randf() < 0.55:
		kind = "sweets"
	var pos: Vector3 = world.random_walk_point(rng, warden.global_position, 8.0, true)
	_add_pickup(kind, pos)


func _add_pickup(kind: String, pos: Vector3) -> void:
	var n := Node3D.new()
	n.position = pos + Vector3(0, 0.6, 0)
	add_child(n)
	if kind == "sweets":
		# A pumpkin bucket full of sweets
		n.add_child(Util.sphere(0.4, Util.mat(Color(1, 0.5, 0.05), true), Vector3(0, 0, 0)))
		n.add_child(Util.box(Vector3(0.3, 0.06, 0.05), Util.glow(Color(1, 0.9, 0.2), 2.0), Vector3(0, 0.05, 0.38)))
		n.add_child(Util.torus(0.3, 0.34, Util.mat(Color(0.1, 0.1, 0.1)), Vector3(0, 0.4, 0)))
		for i in 4:
			n.add_child(Util.sphere(0.1, Color.from_hsv(i * 0.25, 0.8, 1.0), Vector3(-0.15 + i * 0.1, 0.35, 0.05 * (i % 2))))
		n.add_child(Util.label3d("SWEETS", 26, Color(1, 0.6, 0.15), Vector3(0, 0.85, 0)))
	elif kind == "present":
		var c: Color = [Color(0.9, 0.15, 0.15), Color(0.15, 0.6, 0.25), Color(0.2, 0.4, 0.95)][rng.randi() % 3]
		n.add_child(Util.box(Vector3(0.7, 0.6, 0.7), Util.mat(c, true), Vector3.ZERO))
		n.add_child(Util.box(Vector3(0.72, 0.62, 0.14), Util.mat(Color(1, 0.85, 0.2)), Vector3.ZERO))
		n.add_child(Util.box(Vector3(0.14, 0.62, 0.72), Util.mat(Color(1, 0.85, 0.2)), Vector3.ZERO))
		n.add_child(Util.torus(0.08, 0.16, Util.mat(Color(1, 0.85, 0.2)), Vector3(0, 0.38, 0)))
	elif kind == "coffee":
		n.add_child(Util.cylinder(0.22, 0.5, Util.mat(Color.WHITE, true), Vector3.ZERO, false, 0.28))
		n.add_child(Util.cylinder(0.3, 0.08, Util.mat(Color(0.35, 0.2, 0.1)), Vector3(0, 0.28, 0)))
		n.add_child(Util.cylinder(0.25, 0.15, Util.mat(Color(0.75, 0.55, 0.35)), Vector3(0, 0, 0)))
		n.add_child(Util.label3d("~", 40, Color(1, 1, 1, 0.8), Vector3(0, 0.75, 0)))
	else:
		n.add_child(Util.cylinder(0.18, 0.6, Util.mat(Color(0.15, 0.85, 0.3), true), Vector3.ZERO))
		n.add_child(Util.cylinder(0.185, 0.2, Util.glow(Color(0.2, 0.2, 0.2), 0.5), Vector3(0, 0.05, 0)))
		n.add_child(Util.label3d("ZAP", 28, Color(0.4, 1, 0.4), Vector3(0, 0.7, 0)))
	n.add_child(Util.torus(0.45, 0.55, Util.glow(Color(1, 1, 0.6), 1.5), Vector3(0, -0.55, 0)))
	pickups.append({"node": n, "kind": kind, "left": 25.0, "phase": rng.randf() * TAU})


func _open_present(w) -> void:
	var p := player_of(w)
	var pos: Vector3 = w.global_position + Vector3(0, 2.6, 0)
	var roll := rng.randf()
	if roll < 0.15:
		p.score -= 20
		_popup("LUMP OF COAL! NAUGHTY LIST  -20", Color(0.6, 0.6, 0.65), pos, 34)
		Audio.sfx("wrong", 0.8, 0.6)
	elif roll < 0.5:
		w.boost(1.4, 8.0, true)
		_popup("NEW TRAINERS! ZOOM!", Color(0.4, 1, 0.5), pos, 36)
		Audio.sfx("chimes")
	else:
		p.score += 150
		_popup("PRESENT!  +150", Color(1, 0.4, 0.4), pos, 40)
		Audio.sfx("chimes")


# ---------------------------------------------------------------- Halloween: trick or treat

## A trick-or-treater reached the warden. A sweet buys a treat; no sweets means a trick.
func on_trick_or_treat(kid, w) -> void:
	var p := player_of(w)
	var pos: Vector3 = w.global_position + Vector3(0, 2.6, 0)
	if p.sweets > 0:
		p.sweets -= 1
		kid.got_sweet(true)
		var roll := rng.randf()
		if roll < 0.1:
			p.score += 250
			_popup("TREAT: GOLDEN TOFFEE!  +250", Color(1, 0.85, 0.2), pos, 40)
			Audio.sting("unlock")
		elif roll < 0.4:
			p.score += 100
			_popup("TREAT: CHOCOLATE BAR!  +100", Color(1, 0.6, 0.2), pos, 36)
			Audio.sfx("chimes")
		elif roll < 0.7:
			w.boost(1.35, 8.0, false)
			_popup("TREAT: TOFFEE APPLE! Speed up!", Color(1, 0.4, 0.3), pos, 34)
			Audio.sfx("slurp")
		elif mode in ["career", "event", "coop"]:
			time_left += 8.0
			_popup("TREAT: +8 SECONDS ON THE CLOCK!", Color(0.5, 1, 0.8), pos, 34)
			Audio.sfx("ding", 1.2)
		else:
			w.boost(1.5, 5.0, true)
			_popup("TREAT: FIZZY SWEETS! ZOOM!", Color(0.4, 1, 0.4), pos, 34)
			Audio.sfx("slurp")
		return
	kid.got_sweet(false)
	if p.writing:
		_cancel_write(p, "")
	match rng.randi() % 4:
		0:
			p.score -= 30
			w.soak(3.0)
			_splash_fx(w.global_position + Vector3(0, 1.4, 0), Color(1, 0.9, 0.5, 0.95))
			_popup("TRICK: EGGED!  -30", Color(1, 0.9, 0.5), pos, 44)
			Audio.sfx("splash", 1.4)
		1:
			w.stun(2.0)
			_mummy_wrap(w, 2.0)
			_popup("TRICK: TOILET PAPERED!", Color(0.95, 0.95, 1), pos, 40)
			Audio.sfx("whoosh")
		2:
			w.stun(1.5)
			_popup("TRICK: LACES TIED TOGETHER!", Color(1, 0.6, 0.3), pos, 38)
			Audio.sfx("thud")
		_:
			p.score -= 50
			w.stun(1.0)
			_shake(p, 0.6)
			_popup("TRICK: BOO! JUMP SCARE  -50", Color(0.7, 1, 0.5), pos, 40)
			Audio.sfx("boing", 0.7)


func _mummy_wrap(w, seconds: float) -> void:
	var wrap := Node3D.new()
	w.add_child(wrap)
	for i in 6:
		var band := Util.torus(0.36, 0.5, Util.mat(Color(0.97, 0.97, 0.95), true), Vector3(0, 0.35 + i * 0.28, 0))
		band.rotation.z = 0.25 if i % 2 else -0.25
		wrap.add_child(band)
	get_tree().create_timer(seconds).timeout.connect(wrap.queue_free)


# ---------------------------------------------------------------- Christmas Eve: Santa's sleigh fly-over

func _update_flyover(delta: float) -> void:
	if not level.get("flyover", false):
		return
	if flyover == null:
		sleigh_timer -= delta
		if sleigh_timer <= 0.0:
			_start_flyover()
		return
	flyover.position += fly_dir * 15.0 * delta
	flyover.position.y = 7.0 + sin(elapsed * 2.0) * 0.5
	fly_drop -= delta
	var below := Vector3(flyover.position.x, 0, flyover.position.z)
	if fly_drop <= 0.0 and world.bounds.grow(-4.0).has_point(Vector2(below.x, below.z)):
		fly_drop = rng.randf_range(1.2, 2.2)
		_drop_present(world.random_walk_point(rng, below, 0.0, true) if not world.is_walkable(below) else below)
	if absf(flyover.position.x - focus.global_position.x) > 90.0:
		flyover.queue_free()
		flyover = null
		sleigh_timer = rng.randf_range(26.0, 38.0)


func _start_flyover() -> void:
	fly_dir = Vector3.RIGHT if rng.randf() < 0.5 else Vector3.LEFT
	var start: Vector3 = focus.global_position - fly_dir * 60.0
	start.z = focus.global_position.z + rng.randf_range(2.0, 5.0)
	flyover = Node3D.new()
	add_child(flyover)
	flyover.position = start + Vector3(0, 7, 0)
	flyover.rotation.y = 0.0 if fly_dir.x > 0.0 else PI
	fly_drop = 1.0
	var red := Util.mat(Color(0.85, 0.1, 0.1), true)
	var gold := Util.mat(Color(0.95, 0.8, 0.2))
	flyover.add_child(Util.box(Vector3(2.6, 0.9, 1.5), red, Vector3(0, 0.6, 0)))
	flyover.add_child(Util.box(Vector3(0.6, 1.2, 1.5), red, Vector3(-1.1, 1.1, 0)))
	for z in [-0.75, 0.75]:
		flyover.add_child(Util.box(Vector3(3.4, 0.08, 0.1), gold, Vector3(0.3, 0.05, z)))
	flyover.add_child(Util.sphere(0.6, Util.mat(Color(0.5, 0.3, 0.15), true), Vector3(-0.8, 1.6, 0)))
	# Santa
	flyover.add_child(Util.capsule(0.45, 1.0, red, Vector3(0.3, 1.4, 0)))
	flyover.add_child(Util.sphere(0.32, Util.mat(Color(1, 0.8, 0.7), true), Vector3(0.35, 2.15, 0)))
	flyover.add_child(Util.sphere(0.3, Util.mat(Color.WHITE, true), Vector3(0.5, 1.95, 0)))
	var hat := Util.cylinder(0.3, 0.55, red, Vector3(0.3, 2.55, 0), true, 0.02)
	flyover.add_child(hat)
	flyover.add_child(Util.sphere(0.12, Util.mat(Color.WHITE), Vector3(0.3, 2.85, 0)))
	for i in 4:
		var deer := Node3D.new()
		deer.position = Vector3(2.6 + (i / 2) * 1.8, 0.4, -0.5 + (i % 2) * 1.0)
		flyover.add_child(deer)
		var body := Util.capsule(0.25, 1.0, Util.mat(Color(0.55, 0.35, 0.2), true), Vector3(0, 0.5, 0))
		body.rotation.z = PI / 2
		deer.add_child(body)
		deer.add_child(Util.sphere(0.2, Util.mat(Color(0.55, 0.35, 0.2), true), Vector3(0.55, 0.85, 0)))
		deer.add_child(Util.sphere(0.08, Util.glow(Color(1, 0.1, 0.1), 3.0) if i >= 2 else Util.mat(Color(0.1, 0.1, 0.1)), Vector3(0.75, 0.85, 0)))
		for x in [-0.3, 0.3]:
			var antler := Util.cylinder(0.03, 0.4, Util.mat(Color(0.4, 0.28, 0.15)), Vector3(0.5 + x * 0.2, 1.15, 0))
			antler.rotation.z = x
			deer.add_child(antler)
	var label := Util.label3d("HO HO HO!", 60, Color(1, 0.3, 0.3), Vector3(0, 3.6, 0))
	flyover.add_child(label)
	Audio.voice("santa_hohoho", 1.0, 1.0, false)
	Audio.sfx("jingle")


func _drop_present(pos: Vector3) -> void:
	var box := Util.box(Vector3(0.6, 0.5, 0.6), Util.mat(Color(0.9, 0.15, 0.15), true), flyover.position)
	add_child(box)
	var tw := create_tween()
	tw.tween_property(box, "position", pos + Vector3(0, 0.6, 0), 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		box.queue_free()
		if state == "playing" and pickups.size() < 6:
			_add_pickup("present", pos)
			Audio.sfx("thud", 1.4, 0.6))


func _spawn_collectibles() -> void:
	## Golden Tickets: three hidden on each level, always in the same places
	var found: Array = Game.collectibles.get(level.id, [])
	var r := RandomNumberGenerator.new()
	r.seed = hash("golden" + level.id)
	var start := Vector3(level.start.x, 0, level.start.y)
	for i in COLLECTIBLES_PER_LEVEL:
		var pos: Vector3 = world.random_walk_point(r, start, 25.0)
		if i in found:
			continue
		var n := Node3D.new()
		n.position = pos + Vector3(0, 0.9, 0)
		add_child(n)
		n.add_child(Util.box(Vector3(0.9, 0.5, 0.06), Util.metal(Color(1, 0.8, 0.2), true), Vector3.ZERO))
		n.add_child(Util.label3d("TICKET", 22, Color(0.5, 0.3, 0.05), Vector3(0, 0, 0.05)))
		var sparkle := Util.label3d("*", 60, Color(1, 1, 0.7), Vector3(0.5, 0.4, 0))
		n.add_child(sparkle)
		collectibles.append({"node": n, "index": i})


func _update_collectibles(delta: float) -> void:
	for c in collectibles.duplicate():
		var n: Node3D = c.node
		n.rotation.y += delta * 2.5
		n.position.y = world.height_at(n.position) + 0.9 + sin(elapsed * 2.0 + c.index) * 0.2
		for w in all_wardens():
			if w.global_position.distance_to(Vector3(n.position.x, w.global_position.y, n.position.z)) < 1.4:
				collectibles.erase(c)
				n.queue_free()
				var found: Array = Game.collectibles.get(level.id, []).duplicate()
				found.append(c.index)
				Game.collectibles[level.id] = found
				Game.save_game()
				shift.collectibles += 1
				player_of(w).score += 200
				_popup("GOLDEN TICKET!  +200", Color(1, 0.85, 0.2), w.global_position + Vector3(0, 2.8, 0), 44)
				hud.banner("GOLDEN TICKET %d / %d FOUND" % [Game.collectible_count(), Levels.count() * COLLECTIBLES_PER_LEVEL], 1.6)
				Audio.sting("unlock")
				break


# ---------------------------------------------------------------- events from wardens, drivers, cars and the weather

func warden_punch(w) -> void:
	var p := player_of(w)
	if p.writing:
		_cancel_write(p, "")
	var wp: Dictionary = w.weapon
	var origin: Vector3 = w.punch_origin()
	var hit := false
	var words: Array = wp.words
	for d in get_tree().get_nodes_in_group("drivers"):
		if d.can_be_punched() and origin.distance_to(d.global_position) < float(wp.range):
			var chasing: bool = d.is_chasing()
			var floored: bool = d.punched(w.global_position, float(wp.knock))
			hit = true
			if floored:
				p.punches += 1
			_shake(p, 0.4)
			var pos: Vector3 = d.global_position + Vector3(0, 2.4, 0)
			_popup(words[rng.randi() % words.size()], Color(1, 0.95, 0.3), pos, 56)
			if chasing and floored:
				p.score += PUNCH_BONUS
				_popup("SELF DEFENCE  +%d" % PUNCH_BONUS, Color(0.5, 0.85, 1), pos + Vector3(0, -1.2, 0), 28)
			if chasing and wp.id == "printer":
				p.score += PRINTER_BONUS
				_popup("PRINTED A FINE  +%d" % PRINTER_BONUS, Color(1, 0.9, 0.5), pos + Vector3(0, -2.2, 0), 26)
			if wp.id == "walkie":
				_popup("BACKUP!", Color(0.6, 0.9, 1), w.global_position + Vector3(0, 3.0, 0), 36)
				Audio.voice("warden_backup")
				for other in get_tree().get_nodes_in_group("drivers"):
					if other != d and other.global_position.distance_to(w.global_position) < 10.0:
						other.startle(3.0)
			break
	if not hit:
		for ped in get_tree().get_nodes_in_group("pedestrians"):
			if ped.can_be_punched() and origin.distance_to(ped.global_position) < float(wp.range):
				ped.punched(w.global_position)
				hit = true
				_shake(p, 0.3)
				_popup(words[rng.randi() % words.size()], Color(1, 0.95, 0.3), ped.global_position + Vector3(0, 2.4, 0), 48)
				break
	if not hit and street_event != null and is_instance_valid(street_event):
		hit = street_event.punched(w, origin)
	if not hit:
		for c in get_tree().get_nodes_in_group("cars"):
			if origin.distance_to(c.global_position) < 2.6:
				c.punched(w.global_position)
				hit = true
				_shake(p, 0.2)
				_popup("BONK!", Color(1, 0.8, 0.4), c.global_position + Vector3(0, 2.4, 0), 40)
				break
	if hit:
		Audio.sfx("punch_hit" if wp.id != "fish" else "slap", rng.randf_range(0.9, 1.1))
		if rng.randf() < 0.3:
			Audio.voice("warden_hiyah")
	else:
		Audio.sfx("punch_swing", rng.randf_range(0.9, 1.15))


func on_heckled(_source, _w) -> void:
	heckles += 1


func on_pestered(ped, w) -> void:
	var p := player_of(w)
	if p.writing:
		_cancel_write(p, "")
	match ped.kind:
		"drunk":
			w.stun(1.2)
			_popup("BIG SLOPPY HUG!", Color(1, 0.6, 0.8), w.global_position + Vector3(0, 2.6, 0), 34)
		"geezer":
			p.score -= 50
			_popup("BOUGHT A DODGY WATCH  -50", Color(1, 0.5, 0.3), w.global_position + Vector3(0, 2.6, 0), 32)
			Audio.sfx("cash")
		"caroller":
			w.stun(1.5)
			_popup("FORCED TO SING ALONG!", Color(0.6, 1, 0.6), w.global_position + Vector3(0, 2.6, 0), 34)
		"elf":
			p.score -= 40
			_popup("ELF PUT YOU ON THE NAUGHTY LIST  -40", Color(0.4, 1, 0.4), w.global_position + Vector3(0, 2.6, 0), 30)
			Audio.sfx("chimes", 1.5)
		_:
			w.stun(1.0)
			_popup("FORCED TO DANCE!", Color(1, 0.6, 0.9), w.global_position + Vector3(0, 2.6, 0), 34)
	Audio.sfx("boing", 1.2)


func on_warden_hit(driver, w) -> void:
	var p := player_of(w)
	p.score -= HIT_PENALTY
	p.hit += 1
	_break_combo(p)
	if p.writing:
		_cancel_write(p, "")
	w.stun(STUN_TIME)
	_shake(p, 0.5)
	_popup("OOF!  -%d" % HIT_PENALTY, Color(1, 0.3, 0.25), driver.global_position + Vector3(0, 2.5, 0), 44)
	Audio.sfx("punch_hit", 0.8)
	Audio.sfx("boing")
	get_tree().create_timer(0.35).timeout.connect(func() -> void: Audio.voice("warden_oof"))


func on_close_call(pos: Vector3, w) -> void:
	var p := player_of(w)
	p.score += CLOSE_CALL_BONUS
	p.close_calls += 1
	shift.dodges += 1
	_popup("CLOSE CALL!  +%d" % CLOSE_CALL_BONUS, Color(0.5, 0.85, 1), pos + Vector3(0, 2.5, 0), 32)
	Audio.sfx("ding", 1.3, 0.7)


func on_splash(car, pos: Vector3) -> void:
	_splash_fx(pos)
	Audio.sfx("splash", rng.randf_range(0.9, 1.1))
	for w in all_wardens():
		if w.global_position.distance_to(pos) > 3.8:
			continue
		var p := player_of(w)
		if w.is_diving():
			p.score += CLOSE_CALL_BONUS
			shift.dodges += 1
			_popup("DODGED THE SPLASH!  +%d" % CLOSE_CALL_BONUS, Color(0.5, 0.85, 1), w.global_position + Vector3(0, 2.6, 0), 32)
		elif w.weapon_id == "brolly":
			p.score += CLOSE_CALL_BONUS
			_popup("BROLLY BLOCK!  +%d" % CLOSE_CALL_BONUS, Color(0.5, 0.85, 1), w.global_position + Vector3(0, 2.6, 0), 32)
		else:
			p.score -= SPLASH_PENALTY
			shift.splashes += 1
			w.soak(2.5)
			_shake(p, 0.3)
			_popup("SPLOOSH!  -%d" % SPLASH_PENALTY, Color(0.5, 0.7, 1), w.global_position + Vector3(0, 2.6, 0), 46)
			car.shout(["HAHA! SPLASHED YA!", "ENJOY YOUR BATH!", "OOPS! NOT SORRY!"][rng.randi() % 3])
			Audio.voice("heckle_splash", rng.randf_range(0.95, 1.1))


func _splash_fx(pos: Vector3, color := Color(0.6, 0.75, 1.0, 0.9)) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 60
	p.lifetime = 0.9
	p.explosiveness = 0.95
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	p.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	p.direction = Vector3(0, 1, 0)
	p.spread = 70.0
	p.initial_velocity_min = 5.0
	p.initial_velocity_max = 9.0
	p.gravity = Vector3(0, -20, 0)
	p.position = pos + Vector3(0, 0.2, 0)
	add_child(p)
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


## A lightning bolt hit the ground at pos (see weather.gd).
func on_lightning(pos: Vector3) -> void:
	_shake_all(0.6)
	for w in all_wardens():
		var d: float = w.global_position.distance_to(pos)
		var p := player_of(w)
		if d < 2.4 and w.can_be_hit():
			p.score -= 30
			shift.zaps += 1
			if p.writing:
				_cancel_write(p, "")
			w.stun(1.5)
			_popup("ZAPPED!  -30", Color(0.7, 0.9, 1), w.global_position + Vector3(0, 2.8, 0), 52)
			Audio.sfx("zap")
		elif d < 5.0:
			p.score += 50
			_popup("SHOCKINGLY CLOSE!  +50", Color(0.7, 0.9, 1), w.global_position + Vector3(0, 2.8, 0), 32)
	for c in get_tree().get_nodes_in_group("cars"):
		if c.global_position.distance_to(pos) < 4.0:
			c.honk_cooldown = 0.0
			c.honk()
			c.shout("WEE-OO WEE-OO!")
	for d in get_tree().get_nodes_in_group("drivers"):
		if d.global_position.distance_to(pos) < 3.0:
			d.punched(pos, 12.0)


func blow_whistle(w) -> void:
	_popup("PHWEEEET!" if Game.upgrade_level("megaphone") == 0 else "OI! YOU!", Color.WHITE, w.global_position + Vector3(0, 2.8, 0), 34)
	Audio.sfx("whistle", rng.randf_range(0.95, 1.05))
	for d in get_tree().get_nodes_in_group("drivers"):
		if d.global_position.distance_to(w.global_position) < w.whistle_range:
			d.startle(w.whistle_freeze)
	for ped in get_tree().get_nodes_in_group("pedestrians"):
		if ped.global_position.distance_to(w.global_position) < w.whistle_range:
			ped.shoo()
	if street_event != null and is_instance_valid(street_event):
		street_event.whistled(w)
	if wildlife != null:
		wildlife.whistled(w.global_position, w.whistle_range)


func _popup(text: String, color: Color, world_pos: Vector3, size := 36) -> void:
	for p in players:
		var cam: Camera3D = p.camera
		if cam.is_position_behind(world_pos):
			continue
		var sp := cam.unproject_position(world_pos)
		if players.size() > 1:
			if sp.x < 0.0 or sp.x > 640.0 or sp.y < 0.0 or sp.y > 720.0:
				continue
			sp += p.viewport_offset
		hud.popup(text, color, sp, size if players.size() == 1 else int(size * 0.8))


# ---------------------------------------------------------------- pause and flow

func set_paused(paused: bool) -> void:
	if state == "results":
		return
	get_tree().paused = paused
	hud.show_pause(paused)
	Audio.sfx("ui_select" if paused else "ui_back")


func restart() -> void:
	Game.reload_scene()


func next_level() -> void:
	Game.current_level = mini(Game.current_level + 1, Levels.count() - 1)
	Game.reload_scene()


func quit_to_menu() -> void:
	Game.change_scene("res://menu.tscn")


# ---------------------------------------------------------------- end of shift

func _end_shift() -> void:
	state = "results"
	for p in players:
		if p.writing:
			_cancel_write(p, "")
	for d in get_tree().get_nodes_in_group("drivers"):
		d.queue_free()
	Audio.sfx("whistle_long")
	Audio.voice("announce_shift_over")
	if training:
		# No scores or records for the tutorial: back to the menu, ready for Pleasant Street
		var passed_training := total_tickets() >= quota
		if passed_training:
			Game.training_done = true
		Game.training = false
		Game.save_game()
		hud.coach("")
		if not passed_training:
			hud.banner("TIME UP!\nTry Training Day again from the menu", 2.4, true)
		get_tree().create_timer(3.0).timeout.connect(quit_to_menu)
		return

	var score := total_score()
	var tickets := total_tickets()
	var passed := tickets >= quota
	if mode == "endless":
		passed = wave > 1
	elif mode == "race":
		passed = true
	var stars := 0
	if passed and mode in ["career", "event", "coop"]:
		var two_star := int(level.two_star) * (1.5 if mode == "coop" else 1.0)
		var three_star := int(level.three_star) * (1.5 if mode == "coop" else 1.0)
		stars = 1
		if score >= two_star:
			stars = 2
		if score >= three_star:
			stars = 3
	var board_id: String = {"career": level.id, "event": level.id, "endless": "endless", "coop": "coop", "race": "race"}[mode]
	var record_id: String = level.id if mode in ["career", "event"] else "%s_%s" % [mode, level.id]
	var prev_best: int = int(Game.best.get(record_id, {}).get("score", -999999))
	var shift_stats := {
		"tickets": tickets, "punches": _sum("punches"), "perfects": _sum("perfects"), "heckles": heckles,
		"close_calls": _sum("close_calls"), "waves": wave - 1 if mode == "endless" else 0,
	}
	for k in shift:
		shift_stats[k] = shift[k]
	Game.record_shift(record_id, score, stars, shift_stats, mode in ["career", "event"])
	var new_time := false
	if quota_time > 0.0 and mode in ["career", "event"]:
		if not Game.best_times.has(level.id) or quota_time < float(Game.best_times[level.id]):
			Game.best_times[level.id] = quota_time
			new_time = true
	if mode == "endless":
		Game.endless_best[level.id] = maxi(int(Game.endless_best.get(level.id, 0)), wave)
	var summary := shift_stats.duplicate()
	summary.merge({"passed": passed, "hit": _sum("hit"), "best_combo": _best_combo(), "score": score,
		"stars": stars, "wave": wave})
	var done: Array = Game.check_challenges(summary)
	var bonus_w := 0
	var bonus_x := 0
	for c in done:
		bonus_w += int(c.wages)
		bonus_x += int(c.xp)
	var pay: Dictionary = Game.pay(score, bonus_w, bonus_x)
	var unlocks: Array = Game.take_new_unlocks()
	Game.save_game()
	var has_next: bool = mode == "career" and Game.current_level + 1 < Levels.count() and Game.level_unlocked(Game.current_level + 1)
	var board_ok: bool = Game.board_qualifies(board_id, score) and mode != "race"
	var board_place := submit_score(board_id, _board_name()) if board_ok else -1
	var r := {
		"mode": mode, "passed": passed, "stars": stars, "tickets": tickets, "quota": quota, "score": score,
		"new_best": score > prev_best and prev_best > -999999, "perfects": _sum("perfects"), "best_combo": _best_combo(),
		"close_calls": _sum("close_calls"), "punches": _sum("punches"), "heckles": heckles, "wrong": _sum("wrong"),
		"hit": _sum("hit"), "unlocks": unlocks, "has_next": has_next, "wave": wave, "challenges": done, "pay": pay,
		"board": "", "board_place": board_place, "board_name": _board_name(), "quota_time": quota_time, "new_time": new_time,
		"medal": Game.best_time_medal(level.id, float(level.time)) if mode in ["career", "event"] else 0,
		"bosses": shift.bosses, "players": [],
	}
	for p in players:
		r.players.append({"score": p.score, "tickets": p.tickets, "punches": p.punches, "perfects": p.perfects})
	get_tree().create_timer(1.2).timeout.connect(func() -> void:
		Audio.stop_music(0.5)
		Audio.sting("win" if passed else "lose")
		if mode == "race":
			var a: int = r.players[0].tickets
			var b: int = r.players[1].tickets
			if a != b or r.players[0].score != r.players[1].score:
				var p1_wins: bool = a > b or (a == b and r.players[0].score > r.players[1].score)
				Audio.voice("announce_p1wins" if p1_wins else "announce_p2wins")
		if pay.rank_after > pay.rank_before:
			get_tree().create_timer(1.5).timeout.connect(func() -> void:
				Audio.sting("rankup")
				Audio.voice("announce_promoted"))
		elif not unlocks.is_empty() or not done.is_empty():
			get_tree().create_timer(2.5).timeout.connect(func() -> void: Audio.sting("unlock"))
		hud.show_results(r))


func _best_combo() -> float:
	var b := 1.0
	for p in players:
		b = maxf(b, p.best_combo)
	return b


## The name that goes on the score boards: the player profile(s) set in the menu.
func _board_name() -> String:
	var n1: String = Game.profile_name if Game.profile_name != "" else "WARDEN"
	if players.size() > 1:
		var n2: String = Game.profile2_name if Game.profile2_name != "" else "PLAYER 2"
		return "%s & %s" % [n1, n2]
	return n1


func submit_score(board_id: String, name: String) -> int:
	return Game.board_add(board_id, {
		"name": name, "score": total_score(), "level": level.name, "wave": wave,
		"date": Time.get_date_string_from_system(),
	})
