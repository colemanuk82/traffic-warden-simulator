extends CharacterBody3D
## An angry driver who comes back after a ticket, chases the warden, then returns to the car.
## Can be punched: goes flying, sees stars, then limps back to the car.

const Util := preload("res://scripts/util.gd")

const CHASE_SPEED := 5.8
const WALK_SPEED := 3.5
const CHASE_TIME := 9.0
const HIT_RANGE := 1.0
const CLOSE_CALL_RANGE := 2.0
const KNOCK_TIME := 3.0
# [text bubble, voice group]
const SHOUTS := [
	["You what?!", "driver_what"], ["I was only here for a minute!", "driver_minute"],
	["Where else am I meant to park?!", "driver_where"], ["You're a chicken man!", "driver_chicken"],
	["Jobsworth!", "driver_jobsworth"], ["Come 'ere!", "driver_comehere"], ["I was only 2 minutes!", "driver_minutes"],
	["#@%&!", ""],
]
# Excuses for coming back to a ticketed car, mixed in with the shouts
const EXCUSES := [
	["I was only a minute!", "driver_x_aminute"], ["My phone didn't work, so I couldn't pay!", "driver_x_phone"],
	["I couldn't find a space!", "driver_x_space"], ["I park where I like, mate!", "driver_x_wherelike"],
	["I was only popping to the cash machine!", "driver_x_cashpoint"], ["The machine only takes coins!", "driver_x_coins"],
	["The parking app crashed!", "driver_x_app"], ["There weren't any signs!", "driver_x_signs"],
	["I didn't see any yellow lines!", "driver_x_yellow"], ["I was only dropping something off!", "driver_x_droppingoff"],
	["My hazards were on!", "driver_x_hazards"], ["I was coming straight back!", "driver_x_straightback"],
	["Everyone else parks here!", "driver_x_everyone"], ["I've parked here for twenty years!", "driver_x_years"],
	["I was desperate for the loo!", "driver_x_loo"], ["I was only buying a sandwich!", "driver_x_sandwich"],
	["It's not even my car!", "driver_x_notmine"], ["I'm appealing that!", "driver_x_appeal"],
	["Have a heart, it's my birthday!", "driver_x_birthday"], ["Do you know who I am?!", "driver_x_whoami"],
	["I pay my road tax, you know!", "driver_x_roadtax"], ["I was helping my nan with her shopping!", "driver_x_nan"],
	["I got lost looking for the car park!", "driver_x_lost"], ["I was just getting change!", "driver_x_change"],
]
# Recently used excuses, so the same one doesn't come round again too soon
static var _recent_excuses: Array = []


## A random excuse that none of the last few drivers used.
static func pick_excuse() -> Array:
	var fresh := EXCUSES.filter(func(e: Array) -> bool: return not e[1] in _recent_excuses)
	var line: Array = fresh[randi() % fresh.size()]
	_recent_excuses.append(line[1])
	if _recent_excuses.size() > EXCUSES.size() / 2:
		_recent_excuses.pop_front()
	return line


const SANTA_SHOUTS := [["HO HO NO!", "santa_hohoho"], ["Naughty list for YOU!", "santa_naughty"],
	["I've got a schedule to keep!", "santa_naughty"]]

var main
var car
var target  # the warden being chased
var hp := 1  # punches needed to floor them (White Van Man takes two)
var bodyguard := false
var santa := false  # Christmas Eve: Santa himself, after you ticket his sleigh
var chase_speed := CHASE_SPEED
var state := "chase"  # chase, return, knocked
var chase_left := CHASE_TIME
var startle_left := 0.0
var knock_left := 0.0
var knock_vel := Vector3.ZERO
var knock_y := 0.0
var knock_vy := 0.0
var shout_timer := 0.5
var close_call_ready := true
var walk_t := 0.0
var pitch := 1.0
var female := false
var visual: Node3D
var shout_label: Label3D
var stars_label: Label3D


func _ready() -> void:
	add_to_group("drivers")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 4
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	shape.shape = cap
	shape.position = Vector3(0, 0.8, 0)
	add_child(shape)
	pitch = randf_range(0.96, 1.06)
	female = not (bodyguard or santa or hp > 1) and randf() < 0.5

	visual = Node3D.new()
	add_child(visual)
	var dark := Color(0.2, 0.15, 0.15)
	var shirt := Color.from_hsv(randf(), 0.6, 0.85)
	var skin := Color(1.0, 0.55, 0.5)  # red with rage
	if bodyguard:
		shirt = Color(0.08, 0.08, 0.1)
		dark = Color(0.05, 0.05, 0.07)
	elif santa:
		shirt = Color(0.85, 0.1, 0.1)
		dark = Color(0.08, 0.08, 0.08)
		skin = Color(1.0, 0.75, 0.68)
	elif hp > 1:
		shirt = Color(0.95, 0.95, 0.95)
	visual.add_child(Util.box(Vector3(0.18, 0.5, 0.18), Util.mat(dark, true), Vector3(-0.14, 0.25, 0)))
	visual.add_child(Util.box(Vector3(0.18, 0.5, 0.18), Util.mat(dark, true), Vector3(0.14, 0.25, 0)))
	visual.add_child(Util.capsule(0.35, 0.95, Util.mat(shirt, true), Vector3(0, 0.88, 0)))
	for side in [-1.0, 1.0]:
		var arm := Util.capsule(0.09, 0.55, Util.mat(shirt, true), Vector3(side * 0.42, 1.05, 0.1))
		arm.rotation.z = side * 2.4  # arms up in fury
		visual.add_child(arm)
	visual.add_child(Util.sphere(0.4, Util.mat(skin, true), Vector3(0, 1.6, 0)))
	visual.add_child(Util.box(Vector3(0.18, 0.05, 0.05), Util.mat(dark), Vector3(-0.15, 1.78, 0.37)))
	visual.add_child(Util.box(Vector3(0.18, 0.05, 0.05), Util.mat(dark), Vector3(0.15, 1.78, 0.37)))
	visual.add_child(Util.hemisphere(0.42, Util.mat(Color.from_hsv(randf_range(0, 0.1), 0.6, randf_range(0.1, 0.5)), true), Vector3(0, 1.66, -0.04)))
	if female:
		# Longer hair down the back and a bit of lipstick so you can tell who's shouting
		var hair_col := Color.from_hsv(randf_range(0.02, 0.12), randf_range(0.4, 0.8), randf_range(0.15, 0.9))
		visual.add_child(Util.box(Vector3(0.7, 0.55, 0.22), Util.mat(hair_col, true), Vector3(0, 1.42, -0.26)))
		visual.add_child(Util.box(Vector3(0.14, 0.04, 0.04), Util.mat(Color(0.85, 0.1, 0.25)), Vector3(0, 1.45, 0.39)))
	if bodyguard:
		visual.add_child(Util.box(Vector3(0.6, 0.12, 0.06), Util.mat(Color(0.02, 0.02, 0.02)), Vector3(0, 1.7, 0.38)))
		visual.add_child(Util.box(Vector3(0.12, 0.3, 0.05), Util.mat(Color(0.9, 0.1, 0.1)), Vector3(0, 1.1, 0.35)))
	elif santa:
		visual.add_child(Util.sphere(0.36, Util.mat(Color.WHITE, true), Vector3(0, 1.42, 0.16)))
		visual.add_child(Util.box(Vector3(0.75, 0.12, 0.72), Util.mat(Color(0.1, 0.1, 0.1)), Vector3(0, 0.75, 0)))
		visual.add_child(Util.cylinder(0.36, 0.6, Util.mat(Color(0.85, 0.1, 0.1), true), Vector3(0, 2.1, 0), false, 0.03))
		visual.add_child(Util.cylinder(0.43, 0.14, Util.mat(Color.WHITE), Vector3(0, 1.86, 0)))
		visual.add_child(Util.sphere(0.13, Util.mat(Color.WHITE), Vector3(0, 2.44, 0)))
	elif hp > 1:
		# White Van Man: builder's belly, tiny shorts energy and a pencil behind the ear
		visual.add_child(Util.sphere(0.42, Util.mat(Color(0.95, 0.95, 0.95), true), Vector3(0, 0.85, 0.12)))
		visual.add_child(Util.cylinder(0.025, 0.3, Util.mat(Color(1, 0.8, 0.1)), Vector3(0.38, 1.7, 0)))
	shout_label = Util.label3d("", 44, Color(1, 0.35, 0.3), Vector3(0, 2.8, 0))
	add_child(shout_label)
	stars_label = Util.label3d("@ * @", 60, Color(1, 0.9, 0.2), Vector3(0, 2.3, 0))
	stars_label.visible = false
	add_child(stars_label)


func _physics_process(delta: float) -> void:
	if main.state != "playing":
		velocity = Vector3.ZERO
		return
	if state == "knocked":
		_update_knocked(delta)
		return
	if startle_left > 0.0:
		startle_left -= delta
		visual.rotation.z = sin(startle_left * 30.0) * 0.2
		return
	visual.rotation.z = 0.0

	var target_pos: Vector3
	var speed := chase_speed
	if state == "chase":
		chase_left -= delta
		shout_timer -= delta
		if shout_timer <= 0.0:
			shout_timer = randf_range(1.8, 2.8)
			var pool: Array = SHOUTS
			if santa:
				pool = SANTA_SHOUTS
			elif main.level.has("driver_shouts") and randf() < 0.5:
				pool = main.level.driver_shouts
			var line: Array = pool[randi() % pool.size()]
			if pool == SHOUTS and randf() < 0.65:
				line = pick_excuse()
			if line[1] == "driver_oi" and car != null and is_instance_valid(car) and car.kind == "motorbike":
				line = ["Hey, that's my bike!", "driver_bike"]
			shout(line[0])
			if line[1] != "":
				Audio.voice(line[1], pitch, 1.0, false, int(female))
		if target == null or not is_instance_valid(target):
			target = main.nearest_warden(global_position)
		target_pos = target.global_position
		if chase_left <= 0.0:
			_give_up("Hmph!")
	else:
		if not is_instance_valid(car) or bodyguard:
			queue_free()
			return
		target_pos = car.spot.pos + car.spot.normal * 1.6
		speed = WALK_SPEED
		if global_position.distance_to(target_pos) < 0.8:
			car.driver_returned()
			queue_free()
			return

	var to := target_pos - global_position
	to.y = 0.0
	velocity = to.normalized() * speed if to.length() > 0.05 else Vector3.ZERO
	var before := global_position
	move_and_slide()
	position.y = main.world.height_at(position)
	if state == "chase":
		global_position = main.world.clamp_move(before, global_position)
	if velocity.length() > 0.1:
		visual.rotation.y = atan2(velocity.x, velocity.z)
		walk_t += delta * 14.0
		visual.position.y = absf(sin(walk_t)) * 0.15

	if state == "chase":
		for w in main.all_wardens():
			var d: float = global_position.distance_to(w.global_position)
			if d < HIT_RANGE and w.can_be_hit():
				main.on_warden_hit(self, w)
				_give_up("Ha! Take that!")
				Audio.voice("driver_takethat", pitch, 1.0, true, int(female))
				break
			elif d < CLOSE_CALL_RANGE and close_call_ready and w.is_diving():
				close_call_ready = false
				main.on_close_call(global_position, w)


func _update_knocked(delta: float) -> void:
	knock_left -= delta
	if knock_y > 0.0 or knock_vy > 0.0:
		knock_vy -= 30.0 * delta
		knock_y = maxf(knock_y + knock_vy * delta, 0.0)
		visual.rotation.x = lerpf(visual.rotation.x, -PI / 2.0, 1.0 - exp(-10.0 * delta))
		visual.rotation.y += delta * 12.0
		if knock_y <= 0.0 and knock_vy < 0.0:
			knock_vy = 0.0
			Audio.sfx("thud", randf_range(0.9, 1.1), 0.8)
	knock_vel = knock_vel.move_toward(Vector3.ZERO, 14.0 * delta)
	velocity = knock_vel
	var before := global_position
	move_and_slide()
	global_position = main.world.clamp_move(before, Vector3(global_position.x, main.world.height_at(global_position), global_position.z))
	visual.position.y = knock_y
	stars_label.rotation.y += delta * 5.0
	if knock_left <= 0.0:
		visual.rotation.x = 0.0
		visual.position.y = 0.0
		stars_label.visible = false
		state = "return"
		shout("I'm telling my mum!")


## Returns true if that punch floored them.
func punched(from: Vector3, knock := 14.0) -> bool:
	var away := global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3(0, 0, 1)
	hp -= 1
	if hp > 0:
		# Shrugs it off, staggers back and gets angrier
		var tw := create_tween()
		tw.tween_property(self, "global_position", global_position + away * 1.5, 0.15)
		tw.parallel().tween_property(visual, "rotation:x", -0.5, 0.1)
		tw.tween_property(visual, "rotation:x", 0.0, 0.2)
		startle_left = 0.5
		chase_speed += 0.6
		chase_left = maxf(chase_left, 5.0)
		shout(["IS THAT ALL YOU'VE GOT?", "TICKLES!", "LEAVE IT OUT!"][randi() % 3])
		return false
	state = "knocked"
	knock_left = KNOCK_TIME
	knock_vel = away * knock
	knock_vy = 9.0 * knock / 14.0
	knock_y = 0.01
	startle_left = 0.0
	stars_label.visible = true
	shout(["OW!", "MY NOSE!", "OOOF!", "NOT THE FACE!"][randi() % 4])
	Audio.voice("punched", pitch, 1.0, true, int(female))
	return true


func is_chasing() -> bool:
	return state == "chase"


func can_be_punched() -> bool:
	return state != "knocked"


func _give_up(text: String) -> void:
	state = "return"
	shout(text)


func shout(text: String) -> void:
	shout_label.text = text
	shout_label.scale = Vector3.ONE * 1.4
	var tw := create_tween()
	tw.tween_property(shout_label, "scale", Vector3.ONE, 0.15)


func startle(duration: float) -> void:
	if state == "knocked":
		return
	startle_left = duration
	shout("?!")
