extends Node3D
## A random bit of street chaos during a shift: a flock of pigeons to scatter, a runaway shopping
## trolley to stop, or an ice cream van to chase down for a 99 Flake.

const Util := preload("res://scripts/util.gd")
const CarScript := preload("res://scripts/car.gd")

var main
var kind := "pigeons"
var life := 25.0
var done := false
var pigeons: Array[Node3D] = []
var scattered := false
var trolley: Node3D
var trolley_dir := Vector3.RIGHT
var trolley_end := 0.0
var trolley_t := 0.0
var trolley_stopped := false
var trolley_vel := Vector3.ZERO
var van = null
var near_time := 0.0
var chime_timer := 0.0
var label: Label3D
var close_ready := true


func _ready() -> void:
	match kind:
		"pigeons":
			_start_pigeons()
		"trolley":
			_start_trolley()
		"icecream":
			_start_icecream()


func _start_pigeons() -> void:
	global_position = main.world.random_walk_point(main.rng, main.warden.global_position, 12.0, true)
	for i in 12:
		var b := Node3D.new()
		b.position = Vector3(main.rng.randf_range(-2.5, 2.5), 0, main.rng.randf_range(-2.5, 2.5))
		b.rotation.y = main.rng.randf() * TAU
		add_child(b)
		var grey := Util.mat(Color(0.55, 0.57, 0.63), true)
		var body := Util.sphere(0.2, grey, Vector3(0, 0.22, 0))
		body.scale = Vector3(0.9, 0.85, 1.3)
		b.add_child(body)
		b.add_child(Util.sphere(0.12, Util.mat(Color(0.35, 0.5, 0.45), true), Vector3(0, 0.42, 0.18)))
		var beak := Util.cylinder(0.04, 0.1, Util.mat(Color(0.95, 0.7, 0.3)), Vector3(0, 0.41, 0.31), false, 0.0)
		beak.rotation.x = PI / 2
		b.add_child(beak)
		pigeons.append(b)
	label = Util.label3d("PIGEONS! Scare them off!", 40, Color(0.8, 0.9, 1.0), Vector3(0, 2.4, 0))
	add_child(label)
	main.hud.banner("A FLOCK OF PIGEONS!\nRun through them or whistle", 1.8)
	Audio.sfx("coo")


func _start_trolley() -> void:
	life = 14.0
	# Roll along the longest pavement
	var best: Rect2 = main.world.walk_rects[0]
	for w in main.world.walk_rects:
		if maxf(w.size.x, w.size.y) > maxf(best.size.x, best.size.y) and main.rng.randf() < 0.7:
			best = w
	var horizontal := best.size.x > best.size.y
	var forward: bool = main.rng.randf() < 0.5
	if horizontal:
		var z: float = best.position.y + best.size.y * main.rng.randf_range(0.2, 0.8)
		global_position = Vector3(best.position.x + 1.0 if forward else best.end.x - 1.0, 0, z)
		global_position.y = main.world.height_at(global_position)
		trolley_dir = Vector3.RIGHT if forward else Vector3.LEFT
		trolley_end = best.size.x - 2.0
	else:
		var x: float = best.position.x + best.size.x * main.rng.randf_range(0.2, 0.8)
		global_position = Vector3(x, 0, best.position.y + 1.0 if forward else best.end.y - 1.0)
		global_position.y = main.world.height_at(global_position)
		trolley_dir = Vector3.BACK if forward else Vector3.FORWARD
		trolley_end = best.size.y - 2.0
	trolley = Node3D.new()
	add_child(trolley)
	trolley.rotation.y = atan2(trolley_dir.x, trolley_dir.z)
	var metal := Util.metal(Color(0.75, 0.75, 0.8))
	trolley.add_child(Util.box(Vector3(0.9, 0.6, 1.3), metal, Vector3(0, 0.75, 0)))
	trolley.add_child(Util.box(Vector3(0.95, 0.06, 0.06), Util.mat(Color(0.9, 0.1, 0.1)), Vector3(0, 1.15, -0.7)))
	for x in [-0.4, 0.4]:
		for z in [-0.55, 0.55]:
			trolley.add_child(Util.sphere(0.09, Color(0.1, 0.1, 0.1), Vector3(x, 0.09, z)))
	trolley.add_child(Util.sphere(0.25, Color(1, 0.6, 0.2), Vector3(0.1, 1.0, 0.2), true))
	trolley.add_child(Util.box(Vector3(0.3, 0.3, 0.3), Color(0.3, 0.6, 0.9), Vector3(-0.15, 1.0, -0.2), true))
	label = Util.label3d("RUNAWAY TROLLEY!", 44, Color(1, 0.7, 0.3), Vector3(0, 2.2, 0))
	trolley.add_child(label)
	main.hud.banner("RUNAWAY TROLLEY!\nPunch it to stop it, or dive out of the way", 1.8)
	Audio.sfx("rattle")


func _start_icecream() -> void:
	life = 40.0
	van = CarScript.new()
	van.main = main
	van.kind = "icecream"
	van.lane = main.world.lanes[main.rng.randi() % main.world.lanes.size()]
	main.cars_root.add_child(van)
	main.hud.banner("ICE CREAM VAN!\nKeep up with it for a 99 Flake", 1.8)
	chime_timer = 0.0


func _process(delta: float) -> void:
	if done or main.state != "playing":
		return
	life -= delta
	match kind:
		"pigeons":
			_update_pigeons(delta)
		"trolley":
			_update_trolley(delta)
		"icecream":
			_update_icecream(delta)


func _update_pigeons(delta: float) -> void:
	if scattered:
		for b in pigeons:
			b.position += Vector3(sin(b.rotation.y), 1.4, cos(b.rotation.y)) * delta * 6.0
		return
	for b in pigeons:
		b.position.y = absf(sin(Time.get_ticks_msec() * 0.008 + b.rotation.y * 3.0)) * 0.08
		b.rotation.x = sin(Time.get_ticks_msec() * 0.01 + b.rotation.y) * 0.3
	for w in main.all_wardens():
		if w.global_position.distance_to(global_position) < 2.8:
			_scatter(w)
			return
	if life <= 0.0:
		_scatter(null)


func _scatter(w) -> void:
	scattered = true
	label.text = "COO! COO!"
	Audio.sfx("flap")
	_finish(w, 100, "PIGEON PANIC!", 2.0)


func whistled(w) -> void:
	if kind == "pigeons" and not scattered and w.global_position.distance_to(global_position) < w.whistle_range + 2.0:
		_scatter(w)


func _update_trolley(delta: float) -> void:
	if trolley_stopped:
		trolley_vel = trolley_vel.move_toward(Vector3.ZERO, 12.0 * delta)
		trolley.position += trolley_vel * delta
		trolley.rotation.z += delta * 6.0 * trolley_vel.length() / 10.0
		return
	trolley_t += delta * 6.5
	trolley.position = trolley_dir * trolley_t
	trolley.position.y = main.world.height_at(global_position + trolley.position) - global_position.y
	trolley.rotation.z = sin(trolley_t * 3.0) * 0.06
	var tp: Vector3 = trolley.global_position
	for w in main.all_wardens():
		var d: float = w.global_position.distance_to(tp)
		if d < 1.1 and w.can_be_hit():
			w.stun(1.5)
			var p = main.player_of(w)
			p.score -= 25
			main._popup("CLATTER!  -25", Color(1, 0.4, 0.3), w.global_position + Vector3(0, 2.6, 0), 44)
			Audio.sfx("thud")
			Audio.sfx("rattle", 1.3)
			_finish(null, 0, "", 0.5)
			trolley_stopped = true
			trolley_vel = trolley_dir * 3.0
			return
		elif d < 2.2 and w.is_diving() and close_ready:
			close_ready = false
			main.on_close_call(tp, w)
	if trolley_t >= trolley_end or life <= 0.0:
		Audio.sfx("thud", 0.8)
		label.text = "CRASH!"
		_finish(null, 0, "", 1.5)


func punched(w, origin: Vector3) -> bool:
	if kind != "trolley" or trolley_stopped or done:
		return false
	if origin.distance_to(trolley.global_position) > float(w.weapon.range) + 0.5:
		return false
	trolley_stopped = true
	trolley_vel = (trolley.global_position - w.global_position).normalized() * 8.0
	trolley_vel.y = 0.0
	label.text = "STOPPED!"
	_finish(w, 150, "TROLLEY STOPPED!", 2.0)
	return true


func _update_icecream(delta: float) -> void:
	if not is_instance_valid(van):
		_finish(null, 0, "", 0.0)
		return
	global_position = van.global_position
	chime_timer -= delta
	if chime_timer <= 0.0:
		chime_timer = 3.0
		var w = main.nearest_warden(global_position)
		if w and w.global_position.distance_to(global_position) < 30.0:
			Audio.sfx("chimes", 1.0, 0.6)
	for w in main.all_wardens():
		if w.global_position.distance_to(van.global_position) < 4.0:
			near_time += delta
			if near_time >= 1.5:
				w.boost(1.35, 10.0, true)
				van.shout("ONE 99 FLAKE!")
				_finish(w, 100, "99 FLAKE! SUGAR RUSH!", 0.0)
				return


func _finish(w, points: int, text: String, linger: float) -> void:
	if done:
		return
	done = true
	if w != null:
		main.on_street_event_done(self, w, points, text)
	var tw := create_tween()
	tw.tween_interval(linger)
	tw.tween_callback(queue_free)
