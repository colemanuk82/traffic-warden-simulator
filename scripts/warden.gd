extends CharacterBody3D
## The player: walk, sprint (stamina), dive, whistle, punch. Gets stunned by angry drivers.
## In two player mode each warden reads its own actions ("p1_ticket"...); otherwise the plain ones.

const Util := preload("res://scripts/util.gd")
const CharacterScript := preload("res://scripts/character.gd")
const Career := preload("res://scripts/career.gd")

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.5
const ACCEL := 45.0
const DIVE_SPEED := 13.0
const DIVE_TIME := 0.35
const DIVE_RECOVER := 0.3
const STAMINA_MAX := 3.0
const STAMINA_REGEN := 0.9
const WHISTLE_COOLDOWN := 1.5
const BIKE_SPEED := 12.0

var main
var player := 0  # 0 single player, 1 or 2 in two player mode
var prefix := ""
var outfit: Dictionary
var weapon_id := "fists"
var weapon: Dictionary
var stamina_max := STAMINA_MAX
var speed_bonus := 1.0  # Turbo Shoes
var boost_timer := 0.0  # coffee / energy drink
var boost_mult := 1.0
var boost_free_stamina := false
var soak_timer := 0.0
var has_bike := false
var bike: Node3D
var whistle_range := 7.0
var whistle_freeze := 2.0
var stamina := STAMINA_MAX
var exhausted := false
var facing := Vector3(0, 0, -1)
var dive_timer := 0.0
var recover_timer := 0.0
var stun_timer := 0.0
var whistle_timer := 0.0
var punch_timer := 0.0
var locked := false
var speed_mult := 1.0  # weather: snow slows you down
var grip := 1.0  # weather: rain makes you slide
var visual: Node3D
var figure
var stars_label: Label3D


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.6
	shape.shape = cap
	shape.position = Vector3(0, 0.8, 0)
	add_child(shape)
	if player > 0:
		prefix = "p%d_" % player
	if outfit.is_empty():
		outfit = Game.outfit
	weapon = Career.weapon(weapon_id)
	speed_bonus = 1.0 + 0.07 * Game.upgrade_level("shoes")
	stamina_max = STAMINA_MAX + Game.upgrade_level("flask")
	stamina = stamina_max
	whistle_range = 7.0 + 2.5 * Game.upgrade_level("megaphone")
	whistle_freeze = 2.0 + 0.7 * Game.upgrade_level("megaphone")
	has_bike = Game.upgrade_level("bike") > 0 and Game.settings.get("bike", true)
	visual = Node3D.new()
	add_child(visual)
	figure = CharacterScript.new()
	visual.add_child(figure)
	figure.build(outfit)
	figure.set_weapon(weapon_id)
	figure.scale = Vector3.ONE * 1.2
	if has_bike:
		_build_bike()
	stars_label = Util.label3d("@ * @", 64, Color(1, 0.9, 0.2), Vector3(0, figure.height * 1.2 + 0.6, 0))
	stars_label.visible = false
	add_child(stars_label)
	visual.rotation.y = atan2(facing.x, facing.z)
	if player > 0:
		# A coloured ring so players can tell each other apart
		var ring := Util.torus(0.75, 0.95, Util.glow(Color(1, 0.85, 0.1) if player == 1 else Color(0.2, 0.7, 1.0), 1.5), Vector3(0, 0.06, 0))
		add_child(ring)
		var tag := Util.label3d("P%d" % player, 48, Color(1, 0.85, 0.1) if player == 1 else Color(0.3, 0.75, 1.0), Vector3(0, figure.height * 1.2 + 0.3, 0))
		add_child(tag)


func set_torch(on: bool) -> void:
	figure.set_torch(on)


func _build_bike() -> void:
	bike = Node3D.new()
	bike.visible = false
	visual.add_child(bike)
	var frame := Util.mat(Color(0.1, 0.45, 0.25), true)
	for z in [-0.6, 0.6]:
		var wheel := Util.torus(0.3, 0.38, Util.mat(Color(0.1, 0.1, 0.1), true), Vector3(0, 0.38, z))
		wheel.rotation.z = PI / 2
		bike.add_child(wheel)
	var bar := Util.box(Vector3(0.08, 0.08, 1.2), frame, Vector3(0, 0.6, 0))
	bike.add_child(bar)
	bike.add_child(Util.box(Vector3(0.08, 0.5, 0.08), frame, Vector3(0, 0.75, 0.5)))
	bike.add_child(Util.box(Vector3(0.6, 0.06, 0.06), Util.mat(Color(0.2, 0.2, 0.2)), Vector3(0, 1.0, 0.5)))
	bike.add_child(Util.box(Vector3(0.25, 0.08, 0.35), Util.mat(Color(0.1, 0.1, 0.1)), Vector3(0, 0.85, -0.35)))
	bike.add_child(Util.box(Vector3(0.4, 0.3, 0.3), Util.mat(Color(0.95, 0.85, 0.1), true), Vector3(0, 0.95, 0.8)))


func _act(name: String) -> String:
	return prefix + name


func pressed(name: String) -> bool:
	return Input.is_action_just_pressed(_act(name))


func _physics_process(delta: float) -> void:
	whistle_timer = maxf(whistle_timer - delta, 0.0)
	punch_timer = maxf(punch_timer - delta, 0.0)
	if boost_timer > 0.0:
		boost_timer -= delta
		if boost_timer <= 0.0:
			boost_mult = 1.0
			boost_free_stamina = false
	soak_timer = maxf(soak_timer - delta, 0.0)
	if main.state != "playing":
		velocity = Vector3.ZERO
		figure.animate(delta, 0.0)
		return

	if stun_timer > 0.0:
		stun_timer -= delta
		velocity = Vector3.ZERO
		visual.rotation.y += delta * 10.0
		stars_label.rotation.y += delta * 5.0
		stars_label.visible = stun_timer > 0.0
		_regen(delta)
		return

	if dive_timer > 0.0:
		dive_timer -= delta
		velocity = facing * DIVE_SPEED
		figure.body.rotation.x = deg_to_rad(80)
		figure.body.position.y = 0.35
		_move()
		if dive_timer <= 0.0:
			recover_timer = DIVE_RECOVER
		return

	if recover_timer > 0.0:
		recover_timer -= delta
		velocity = velocity.move_toward(Vector3.ZERO, ACCEL * delta)
		_move()
		if recover_timer <= 0.0:
			figure.body.rotation.x = 0.0
			figure.body.position.y = 0.0
		return

	var input := Input.get_vector(_act("move_left"), _act("move_right"), _act("move_up"), _act("move_down"))
	var dir := Vector3(input.x, 0, input.y)
	if locked:
		dir = Vector3.ZERO
	var moving := dir.length() > 0.1
	var sprinting := Input.is_action_pressed(_act("sprint")) and moving and not exhausted
	if sprinting:
		if not boost_free_stamina:
			stamina -= delta * (0.5 if has_bike else 1.0)
		if stamina <= 0.0:
			stamina = 0.0
			exhausted = true
	else:
		_regen(delta)
	if bike:
		bike.visible = sprinting
		figure.visible = true

	var top := (BIKE_SPEED if has_bike else SPRINT_SPEED) if sprinting else WALK_SPEED
	var speed: float = top * speed_mult * speed_bonus * boost_mult * main.ground_speed(global_position)
	if soak_timer > 0.0:
		speed *= 0.55
	velocity = velocity.move_toward(dir * speed, ACCEL * grip * delta)
	_move()
	if moving:
		facing = dir.normalized()

	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(facing.x, facing.z), 1.0 - exp(-15.0 * delta))
	figure.animate(delta, clampf(velocity.length() / SPRINT_SPEED, 0.0, 1.0) if moving or velocity.length() > 1.0 else 0.0)

	if pressed("dive"):
		_start_dive()
	elif pressed("punch") and punch_timer <= 0.0:
		punch_timer = float(weapon.cooldown)
		figure.punch()
		main.warden_punch(self)
	elif pressed("whistle") and whistle_timer <= 0.0 and not locked:
		whistle_timer = WHISTLE_COOLDOWN
		_squash()
		main.blow_whistle(self)
	elif pressed("gadget") and not locked:
		main.use_gadget(self)
	elif pressed("gadget_next"):
		main.next_gadget(self)


func _move() -> void:
	var before := global_position
	move_and_slide()
	position.y = main.world.height_at(position)
	global_position = main.world.clamp_move(before, global_position)


func _regen(delta: float) -> void:
	stamina = minf(stamina + STAMINA_REGEN * delta, stamina_max)
	if exhausted and stamina >= stamina_max * 0.4:
		exhausted = false


## Coffee or an energy drink: faster for a while (energy drinks also give free sprinting).
func boost(mult: float, seconds: float, free_stamina: bool) -> void:
	boost_mult = mult
	boost_timer = seconds
	boost_free_stamina = free_stamina
	stamina = stamina_max
	exhausted = false
	_squash()


func soak(seconds: float) -> void:
	soak_timer = seconds
	_squash()


func is_sprinting() -> bool:
	return velocity.length() > WALK_SPEED * speed_mult * speed_bonus * 1.15


func _start_dive() -> void:
	dive_timer = DIVE_TIME
	locked = false
	figure.body.rotation.z = 0.0
	visual.rotation.y = atan2(facing.x, facing.z)
	Audio.sfx("whoosh", randf_range(0.9, 1.1))


func _squash() -> void:
	var tw := create_tween()
	tw.tween_property(visual, "scale", Vector3(1.25, 0.75, 1.25), 0.07)
	tw.tween_property(visual, "scale", Vector3(0.9, 1.15, 0.9), 0.1)
	tw.tween_property(visual, "scale", Vector3.ONE, 0.12)


func stun(duration: float) -> void:
	stun_timer = duration
	dive_timer = 0.0
	recover_timer = 0.0
	velocity = Vector3.ZERO
	figure.body.rotation = Vector3.ZERO
	figure.body.position.y = 0.0
	stars_label.visible = true
	_squash()


func face_towards(point: Vector3) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length() > 0.1:
		facing = d.normalized()


func punch_origin() -> Vector3:
	return global_position + facing * 1.0


func can_be_hit() -> bool:
	return stun_timer <= 0.0 and dive_timer <= 0.0


func is_diving() -> bool:
	return dive_timer > 0.0


func is_busy() -> bool:
	return stun_timer > 0.0 or dive_timer > 0.0 or recover_timer > 0.0


func stamina_frac() -> float:
	return stamina / stamina_max
