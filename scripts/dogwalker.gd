extends Node3D
## Friendly locals walking their dogs along the pavements. The dog barks at the warden and
## wags its tail; the owner says hello. They're just scenery: you can't ticket a dog.

const Util := preload("res://scripts/util.gd")

const SPEED := 1.5
const LINES := ["Morning!", "Lovely day for it!", "He's friendly!", "Sit, Biscuit! SIT!", "Don't mind him!",
	"Busy day, officer?", "He just wants to say hello!", "Walkies!", "Good boy!"]

var main
var target := Vector3.ZERO
var pause_left := 0.0
var say_cd := 3.0
var walk_t := 0.0
var person: Node3D
var dog: Node3D
var tail: Node3D
var lead: MeshInstance3D
var label: Label3D
var dog_pos := Vector3.ZERO
var bark_left := 0.0


static func spawn_some(m, count: int) -> void:
	for i in count:
		var d = load("res://scripts/dogwalker.gd").new()
		d.main = m
		var p: Vector3 = m.world.random_walk_point(m.rng, m.warden.global_position if m.warden else Vector3.ZERO, 10.0, true)
		d.position = p
		m.add_child(d)


func _ready() -> void:
	var rng: RandomNumberGenerator = main.rng
	person = Node3D.new()
	add_child(person)
	var skin := Color.from_hsv(rng.randf_range(0.04, 0.09), rng.randf_range(0.3, 0.55), rng.randf_range(0.45, 1.0))
	var coat := [Color(0.25, 0.45, 0.3), Color(0.7, 0.35, 0.3), Color(0.3, 0.35, 0.6), Color(0.85, 0.7, 0.3),
		Color(0.55, 0.4, 0.6)][rng.randi() % 5] as Color
	for x in [-0.13, 0.13]:
		person.add_child(Util.box(Vector3(0.17, 0.5, 0.17), Util.mat(Color(0.25, 0.25, 0.35), true), Vector3(x, 0.25, 0)))
	person.add_child(Util.capsule(0.32, 0.9, Util.mat(coat, true), Vector3(0, 0.85, 0)))
	person.add_child(Util.sphere(0.34, Util.mat(skin, true), Vector3(0, 1.5, 0)))
	if rng.randf() < 0.5:
		# Woolly hat with a bobble
		person.add_child(Util.hemisphere(0.36, Util.mat(Color.from_hsv(rng.randf(), 0.6, 0.8), true), Vector3(0, 1.58, 0)))
		person.add_child(Util.sphere(0.1, Util.mat(Color.WHITE), Vector3(0, 1.97, 0)))
	else:
		person.add_child(Util.hemisphere(0.36, Util.mat(Color.from_hsv(rng.randf_range(0.0, 0.12), 0.5, rng.randf_range(0.15, 0.8)), true), Vector3(0, 1.6, -0.03)))
	for x in [-0.12, 0.12]:
		person.add_child(Util.sphere(0.045, Util.mat(Color(0.05, 0.05, 0.05)), Vector3(x, 1.55, 0.31)))
	_build_dog(rng)
	lead = Util.cylinder(0.02, 1.0, Util.mat(Color(0.8, 0.15, 0.15)))
	add_child(lead)
	label = Util.label3d("", 36, Color(0.85, 1.0, 0.85), Vector3(0, 2.4, 0))
	label.visible = false
	add_child(label)
	dog_pos = global_position + Vector3(1.2, 0, 0)
	target = main.world.random_walk_point(main.rng, global_position, 6.0, true)


func _build_dog(rng: RandomNumberGenerator) -> void:
	dog = Node3D.new()
	add_child(dog)
	dog.top_level = true
	var fur: Color = [Color(0.85, 0.65, 0.35), Color(0.15, 0.12, 0.1), Color(0.95, 0.92, 0.85), Color(0.55, 0.35, 0.2),
		Color(0.7, 0.7, 0.72)][rng.randi() % 5]
	var size := rng.randf_range(0.7, 1.15)
	var body := Util.capsule(0.22, 0.8, Util.mat(fur, true), Vector3(0, 0.42, 0) * size)
	body.rotation.x = PI / 2
	body.scale = Vector3.ONE * size
	dog.add_child(body)
	dog.add_child(Util.sphere(0.2 * size, Util.mat(fur, true), Vector3(0, 0.62, 0.42) * size))
	dog.add_child(Util.sphere(0.07 * size, Util.mat(Color(0.05, 0.05, 0.05)), Vector3(0, 0.6, 0.62) * size))
	for x in [-0.14, 0.14]:
		var ear := Util.sphere(0.08 * size, Util.mat(fur.darkened(0.3), true), Vector3(x, 0.75, 0.38) * size)
		ear.scale = Vector3(0.7, 1.4, 0.7)
		dog.add_child(ear)
		for z in [-0.22, 0.22]:
			dog.add_child(Util.cylinder(0.05 * size, 0.3 * size, Util.mat(fur.darkened(0.15)), Vector3(x * 0.8, 0.15, z) * size))
	tail = Node3D.new()
	tail.position = Vector3(0, 0.5, -0.4) * size
	dog.add_child(tail)
	var t := Util.cylinder(0.035, 0.35 * size, Util.mat(fur, true), Vector3(0, 0.15 * size, 0))
	tail.add_child(t)
	tail.rotation.x = -0.6
	# Collar
	dog.add_child(Util.torus(0.12 * size, 0.16 * size, Util.mat(Color(0.9, 0.15, 0.15)), Vector3(0, 0.6, 0.3) * size))


func _process(delta: float) -> void:
	if main.state == "results":
		return
	say_cd -= delta
	bark_left = maxf(bark_left - delta, 0.0)
	var w = main.nearest_warden(global_position)
	var near: bool = w != null and global_position.distance_to(w.global_position) < 4.5
	if pause_left > 0.0:
		pause_left -= delta
	else:
		var to := target - global_position
		to.y = 0.0
		if to.length() < 0.8:
			target = main.world.random_walk_point(main.rng, global_position, 8.0, true)
			if main.rng.randf() < 0.4:
				pause_left = main.rng.randf_range(1.5, 3.5)  # the dog has found a good smell
		else:
			var before := global_position
			var step := to.normalized() * SPEED * delta
			global_position = main.world.clamp_move(before, before + step)
			if global_position.distance_to(before) < step.length() * 0.2:
				target = main.world.random_walk_point(main.rng, global_position, 8.0, true)
			person.rotation.y = lerp_angle(person.rotation.y, atan2(to.x, to.z), 1.0 - exp(-8.0 * delta))
			walk_t += delta * 9.0
			person.position.y = absf(sin(walk_t)) * 0.08
	global_position.y = main.world.height_at(global_position)
	# The dog trots ahead on the lead, or turns to bark at the warden
	var ahead := global_position + Vector3(sin(person.rotation.y), 0, cos(person.rotation.y)) * 1.4 + Vector3(0.6, 0, 0)
	if near:
		ahead = global_position + (w.global_position - global_position).normalized() * 1.5
	dog_pos = dog_pos.lerp(ahead, 1.0 - exp(-4.0 * delta))
	dog_pos.y = main.world.height_at(dog_pos)
	var look: Vector3 = (w.global_position if near else ahead) - dog_pos
	look.y = 0.0
	dog.global_position = dog_pos + Vector3(0, absf(sin(walk_t * 1.6)) * 0.05 + (absf(sin(bark_left * 30.0)) * 0.12 if bark_left > 0.0 else 0.0), 0)
	if look.length() > 0.05:
		dog.rotation.y = lerp_angle(dog.rotation.y, atan2(look.x, look.z), 1.0 - exp(-8.0 * delta))
	tail.rotation.z = sin(Time.get_ticks_msec() * (0.03 if near else 0.012)) * 0.7
	# Lead from hand to collar
	var hand := global_position + Vector3(0, 0.9, 0) + Vector3(sin(person.rotation.y + 1.2), 0, cos(person.rotation.y + 1.2)) * 0.35
	var collar := dog.global_position + Vector3(0, 0.55, 0)
	var mid := (hand + collar) / 2.0
	var len := hand.distance_to(collar)
	lead.global_position = mid
	lead.scale = Vector3(1, maxf(len, 0.05), 1)
	if len > 0.01:
		var dir := (collar - hand) / len
		var axis := Vector3.UP.cross(dir)
		if axis.length() > 0.001:
			lead.global_basis = Basis(axis.normalized(), Vector3.UP.angle_to(dir)) * Basis.from_scale(Vector3(1, len, 1))
	if near and say_cd <= 0.0:
		say_cd = main.rng.randf_range(5.0, 9.0)
		bark_left = 0.6
		_say("WOOF! WOOF!" if main.rng.randf() < 0.5 else LINES[main.rng.randi() % LINES.size()])
		Audio.sfx("bark", main.rng.randf_range(0.85, 1.25), 0.8)


func _say(text: String) -> void:
	label.text = text
	label.visible = true
	label.scale = Vector3.ONE * 1.4
	var tw := create_tween()
	tw.tween_property(label, "scale", Vector3.ONE, 0.15)
	tw.tween_interval(2.0)
	tw.tween_callback(func() -> void: label.visible = false)
