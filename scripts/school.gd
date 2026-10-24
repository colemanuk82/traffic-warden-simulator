extends RefCounted
## School Patrol: the lollipop ladies who stop the traffic at the crossings, and the kids who hop out
## of the school-run cars and run in through the school gate (crossing with a lollipop lady if the
## car stopped on the far side of the road). Nobody here can be punched or batted.

const Util := preload("res://scripts/util.gd")

const KID_BYE := ["Bye Mum!", "Bye Dad!", "See you later!", "Love you!", "Bye!", "See you at home time!"]
const LOLLIPOP_LINES := ["STOP! CHILDREN CROSSING!", "WAIT THERE, PLEASE!", "SLOW DOWN, DRIVER!", "MIND THE LITTLE ONES!",
	"THANK YOU, DRIVER!"]


static func spawn(main) -> void:
	var sc: Dictionary = main.level.get("school", {})
	for cr in sc.get("crossings", []):
		var l := Lollipop.new()
		l.main = main
		l.kerb = cr[0]
		l.mid = cr[1]
		main.add_child(l)


## Kids climb out of a school-run car and head for the gate.
static func drop_kids(main, car) -> void:
	var sc: Dictionary = main.level.get("school", {})
	if sc.is_empty():
		return
	var n: int = 1 + int(main.rng.randf() < 0.45)
	var gate: Vector2 = sc.gate
	var door: Vector3 = car.spot.pos + car.spot.normal * 1.3
	var school_side: bool = car.spot.pos.z * gate.y > 0.0  # parked on the same side of the road as the school
	for i in n:
		var k := Kid.new()
		k.main = main
		var start: Vector3 = door + car.spot.dir * (i * 0.8 - 0.4)
		var pave_z: float = gate.y + 3.5 if school_side else car.spot.pos.z + car.spot.normal.z * 3.5
		var path: Array[Vector3] = []
		if school_side:
			path.append(Vector3(start.x, 0, pave_z))
		else:
			# Walk along to the nearest crossing and wait for the lollipop lady
			var best = null
			for l in main.get_tree().get_nodes_in_group("road_blockers"):
				if best == null or absf(l.kerb.x - start.x) < absf(best.kerb.x - start.x):
					best = l
			if best == null:
				return
			k.crossing = best
			path.append(Vector3(start.x, 0, pave_z))
			path.append(Vector3(best.kerb.x + i * 0.7, 0, best.kerb.y))
			path.append(Vector3(best.kerb.x + i * 0.7, 0, gate.y + 3.5))
			k.wait_at = 2
		path.append(Vector3(gate.x + (i - 0.5) * 0.8, 0, gate.y + 1.0))
		path.append(Vector3(gate.x, 0, gate.y - 3.0))
		k.path = path
		k.position = start
		k.say_bye = i == 0
		k.delay = 0.3 + i * 0.35
		main.add_child(k)


## A lollipop lady: waits on the kerb, then walks out with her big STOP sign and holds the traffic
## while the children cross.
class Lollipop extends Node3D:
	var main
	var kerb := Vector2.ZERO
	var mid := Vector2.ZERO
	var state := "kerb"  # kerb, out, hold, back
	var wait := 0.0
	var hold := 0.0
	var walk_t := 0.0
	var visual: Node3D
	var sign: Node3D
	var shout_label: Label3D
	var speech_cd := 0.0

	func _ready() -> void:
		add_to_group("road_blockers")
		wait = randf_range(4.0, 10.0)
		position = Vector3(kerb.x, 0, kerb.y)
		visual = Node3D.new()
		add_child(visual)
		var coat := Util.mat(Color(0.97, 0.97, 0.95), true)
		var hivis := Util.mat(Color(1, 0.9, 0.1))
		for x in [-0.14, 0.14]:
			visual.add_child(Util.box(Vector3(0.18, 0.5, 0.18), Util.mat(Color(0.12, 0.12, 0.18), true), Vector3(x, 0.25, 0)))
		# Long white coat with yellow bands
		visual.add_child(Util.cylinder(0.42, 1.1, coat, Vector3(0, 0.95, 0), false, 0.3))
		visual.add_child(Util.cylinder(0.4, 0.12, hivis, Vector3(0, 0.75, 0), false, 0.38))
		visual.add_child(Util.cylinder(0.34, 0.12, hivis, Vector3(0, 1.15, 0), false, 0.32))
		visual.add_child(Util.sphere(0.36, Util.mat(Color(1.0, 0.82, 0.7), true), Vector3(0, 1.75, 0)))
		# Grey curls and a peaked cap
		for x in [-0.22, 0.0, 0.22]:
			visual.add_child(Util.sphere(0.15, Util.mat(Color(0.82, 0.82, 0.86)), Vector3(x, 1.72, -0.18)))
		visual.add_child(Util.cylinder(0.36, 0.22, Util.mat(Color(0.12, 0.15, 0.3), true), Vector3(0, 2.05, 0)))
		visual.add_child(Util.box(Vector3(0.5, 0.05, 0.3), Util.mat(Color(0.08, 0.08, 0.15)), Vector3(0, 1.96, 0.3)))
		visual.add_child(Util.box(Vector3(0.36, 0.06, 0.04), Util.mat(Color(0.05, 0.05, 0.05)), Vector3(0, 1.8, 0.34)))
		# The lollipop: a pole with a round STOP CHILDREN sign
		sign = Node3D.new()
		sign.position = Vector3(0.45, 0, 0.1)
		visual.add_child(sign)
		sign.add_child(Util.cylinder(0.04, 2.6, Util.mat(Color(0.95, 0.95, 0.95)), Vector3(0, 1.3, 0)))
		var disc := Util.cylinder(0.5, 0.05, Util.mat(Color(1, 0.88, 0.1), true), Vector3(0, 2.75, 0))
		disc.rotation.x = PI / 2
		sign.add_child(disc)
		var ring := Util.torus(0.36, 0.46, Util.mat(Color(0.85, 0.1, 0.1)), Vector3(0, 2.75, 0.04))
		ring.rotation.x = PI / 2
		sign.add_child(ring)
		var txt := Util.label3d("STOP\nCHILDREN", 22, Color(0.1, 0.1, 0.1), Vector3(0, 2.75, 0.06))
		txt.outline_size = 0
		sign.add_child(txt)
		shout_label = Util.label3d("", 40, Color(1, 0.9, 0.3), Vector3(0, 3.6, 0))
		add_child(shout_label)
		_face(Vector2(0, -1) if mid.y < kerb.y else Vector2(0, 1))

	func is_stopping_traffic() -> bool:
		var into := absf(position.z - mid.y)
		return state == "hold" or (state in ["out", "back"] and into < 4.5)

	func kids_waiting() -> bool:
		for k in get_tree().get_nodes_in_group("waiting_kids"):
			if k.crossing == self:
				return true
		return false

	func _process(delta: float) -> void:
		if main.state != "playing":
			return
		speech_cd -= delta
		var target := Vector3(kerb.x, 0, kerb.y)
		match state:
			"kerb":
				wait -= delta
				if wait <= 0.0 or (kids_waiting() and wait < 6.0):
					state = "out"
					_say(randi() % 4)
			"out":
				target = Vector3(mid.x, 0, mid.y)
				if _walk_to(target, 2.8, delta):
					state = "hold"
					hold = randf_range(3.5, 5.0)
			"hold":
				hold -= delta
				sign.rotation.z = sin(Time.get_ticks_msec() / 160.0) * 0.06
				if hold <= 0.0 and not kids_crossing():
					state = "back"
					if randf() < 0.5:
						_say(4)
			"back":
				if _walk_to(target, 2.8, delta):
					state = "kerb"
					wait = randf_range(9.0, 16.0)
					_face(Vector2(mid.x - kerb.x, mid.y - kerb.y))

	func kids_crossing() -> bool:
		for k in get_tree().get_nodes_in_group("crossing_kids"):
			if k.crossing == self:
				return true
		return false

	func _walk_to(target: Vector3, speed: float, delta: float) -> bool:
		var to := target - position
		to.y = 0.0
		if to.length() < 0.1:
			visual.position.y = 0.0
			return true
		var step := minf(speed * delta, to.length())
		position += to.normalized() * step
		position.y = main.world.height_at(position)
		_face(Vector2(to.x, to.z))
		walk_t += delta * 10.0
		visual.position.y = absf(sin(walk_t)) * 0.08
		return false

	func _face(d: Vector2) -> void:
		if d.length() > 0.01:
			visual.rotation.y = atan2(d.x, d.y)

	func _say(i: int) -> void:
		if speech_cd > 0.0:
			return
		speech_cd = 3.0
		shout_label.text = LOLLIPOP_LINES[i]
		shout_label.visible = true
		shout_label.scale = Vector3.ONE * 1.4
		var tw := create_tween()
		tw.tween_property(shout_label, "scale", Vector3.ONE, 0.15)
		tw.tween_interval(2.0)
		tw.tween_callback(func() -> void: shout_label.visible = false)
		if main.nearest_warden(global_position) != null and main.nearest_warden(global_position).global_position.distance_to(global_position) < 22.0:
			Audio.voice("lollipop_%d" % i, randf_range(0.97, 1.03), 0.9, false)

	func whistled(w) -> void:
		if w.global_position.distance_to(global_position) > w.whistle_range:
			return
		speech_cd = 0.0
		var line: String = ["OI! THAT'S MY JOB!", "CHEEKY!"][randi() % 2]
		shout_label.text = line
		shout_label.visible = true
		var tw := create_tween()
		tw.tween_interval(2.0)
		tw.tween_callback(func() -> void: shout_label.visible = false)
		Audio.voice("lollipop_whistled", 1.0, 0.9, false)
		speech_cd = 3.0


## A kid in school uniform with a backpack, trotting from the car to the school gate.
class Kid extends Node3D:
	var main
	var path: Array[Vector3] = []
	var crossing = null  # the lollipop lady who sees this kid across, if any
	var wait_at := -1  # index of the path point (the kerb) where the kid waits for the lollipop lady
	var delay := 0.3
	var say_bye := false
	var walk_t := 0.0
	var visual: Node3D
	var leg_l: Node3D
	var leg_r: Node3D
	var label: Label3D

	func _ready() -> void:
		visual = Node3D.new()
		visual.scale = Vector3.ONE * 0.62
		add_child(visual)
		var jumper: Color = [Color(0.55, 0.1, 0.18), Color(0.12, 0.2, 0.5), Color(0.15, 0.45, 0.25)][randi() % 3]
		var skin := Color.from_hsv(randf_range(0.04, 0.09), randf_range(0.25, 0.6), randf_range(0.45, 1.0))
		leg_l = Util.box(Vector3(0.2, 0.5, 0.2), Util.mat(Color(0.4, 0.4, 0.45), true), Vector3(-0.14, 0.25, 0))
		leg_r = Util.box(Vector3(0.2, 0.5, 0.2), Util.mat(Color(0.4, 0.4, 0.45), true), Vector3(0.14, 0.25, 0))
		visual.add_child(leg_l)
		visual.add_child(leg_r)
		visual.add_child(Util.capsule(0.34, 0.9, Util.mat(jumper, true), Vector3(0, 0.86, 0)))
		visual.add_child(Util.box(Vector3(0.12, 0.4, 0.04), Util.mat(Color.WHITE), Vector3(0, 1.05, 0.33)))
		visual.add_child(Util.sphere(0.42, Util.mat(skin, true), Vector3(0, 1.6, 0)))
		for x in [-0.14, 0.14]:
			visual.add_child(Util.sphere(0.06, Util.mat(Color(0.05, 0.05, 0.05)), Vector3(x, 1.66, 0.37)))
		var hair := Color.from_hsv(randf_range(0.02, 0.12), randf_range(0.4, 0.8), randf_range(0.12, 0.85))
		visual.add_child(Util.hemisphere(0.45, Util.mat(hair, true), Vector3(0, 1.68, -0.04)))
		# A big backpack
		var bag: Color = [Color(0.95, 0.3, 0.3), Color(0.3, 0.7, 1.0), Color(1, 0.8, 0.2), Color(0.7, 0.4, 0.9)][randi() % 4]
		visual.add_child(Util.box(Vector3(0.55, 0.6, 0.3), Util.mat(bag, true), Vector3(0, 1.0, -0.42)))
		label = Util.label3d("", 34, Color(0.6, 0.95, 1.0), Vector3(0, 1.9, 0))
		add_child(label)
		visual.visible = false

	func _process(delta: float) -> void:
		if main.state != "playing":
			return
		if delay > 0.0:
			delay -= delta
			if delay <= 0.0:
				visual.visible = true
				if say_bye:
					var i := randi() % KID_BYE.size()
					label.text = KID_BYE[i]
					var tw := create_tween()
					tw.tween_interval(2.0)
					tw.tween_callback(func() -> void: label.text = "")
					var w = main.nearest_warden(global_position)
					if w != null and w.global_position.distance_to(global_position) < 18.0:
						Audio.voice("kid_bye_%d" % i, randf_range(0.97, 1.05), 0.8, false)
			return
		if path.is_empty():
			queue_free()
			return
		# Wait at the kerb until the lollipop lady is holding the traffic
		if wait_at == 0:
			if crossing == null or not is_instance_valid(crossing) or crossing.state != "hold":
				add_to_group("waiting_kids")
				_idle(delta)
				return
			remove_from_group("waiting_kids")
			add_to_group("crossing_kids")
		var target: Vector3 = path[0]
		var to := target - position
		to.y = 0.0
		if to.length() < 0.15:
			path.pop_front()
			wait_at -= 1
			if wait_at < 0 and is_in_group("crossing_kids"):
				remove_from_group("crossing_kids")
			if path.size() == 1:
				# Through the gate and into school
				var tw := create_tween()
				tw.tween_property(visual, "scale", Vector3.ONE * 0.01, 0.6).set_delay(0.6)
			return
		var step := minf(3.2 * delta, to.length())
		position += to.normalized() * step
		position.y = main.world.height_at(position)
		visual.rotation.y = atan2(to.x, to.z)
		walk_t += delta * 16.0
		leg_l.rotation.x = sin(walk_t) * 0.7
		leg_r.rotation.x = -sin(walk_t) * 0.7
		visual.position.y = absf(sin(walk_t)) * 0.06

	func _idle(delta: float) -> void:
		walk_t += delta * 4.0
		leg_l.rotation.x = 0.0
		leg_r.rotation.x = 0.0
		visual.position.y = absf(sin(walk_t)) * 0.03
