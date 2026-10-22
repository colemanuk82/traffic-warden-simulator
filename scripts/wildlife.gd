extends Node3D
## Garden birds and street cats: pure scenery that reacts to the warden.
## Birds peck about on the pavements and in the parks and take off when you run at them or whistle.
## Cats sit on garden walls, wash, nap and wander; walk up slowly for a stroke and a purr, or
## sprint past and they hiss and bolt. Themed per level: gulls by the sea, crows and black cats on
## Halloween, robins in the snow.

const Util := preload("res://scripts/util.gd")

const SPECIES := {
	"sparrow": {"body": Color(0.55, 0.4, 0.28), "belly": Color(0.82, 0.74, 0.6), "head": Color(0.45, 0.35, 0.3), "beak": Color(0.25, 0.22, 0.2), "size": 0.8, "call": "chirp"},
	"blackbird": {"body": Color(0.08, 0.08, 0.09), "belly": Color(0.12, 0.12, 0.13), "head": Color(0.08, 0.08, 0.09), "beak": Color(1.0, 0.6, 0.1), "size": 1.0, "call": "chirp2"},
	"robin": {"body": Color(0.45, 0.36, 0.25), "belly": Color(0.95, 0.4, 0.15), "head": Color(0.45, 0.36, 0.25), "beak": Color(0.2, 0.18, 0.15), "size": 0.8, "call": "chirp"},
	"bluetit": {"body": Color(0.45, 0.6, 0.35), "belly": Color(1.0, 0.85, 0.2), "head": Color(0.2, 0.45, 0.9), "beak": Color(0.15, 0.15, 0.15), "size": 0.7, "call": "chirp2"},
	"magpie": {"body": Color(0.06, 0.06, 0.08), "belly": Color(0.97, 0.97, 0.97), "head": Color(0.06, 0.06, 0.08), "beak": Color(0.1, 0.1, 0.1), "size": 1.3, "call": "caw"},
	"crow": {"body": Color(0.07, 0.07, 0.1), "belly": Color(0.1, 0.1, 0.13), "head": Color(0.07, 0.07, 0.1), "beak": Color(0.12, 0.12, 0.12), "size": 1.4, "call": "caw"},
	"gull": {"body": Color(0.75, 0.77, 0.8), "belly": Color(0.98, 0.98, 0.98), "head": Color(0.98, 0.98, 0.98), "beak": Color(1.0, 0.8, 0.15), "size": 1.6, "call": "gull"},
}
const CAT_COATS := [
	[Color(0.95, 0.55, 0.2), Color(1.0, 0.85, 0.65)],  # ginger
	[Color(0.1, 0.1, 0.12), Color(0.1, 0.1, 0.12)],  # black
	[Color(0.5, 0.5, 0.52), Color(0.75, 0.75, 0.78)],  # grey tabby
	[Color(0.97, 0.97, 0.95), Color(0.97, 0.97, 0.95)],  # white
	[Color(0.12, 0.12, 0.14), Color(0.97, 0.97, 0.97)],  # black and white
	[Color(0.55, 0.38, 0.25), Color(0.85, 0.72, 0.55)],  # brown tabby
]
const STROKE_POINTS := 25

var main
var flocks: Array = []
var cats: Array = []
var flyover_timer := 25.0
var flyovers: Array = []


static func spawn(m) -> Node3D:
	var w = load("res://scripts/wildlife.gd").new()
	w.main = m
	m.add_child(w)
	return w


func _ready() -> void:
	var lv: Dictionary = main.level
	var theme: String = lv.get("theme", "")
	var season: String = lv.get("season", "")
	var kinds := ["sparrow", "sparrow", "blackbird", "robin", "bluetit", "magpie"]
	if theme == "seaside":
		kinds = ["gull", "gull", "gull", "sparrow"]
	elif season == "halloween" or theme == "halloween":
		kinds = ["crow", "crow", "magpie", "blackbird"]
	elif theme == "snow" or season == "xmas" or theme == "xmas":
		kinds = ["robin", "robin", "bluetit", "blackbird", "sparrow"]
	elif theme in ["city", "multistorey", "carpark"]:
		kinds = ["sparrow", "crow", "magpie"]
	var flock_count := 3 if theme in ["city", "multistorey", "carpark"] else 5
	if main.get("training"):
		flock_count = 2
	for i in flock_count:
		_add_flock(kinds[main.rng.randi() % kinds.size()])
	var cat_count := 2 if theme in ["city", "multistorey", "carpark"] else 4
	for i in cat_count:
		var coat: Array = CAT_COATS[main.rng.randi() % CAT_COATS.size()]
		if season == "halloween" or theme == "halloween":
			coat = CAT_COATS[1]
		_add_cat(coat)


# ---------------------------------------------------------------- birds

func _landing_spot(away := Vector3.ZERO, min_d := 0.0) -> Vector3:
	var w = main.world
	var parks: Array = w.get("park_rects") if w.get("park_rects") != null else []
	if not parks.is_empty() and main.rng.randf() < 0.45:
		for i in 10:
			var r: Rect2 = parks[main.rng.randi() % parks.size()]
			var p := Vector3(main.rng.randf_range(r.position.x + 1, r.end.x - 1), 0, main.rng.randf_range(r.position.y + 1, r.end.y - 1))
			if p.distance_to(away) >= min_d:
				p.y = w.height_at(p)
				return p
	return w.random_walk_point(main.rng, away, min_d, true)


func _add_flock(kind: String) -> void:
	var sp: Dictionary = SPECIES[kind]
	var home := _landing_spot(main.warden.global_position if main.warden else Vector3.ZERO, 12.0)
	var f := {"kind": kind, "birds": [], "state": "ground", "home": home, "idle": main.rng.randf_range(25.0, 50.0),
		"t": 0.0, "dur": 1.0}
	var n: int = main.rng.randi_range(2, 4) if kind in ["gull", "crow", "magpie"] else main.rng.randi_range(3, 6)
	for i in n:
		var b := _make_bird(sp)
		add_child(b.node)
		b.offset = Vector3(main.rng.randf_range(-1.4, 1.4), 0, main.rng.randf_range(-1.4, 1.4))
		b.node.global_position = home + b.offset
		b.node.rotation.y = main.rng.randf() * TAU
		f.birds.append(b)
	flocks.append(f)


func _make_bird(sp: Dictionary) -> Dictionary:
	var s: float = sp.size * 0.32  # cartoon-big so they read from the warden camera
	var root := Node3D.new()
	var body := Node3D.new()
	root.add_child(body)
	var torso := Util.sphere(s, Util.mat(sp.body, true), Vector3(0, s * 1.1, 0))
	torso.scale = Vector3(0.85, 0.8, 1.25)
	body.add_child(torso)
	var belly := Util.sphere(s * 0.8, Util.mat(sp.belly), Vector3(0, s * 0.95, s * 0.35))
	belly.scale = Vector3(0.85, 0.8, 0.9)
	body.add_child(belly)
	var head := Node3D.new()
	head.position = Vector3(0, s * 1.75, s * 0.85)
	body.add_child(head)
	head.add_child(Util.sphere(s * 0.62, Util.mat(sp.head, true)))
	var beak := Util.box(Vector3(s * 0.22, s * 0.18, s * 0.6), Util.mat(sp.beak), Vector3(0, -s * 0.05, s * 0.75))
	head.add_child(beak)
	for x in [-1.0, 1.0]:
		head.add_child(Util.sphere(s * 0.13, Util.mat(Color(0.03, 0.03, 0.03)), Vector3(x * s * 0.42, s * 0.15, s * 0.38)))
	var tail := Util.box(Vector3(s * 0.6, s * 0.12, s * 1.0), Util.mat(sp.body), Vector3(0, s * 1.3, -s * 1.35))
	tail.rotation.x = -0.4
	body.add_child(tail)
	var wings := []
	for x in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(x * s * 0.7, s * 1.35, 0)
		body.add_child(pivot)
		pivot.add_child(Util.box(Vector3(s * 1.5, s * 0.1, s * 1.2), Util.mat(sp.body.darkened(0.15)), Vector3(x * s * 0.7, 0, -s * 0.1)))
		pivot.rotation.z = x * 1.3  # folded
		wings.append(pivot)
	for x in [-1.0, 1.0]:
		body.add_child(Util.box(Vector3(s * 0.08, s * 0.5, s * 0.08), Util.mat(Color(0.8, 0.55, 0.3)), Vector3(x * s * 0.25, s * 0.25, 0)))
	return {"node": root, "body": body, "head": head, "wings": wings, "offset": Vector3.ZERO, "hop": 0.0,
		"peck": main.rng.randf() * 3.0, "from": Vector3.ZERO, "to": Vector3.ZERO}


func _update_flock(f: Dictionary, delta: float) -> void:
	f.t += delta
	match f.state:
		"ground":
			f.idle -= delta
			for b in f.birds:
				_peck(b, delta)
			if f.idle <= 0.0:
				_take_off(f, Vector3.ZERO)
				return
			for w in main.all_wardens():
				var d: float = w.global_position.distance_to(f.home)
				var fast: bool = w.is_sprinting() if w.has_method("is_sprinting") else false
				if d < (5.5 if fast else 3.2):
					_take_off(f, w.global_position)
					return
			for c in get_tree().get_nodes_in_group("drivers"):
				if c.global_position.distance_to(f.home) < 3.0:
					_take_off(f, c.global_position)
					return
		"flying":
			var k := clampf(f.t / f.dur, 0.0, 1.0)
			for b in f.birds:
				var p: Vector3 = b.from.lerp(b.to, k)
				p.y += sin(k * PI) * f.height
				var prev: Vector3 = b.node.global_position
				b.node.global_position = p
				var v := p - prev
				v.y = 0.0
				if v.length() > 0.001:
					b.node.rotation.y = atan2(v.x, v.z)
				var flap := sin(f.t * 28.0 + b.peck)
				b.wings[0].rotation.z = -0.2 + flap * 0.9
				b.wings[1].rotation.z = 0.2 - flap * 0.9
				b.body.rotation.x = -0.2
			if k >= 1.0:
				f.state = "ground"
				f.idle = main.rng.randf_range(25.0, 50.0)
				for b in f.birds:
					b.wings[0].rotation.z = -1.3
					b.wings[1].rotation.z = 1.3
					b.body.rotation.x = 0.0


func _peck(b: Dictionary, delta: float) -> void:
	b.peck -= delta
	if b.peck <= 0.0:
		b.peck = main.rng.randf_range(0.6, 2.2)
		if main.rng.randf() < 0.45:
			# A couple of little hops to a new crumb
			b.hop = 0.3
			b.node.rotation.y += main.rng.randf_range(-1.2, 1.2)
	if b.hop > 0.0:
		b.hop -= delta
		var fwd := Vector3(sin(b.node.rotation.y), 0, cos(b.node.rotation.y))
		b.node.global_position += fwd * delta * 1.6
		b.body.position.y = absf(sin(b.hop * 20.0)) * 0.08
		b.head.rotation.x = 0.0
	else:
		b.body.position.y = 0.0
		var t: float = b.peck
		b.head.rotation.x = 0.9 if fmod(t, 0.5) < 0.12 else 0.0


func _take_off(f: Dictionary, threat: Vector3) -> void:
	var dest := _landing_spot(threat if threat != Vector3.ZERO else f.home, 15.0)
	f.state = "flying"
	f.t = 0.0
	var dist: float = f.home.distance_to(dest)
	f.dur = clampf(dist / 9.0, 1.6, 4.5)
	f.height = clampf(dist * 0.25, 3.0, 8.0)
	for b in f.birds:
		b.from = b.node.global_position
		b.offset = Vector3(main.rng.randf_range(-1.4, 1.4), 0, main.rng.randf_range(-1.4, 1.4))
		b.to = dest + b.offset
	f.home = dest
	if threat != Vector3.ZERO:
		Audio.sfx("flap", main.rng.randf_range(0.9, 1.15), 0.7)
		Audio.sfx(SPECIES[f.kind].call, main.rng.randf_range(0.95, 1.1), 0.45)


## A whistle sends every bird nearby flapping and every cat nearby running.
func whistled(pos: Vector3, radius: float) -> void:
	for f in flocks:
		if f.state == "ground" and f.home.distance_to(pos) < radius + 3.0:
			_take_off(f, pos)
	for c in cats:
		if c.node.global_position.distance_to(pos) < radius:
			_spook(c, pos)


## Geese in a V, high over the street now and then.
func _update_flyovers(delta: float) -> void:
	flyover_timer -= delta
	if flyover_timer <= 0.0 and main.warden:
		flyover_timer = main.rng.randf_range(40.0, 70.0)
		var dir := Vector3(main.rng.randf_range(-1, 1), 0, main.rng.randf_range(-1, 1)).normalized()
		if dir == Vector3.ZERO:
			dir = Vector3.RIGHT
		var start: Vector3 = main.warden.global_position - dir * 45.0 + Vector3(0, 11, 0)
		var v := {"birds": [], "dir": dir, "pos": start, "left": 10.0, "t": 0.0}
		var sp := {"body": Color(0.45, 0.4, 0.35), "belly": Color(0.85, 0.82, 0.78), "head": Color(0.1, 0.1, 0.1), "beak": Color(0.1, 0.1, 0.1), "size": 1.8}
		for i in 7:
			var b := _make_bird(sp)
			add_child(b.node)
			var row := (i + 1) / 2
			var side := -1.0 if i % 2 else 1.0
			b.offset = -dir * row * 1.6 + dir.cross(Vector3.UP) * side * row * 1.4
			b.node.rotation.y = atan2(dir.x, dir.z)
			v.birds.append(b)
		flyovers.append(v)
	for v in flyovers.duplicate():
		v.left -= delta
		v.t += delta
		v.pos += v.dir * delta * 9.0
		for b in v.birds:
			b.node.global_position = v.pos + b.offset
			var flap := sin(v.t * 9.0 + b.offset.length())
			b.wings[0].rotation.z = -0.1 + flap * 0.6
			b.wings[1].rotation.z = 0.1 - flap * 0.6
		if v.left <= 0.0:
			for b in v.birds:
				b.node.queue_free()
			flyovers.erase(v)


# ---------------------------------------------------------------- cats

func _add_cat(coat: Array) -> void:
	var c := _make_cat(coat)
	add_child(c.node)
	var perches: Array = main.world.get("perches") if main.world.get("perches") != null else []
	var away: Vector3 = main.warden.global_position if main.warden else Vector3.ZERO
	var pos := Vector3.ZERO
	c.perched = false
	if not perches.is_empty() and main.rng.randf() < 0.6:
		for i in 12:
			var p: Vector3 = perches[main.rng.randi() % perches.size()]
			if Vector3(p.x, 0, p.z).distance_to(Vector3(away.x, 0, away.z)) > 10.0:
				pos = Vector3(p.x, main.world.height_at(Vector3(p.x, 0, p.z)) + p.y, p.z)
				c.perched = true
				break
	if not c.perched:
		pos = main.world.random_walk_point(main.rng, away, 10.0, true)
	c.node.global_position = pos
	c.home = pos
	c.node.rotation.y = main.rng.randf() * TAU
	c.state = ["sit", "sleep", "groom"][main.rng.randi() % 3]
	c.timer = main.rng.randf_range(4.0, 10.0)
	cats.append(c)


func _make_cat(coat: Array) -> Dictionary:
	var fur: Color = coat[0]
	var pale: Color = coat[1]
	var root := Node3D.new()
	var body := Node3D.new()
	body.scale = Vector3.ONE * 1.35
	root.add_child(body)
	var torso := Util.capsule(0.17, 0.62, Util.mat(fur, true), Vector3(0, 0.3, 0))
	torso.rotation.x = PI / 2
	body.add_child(torso)
	body.add_child(Util.sphere(0.13, Util.mat(pale), Vector3(0, 0.27, 0.18)))
	var legs := []
	for z in [-0.18, 0.18]:
		for x in [-0.08, 0.08]:
			var leg := Util.box(Vector3(0.07, 0.24, 0.07), Util.mat(fur), Vector3(x, 0.12, z))
			body.add_child(leg)
			legs.append(leg)
	var head := Node3D.new()
	head.position = Vector3(0, 0.48, 0.3)
	body.add_child(head)
	head.add_child(Util.sphere(0.15, Util.mat(fur, true)))
	head.add_child(Util.sphere(0.07, Util.mat(pale), Vector3(0, -0.04, 0.12)))
	head.add_child(Util.sphere(0.022, Util.mat(Color(1.0, 0.55, 0.65)), Vector3(0, -0.01, 0.17)))
	for x in [-1.0, 1.0]:
		var ear := Util.prism(Vector3(0.1, 0.12, 0.05), Util.mat(fur), Vector3(x * 0.08, 0.15, 0.0))
		head.add_child(ear)
		var eye_col := Color(0.55, 0.9, 0.3) if fur.v < 0.3 else Color(0.95, 0.75, 0.2)
		# Eyes shine in the dark, so black cats show up at night
		var eye_m: Material = Util.glow(eye_col, 2.5) if main.level.get("night", false) else Util.mat(eye_col)
		head.add_child(Util.sphere(0.033, eye_m, Vector3(x * 0.06, 0.03, 0.125)))
		head.add_child(Util.box(Vector3(0.012, 0.04, 0.01), Util.mat(Color(0.02, 0.02, 0.02)), Vector3(x * 0.06, 0.03, 0.156)))
	var tail := Node3D.new()
	tail.position = Vector3(0, 0.35, -0.3)
	body.add_child(tail)
	var t1 := Util.cylinder(0.035, 0.42, Util.mat(fur), Vector3(0, 0.2, 0))
	tail.add_child(t1)
	tail.rotation.x = -0.6
	var label := Util.label3d("", 34, Color(1, 0.75, 0.85), Vector3(0, 1.0, 0))
	label.visible = false
	root.add_child(label)
	return {"node": root, "body": body, "head": head, "tail": tail, "legs": legs, "label": label, "t": 0.0,
		"state": "sit", "timer": 3.0, "home": Vector3.ZERO, "target": Vector3.ZERO, "stroked": false,
		"near": 0.0, "perched": false}


func _update_cat(c: Dictionary, delta: float) -> void:
	c.t += delta
	c.timer -= delta
	var n: Node3D = c.node
	# Tail swish whatever it's doing
	c.tail.rotation.z = sin(c.t * (5.0 if c.state == "flee" else 1.6)) * 0.5
	var w = main.nearest_warden(n.global_position)
	var d: float = w.global_position.distance_to(n.global_position) if w else 99.0
	match c.state:
		"sit", "groom", "sleep":
			_pose(c, c.state)
			if c.state == "sit" and w and d < 9.0:
				# Keep an eye on the warden
				var to: Vector3 = w.global_position - n.global_position
				c.head.rotation.y = clampf(wrapf(atan2(to.x, to.z) - n.rotation.y, -PI, PI), -1.1, 1.1)
			if w and d < 3.2 and w.is_sprinting():
				_spook(c, w.global_position)
				return
			if w and d < 1.6 and not c.stroked:
				c.near += delta
				if c.near > 0.7:
					_stroke(c, w)
			else:
				c.near = 0.0
			if c.timer <= 0.0:
				c.timer = main.rng.randf_range(5.0, 12.0)
				var roll: float = main.rng.randf()
				if not c.perched and roll < 0.35:
					c.state = "walk"
					c.target = main.world.random_walk_point(main.rng, n.global_position, 3.0, true)
					if c.target.distance_to(c.home) > 10.0:
						c.target = c.home
				else:
					c.state = ["sit", "groom", "sleep"][main.rng.randi() % 3]
		"walk", "flee":
			var speed := 4.8 if c.state == "flee" else 0.9
			var to: Vector3 = c.target - n.global_position
			to.y = 0.0
			if to.length() < 0.3 or c.timer <= 0.0:
				c.state = "sit"
				c.timer = main.rng.randf_range(5.0, 10.0)
				c.home = n.global_position
				return
			var step := to.normalized() * speed * delta
			n.global_position += step
			n.global_position.y = main.world.height_at(n.global_position)
			n.rotation.y = lerp_angle(n.rotation.y, atan2(to.x, to.z), 1.0 - exp(-10.0 * delta))
			_pose(c, "walk")
			var gait: float = c.t * (16.0 if c.state == "flee" else 7.0)
			for i in c.legs.size():
				c.legs[i].rotation.x = sin(gait + (PI if i % 3 == 0 else 0.0)) * 0.6


func _pose(c: Dictionary, pose: String) -> void:
	match pose:
		"sit":
			c.body.rotation.x = -0.45
			c.body.position.y = 0.06
			c.head.rotation.x = 0.45
		"groom":
			c.body.rotation.x = -0.45
			c.body.position.y = 0.06
			c.head.rotation.x = 0.9 + sin(c.t * 7.0) * 0.25
			c.head.rotation.y = 0.5
		"sleep":
			c.body.rotation.x = 0.0
			c.body.position.y = -0.12
			c.head.rotation.x = 0.5
			c.head.rotation.y = 0.9
		"walk":
			c.body.rotation.x = 0.0
			c.body.position.y = 0.0
			c.head.rotation.x = 0.0
			c.head.rotation.y = 0.0


func _spook(c: Dictionary, from: Vector3) -> void:
	if c.state == "flee":
		return
	var n: Node3D = c.node
	var away: Vector3 = n.global_position - from
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3.RIGHT
	c.target = main.world.nearest_walkable(n.global_position + away * 9.0)
	c.state = "flee"
	c.perched = false
	c.timer = 3.0
	c.near = 0.0
	_say(c, "HISSS!")
	Audio.sfx("hiss", main.rng.randf_range(0.9, 1.1), 0.6)
	# Off the wall in one bound
	n.global_position.y = main.world.height_at(n.global_position)


func _stroke(c: Dictionary, w) -> void:
	c.stroked = true
	c.state = "sit"
	c.timer = 6.0
	_say(c, "Purrrr <3")
	Audio.sfx("purr", 1.0, 0.8)
	get_tree().create_timer(0.6).timeout.connect(func() -> void:
		Audio.sfx(["meow", "meow2", "meow3"][main.rng.randi() % 3], main.rng.randf_range(0.95, 1.1), 0.7))
	if main.has_method("player_of"):
		var p = main.player_of(w)
		if p != null:
			p.score += STROKE_POINTS
	main._popup("GOOD KITTY!  +%d" % STROKE_POINTS, Color(1, 0.7, 0.85), c.node.global_position + Vector3(0, 1.4, 0), 30)


func _say(c: Dictionary, text: String) -> void:
	var l: Label3D = c.label
	l.text = text
	l.visible = true
	get_tree().create_timer(1.6).timeout.connect(func() -> void:
		if is_instance_valid(l):
			l.visible = false)


# ---------------------------------------------------------------- main loop

func _process(delta: float) -> void:
	if main.state != "playing" and main.state != "intro":
		return
	for f in flocks:
		_update_flock(f, delta)
	for c in cats:
		_update_cat(c, delta)
	_update_flyovers(delta)
	# The odd meow from a cat that's on screen
	if main.rng.randf() < delta * 0.04 and not cats.is_empty():
		var c: Dictionary = cats[main.rng.randi() % cats.size()]
		if main.warden and c.node.global_position.distance_to(main.warden.global_position) < 14.0 and c.state != "sleep":
			Audio.sfx(["meow", "meow2", "meow3"][main.rng.randi() % 3], main.rng.randf_range(0.9, 1.15), 0.45)
