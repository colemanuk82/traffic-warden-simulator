extends Node3D
## A cartoon warden built from an outfit (see catalogue.gd). Faces +Z.
## Exposes limbs so the owner can animate walking, punching and diving.
## Everything worn is placed against the real shape underneath it: hats sit on a "fit" sphere
## around the head and hair, and chest items sit on the torso capsule, so nothing floats or sinks.

const Util := preload("res://scripts/util.gd")
const Catalogue := preload("res://scripts/catalogue.gd")

# legs, torso radius, torso height, head radius, hunch
const SHAPES := {
	"classic": [0.5, 0.36, 0.95, 0.42, 0.0],
	"big": [0.45, 0.52, 1.0, 0.42, 0.0],
	"beanpole": [0.85, 0.27, 1.15, 0.36, 0.0],
	"shorty": [0.28, 0.4, 0.72, 0.46, 0.0],
	"granny": [0.38, 0.38, 0.82, 0.4, 0.25],
	"robot": [0.5, 0.36, 0.95, 0.42, 0.0],
	"alien": [0.45, 0.32, 0.85, 0.52, 0.0],
}
# Hair that sticks up through a hat is swapped for a neat cut while a hat is on
const TALL_HAIR := ["spiky", "mohawk", "quiff", "bun"]

var body: Node3D
var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var notepad: Node3D
var cape: Node3D
var weapon: Node3D
var torch: Node3D
var eye_whites: Array = []  # glow red in rampage mode
var bat_swing := false  # the rampage baseball bat swings round in a big arc instead of a jab
var height := 2.2
var torso_r := 0.36
var torso_h := 0.95
var walk_t := 0.0
var punch_t := 0.0

var _robot := false
var _hr := 0.42
var _shoulder_y := 0.78
var _neck_y := 0.85
# The sphere a hat has to fit over (head plus hair), in head space
var _fit_c := Vector3.ZERO
var _fit_r := 0.45
var _hat_top := 0.45
var _eye_y := 0.05
var _eye_x := 0.15
var _eye_z := 0.5


func build(outfit: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	cape = null
	var type_id: String = outfit.get("type", "classic")
	var shape: Array = SHAPES.get(type_id, SHAPES.classic)
	var leg_len: float = shape[0]
	var tr: float = shape[1]
	var th: float = shape[2]
	var hr: float = shape[3]
	var hunch: float = shape[4]
	torso_r = tr
	torso_h = th
	_hr = hr
	weapon = null
	torch = null

	var skin: Color = Catalogue.find("skin", outfit.get("skin", "s2")).color
	var hair_col: Color = Catalogue.find("hair_color", outfit.get("hair_color", "brown")).color
	var uni := Catalogue.find("uniform", outfit.get("uniform", "hivis"))
	var robot := type_id == "robot"
	_robot = robot
	if robot:
		skin = Color(0.7, 0.75, 0.8)
	elif type_id == "alien":
		skin = Color(0.5, 0.9, 0.45)
	var gold: bool = uni.id == "gold"
	var skin_m := Util.metal(skin) if robot else Util.mat(skin, true)
	var jacket_m := Util.metal(uni.jacket) if gold else Util.mat(uni.jacket, true)
	var trouser_m := Util.metal(uni.trousers) if gold else Util.mat(uni.trousers, true)
	var dark := Color(0.08, 0.08, 0.12)
	var hat_id: String = outfit.get("hat", "cap")
	var acc: String = outfit.get("accessory", "none")

	body = Node3D.new()
	add_child(body)

	# Legs swing from the hips
	var leg_w := tr * 0.5
	var shoe_m := Util.mat(Color(0.1, 0.09, 0.1), true)
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * tr * 0.42, leg_len, 0)
		body.add_child(leg)
		leg.add_child(Util.capsule(leg_w * 0.55, leg_len + 0.1, trouser_m, Vector3(0, -leg_len * 0.5, 0)))
		# Rounded cartoon shoe with a toe cap, resting on the ground
		var shoe := Util.sphere(0.15, shoe_m, Vector3(0, -leg_len + 0.075, 0.07))
		shoe.scale = Vector3(maxf(leg_w * 0.75, 0.13) / 0.15, 0.5, 1.35)
		leg.add_child(shoe)
		leg.add_child(Util.box(Vector3(maxf(leg_w * 1.4, 0.26), 0.04, 0.4), Util.mat(Color(0.25, 0.2, 0.18)), Vector3(0, -leg_len + 0.02, 0.07)))
		if side < 0.0:
			leg_l = leg
		else:
			leg_r = leg

	# Torso (leans forward for granny)
	torso = Node3D.new()
	torso.position = Vector3(0, leg_len, 0)
	torso.rotation.x = hunch
	body.add_child(torso)
	_shoulder_y = th * 0.82
	var head_y := th + hr * 0.55
	_neck_y = head_y - hr * 0.8
	if robot:
		torso.add_child(Util.box(Vector3(tr * 2.0, th, tr * 1.6), jacket_m, Vector3(0, th * 0.5, 0)))
	else:
		torso.add_child(Util.capsule(tr, th + tr * 0.6, jacket_m, Vector3(0, th * 0.5, 0)))
	_build_uniform(uni, jacket_m)
	_build_vest(outfit.get("vest", "none"), tr, th)
	# Badge pinned flat to the chest
	var badge_y := th * 0.66 if outfit.get("vest", "none") == "none" else th * 0.8
	_stick(torso, Util.box(Vector3(0.14, 0.15, 0.03), Util.metal(Color(0.85, 0.85, 0.9), false)), badge_y, -tr * 0.45, 0.015)
	# Collar hides the join between head and body
	if not robot:
		var nr := _torso_radius(_neck_y)
		var collar := Util.torus(nr * 0.62, nr * 1.04, Util.mat(uni.jacket.darkened(0.12), true), Vector3(0, _neck_y + 0.02, 0))
		torso.add_child(collar)

	# Arms swing from the shoulders and point straight down at rest
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * (tr + 0.08), _shoulder_y, 0)
		torso.add_child(arm)
		arm.add_child(Util.capsule(0.1, 0.6, jacket_m, Vector3(0, -0.26, 0)))
		if uni.id in ["hivis", "orange", "council", "ticket"]:
			arm.add_child(Util.cylinder(0.105, 0.06, Util.mat(uni.stripe), Vector3(0, -0.38, 0)))
		if uni.id == "chief":
			arm.add_child(Util.box(Vector3(0.24, 0.05, 0.24), Util.metal(Color(1, 0.8, 0.2), false), Vector3(0, 0.07, 0)))
		var fist_r := 0.12
		var fist_m: Material = skin_m
		if acc == "gloves":
			fist_r = 0.2
			fist_m = Util.mat(Color(0.9, 0.12, 0.12), true)
			arm.add_child(Util.cylinder(0.13, 0.08, Util.mat(Color.WHITE, true), Vector3(0, -0.46, 0)))
		else:
			arm.add_child(Util.cylinder(0.11, 0.06, Util.mat(uni.jacket.darkened(0.15)), Vector3(0, -0.5, 0)))
		arm.add_child(Util.sphere(fist_r, fist_m, Vector3(0, -0.6, 0)))
		if side < 0.0:
			arm_l = arm
			notepad = Util.box(Vector3(0.3, 0.04, 0.38), Util.mat(Color.WHITE, true), Vector3(0, -0.62, 0.22))
			arm.add_child(notepad)
		else:
			arm_r = arm

	# Head
	head = Node3D.new()
	head.position = Vector3(0, head_y, 0)
	torso.add_child(head)
	_fit_c = Vector3.ZERO
	_fit_r = hr * 1.02
	_eye_y = hr * 0.12
	_eye_x = hr * 0.36
	if robot:
		# Tin-can head: round, so every hat band fits it
		head.add_child(Util.cylinder(hr * 0.85, hr * 1.6, skin_m))
		head.add_child(Util.cylinder(hr * 0.88, 0.05, Util.metal(Color(0.5, 0.5, 0.55)), Vector3(0, -hr * 0.8, 0)))
		head.add_child(Util.box(Vector3(hr * 1.3, hr * 0.35, 0.05), Util.glow(Color(0.2, 1.0, 1.0), 3.0), Vector3(0, hr * 0.1, hr * 0.82)))
		for side in [-1.0, 1.0]:
			var bolt := Util.cylinder(hr * 0.16, 0.08, Util.metal(Color(0.5, 0.5, 0.55)), Vector3(side * hr * 0.86, 0, 0))
			bolt.rotation.z = PI / 2
			head.add_child(bolt)
		head.add_child(Util.box(Vector3(hr * 0.8, 0.05, 0.04), Util.mat(dark), Vector3(0, -hr * 0.45, hr * 0.84)))
		if hat_id == "none":
			head.add_child(Util.cylinder(0.03, 0.35, Util.metal(Color(0.5, 0.5, 0.55)), Vector3(0, hr * 0.8 + 0.17, 0)))
			head.add_child(Util.sphere(0.07, Util.glow(Color(1, 0.2, 0.2), 3.0), Vector3(0, hr * 0.8 + 0.37, 0)))
		_fit_c = Vector3(0, hr * 0.22, 0)
		_fit_r = hr * 1.05
		_eye_y = hr * 0.1
		_eye_z = hr * 0.88
	else:
		head.add_child(Util.sphere(hr, skin_m))
		_build_face(type_id, hr, skin, skin_m, hair_col, acc)
		if type_id == "alien" and hat_id == "none":
			for side in [-1.0, 1.0]:
				var stalk := Util.cylinder(0.025, 0.4, Util.mat(skin), Vector3(side * 0.18, hr + 0.15, 0))
				stalk.rotation.z = -side * 0.4
				head.add_child(stalk)
				head.add_child(Util.sphere(0.07, Util.glow(Color(1, 0.9, 0.2), 2.0), Vector3(side * 0.28, hr + 0.36, 0)))
		if type_id == "granny" and acc != "shades":
			# Granny's specs
			for side in [-1.0, 1.0]:
				var ring := Util.torus(hr * 0.17, hr * 0.24, Util.mat(Color(0.6, 0.4, 0.8)), Vector3(side * _eye_x, _eye_y, _eye_z + 0.01))
				ring.rotation.x = PI / 2
				head.add_child(ring)
			head.add_child(_bar(Vector3(-_eye_x + hr * 0.2, _eye_y, _eye_z), Vector3(_eye_x - hr * 0.2, _eye_y, _eye_z), 0.015, Util.mat(Color(0.6, 0.4, 0.8))))
		var hair: String = outfit.get("hair", "short")
		if hair == "bald" and type_id == "granny":
			hair = "bun"
		if hat_id != "none" and hair in TALL_HAIR:
			hair = "short"
		if hair != "bald":
			_build_hair(hair, hr, hair_col)
	_hat_top = _fit_c.y + _fit_r
	_build_hat(hat_id, hr)
	_build_accessory(acc, hr, tr, th, hair_col, hat_id != "none")
	height = leg_len + head_y + maxf(_hat_top, hr) + (0.4 if acc == "pigeon" else 0.1)


## Radius of the torso capsule at height y (torso space).
func _torso_radius(y: float) -> float:
	var tr := torso_r
	if _robot:
		return tr * 0.8
	var hi := torso_h - 0.7 * tr
	var lo := 0.7 * tr
	if y > hi:
		return sqrt(maxf(tr * tr - (y - hi) * (y - hi), 0.0))
	if y < lo:
		return sqrt(maxf(tr * tr - (lo - y) * (lo - y), 0.0))
	return tr


## Outward normal of the torso front at (x, y).
func _torso_normal(y: float, x: float) -> Vector3:
	if _robot:
		return Vector3.BACK
	var tr := torso_r
	var hi := torso_h - 0.7 * tr
	var lo := 0.7 * tr
	var dy := 0.0
	if y > hi:
		dy = y - hi
	elif y < lo:
		dy = y - lo
	var r := _torso_radius(y)
	var z := sqrt(maxf(r * r - x * x, 0.0))
	return Vector3(x, dy, z).normalized()


## Point on the torso front at (x, y), pushed out by `out`.
func _torso_point(y: float, x: float, out := 0.0) -> Vector3:
	var r := _torso_radius(y)
	if _robot:
		return Vector3(x, y, r + out)
	var z := sqrt(maxf(r * r - x * x, 0.0))
	return Vector3(x, y, z) + _torso_normal(y, x) * out


## Pins a flat item to the torso front so it lies against the curve instead of floating off it.
func _stick(parent: Node3D, n: Node3D, y: float, x: float, out: float) -> Node3D:
	n.position = _torso_point(y, x, out)
	n.basis = Basis(Quaternion(Vector3.BACK, _torso_normal(y, x))) * n.basis
	parent.add_child(n)
	return n


## Point on the head sphere (hr) at (x, y) on the front, pushed out by `out`.
func _face_point(x: float, y: float, out := 0.0) -> Vector3:
	var z := sqrt(maxf(_hr * _hr - x * x - y * y, 0.0))
	var p := Vector3(x, y, z)
	return p + p.normalized() * out


## Pins an item to the face, facing out from the head.
func _on_face(n: Node3D, x: float, y: float, out: float) -> Node3D:
	var p := _face_point(x, y, out)
	n.position = p
	n.basis = Basis(Quaternion(Vector3.BACK, p.normalized())) * n.basis
	head.add_child(n)
	return n


## A thin rod from a to b (straps, glasses arms).
func _bar(a: Vector3, b: Vector3, r: float, m: Material) -> MeshInstance3D:
	var d := b - a
	var rod := Util.cylinder(r, d.length(), m, (a + b) * 0.5)
	if d.length() > 0.0001:
		rod.basis = Basis(Quaternion(Vector3.UP, d.normalized()))
	return rod


## Flat text printed onto a surface (no billboard, hidden when behind things).
func _decal(text: String, size: int, col: Color) -> Label3D:
	var l := Util.label3d(text, size, col)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	l.no_depth_test = false
	l.double_sided = false
	l.pixel_size = 0.006
	l.outline_size = 4
	return l


## Height and radius of the ring around the hat-fit sphere at fraction h of its radius above the centre.
func _ring(h: float) -> Vector2:
	return Vector2(_fit_c.y + h * _fit_r, sqrt(maxf(1.0 - h * h, 0.0)) * _fit_r)


func _build_uniform(uni: Dictionary, jacket_m: Material) -> void:
	var tr := torso_r
	var th := torso_h
	var stripe_m := Util.mat(uni.stripe)
	var rows := [0.35]
	if uni.id in ["hivis", "orange", "pink", "council", "ticket"]:
		rows.append(0.6)
	for f in rows:
		var y: float = th * f
		if _robot:
			torso.add_child(Util.box(Vector3(tr * 2.04, 0.08, tr * 1.64), stripe_m, Vector3(0, y, 0)))
		else:
			torso.add_child(Util.cylinder(_torso_radius(y) * 1.02, 0.08, stripe_m, Vector3(0, y, 0)))
	if uni.id in ["hivis", "orange", "council", "ticket", "navy", "chief"]:
		# Zip or button line down the front
		torso.add_child(_bar(_torso_point(th * 0.12, 0, 0.005), _torso_point(th * 0.66, 0, 0.005), 0.018, Util.mat(uni.jacket.darkened(0.3))))
	if uni.id == "tux":
		_stick(torso, Util.box(Vector3(tr * 0.6, th * 0.5, 0.03), Util.mat(Color.WHITE)), th * 0.6, 0, 0.0)
		for side in [-1.0, 1.0]:
			var lapel := Util.prism(Vector3(tr * 0.35, th * 0.45, 0.03), Util.mat(Color(0.15, 0.15, 0.18)))
			lapel.rotation.z = PI
			_stick(torso, lapel, th * 0.62, side * tr * 0.38, 0.01)
		for i in 2:
			_stick(torso, Util.sphere(0.03, Util.mat(Color(0.1, 0.1, 0.1))), th * (0.45 + i * 0.12), 0, 0.02)
	if uni.id == "camo":
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 11:
			var a := rng.randf() * TAU
			var y := rng.randf_range(0.12, 0.8) * th
			var r := _torso_radius(y)
			var blob := Util.sphere(0.1, Util.mat(Color(0.22, 0.28, 0.15) if i % 2 else Color(0.5, 0.45, 0.3)),
				Vector3(sin(a) * r * 0.93, y, cos(a) * r * 0.93))
			blob.rotation.y = a
			blob.scale = Vector3(1.3, 0.8, 0.5)
			torso.add_child(blob)
	if uni.id == "gold":
		_stick(torso, _decal("$", 90, Color(1, 0.95, 0.5)), th * 0.5, 0, 0.02)
	if uni.id == "chief":
		for i in 3:
			_stick(torso, Util.sphere(0.04, Util.metal(Color(1, 0.8, 0.2), false)), th * (0.25 + i * 0.16), tr * 0.25, 0.01)
			_stick(torso, Util.sphere(0.04, Util.metal(Color(1, 0.8, 0.2), false)), th * (0.25 + i * 0.16), -tr * 0.25, 0.01)


func _build_face(type_id: String, hr: float, skin: Color, skin_m: Material, hair_col: Color, acc: String) -> void:
	var dark := Color(0.08, 0.08, 0.12)
	if type_id == "alien":
		for side in [-1.0, 1.0]:
			var eye := Util.sphere(0.12, Util.mat(dark))
			eye.scale = Vector3(0.8, 1.3, 0.5)
			_on_face(eye, side * _eye_x, _eye_y, 0.0)
			eye_whites.append(eye)
			_on_face(Util.sphere(0.03, Util.mat(Color.WHITE)), side * _eye_x + 0.03, _eye_y + 0.06, 0.04)
		_eye_z = _face_point(_eye_x, _eye_y).z + 0.07
		_on_face(Util.box(Vector3(hr * 0.35, 0.035, 0.03), Util.mat(Color(0.15, 0.3, 0.12))), 0, -hr * 0.42, 0.0)
		return
	# Googly eyes: white set into the face, pupil on the front
	var eye_r := 0.06
	for side in [-1.0, 1.0]:
		eye_whites.append(_on_face(Util.sphere(eye_r * 1.6, Util.mat(Color.WHITE)), side * _eye_x, _eye_y, -0.03))
		_on_face(Util.sphere(eye_r, Util.mat(dark)), side * _eye_x, _eye_y, 0.035)
		_on_face(Util.sphere(0.018, Util.mat(Color.WHITE)), side * _eye_x + 0.02, _eye_y + 0.025, 0.09)
		# Eyebrows, slightly cross (it's a warden)
		var brow := Util.capsule(0.022, hr * 0.38, Util.mat(hair_col.darkened(0.35)))
		brow.rotation.z = PI / 2 + side * 0.22
		_on_face(brow, side * _eye_x, _eye_y + hr * 0.3, 0.01)
		# Ears
		if type_id != "robot":
			var ear := Util.sphere(hr * 0.17, skin_m, Vector3(side * hr * 0.97, -hr * 0.02, -hr * 0.05))
			ear.scale = Vector3(0.5, 1.0, 0.8)
			head.add_child(ear)
		# Rosy cheeks
		var cheek := Util.sphere(hr * 0.13, Util.mat(skin.lerp(Color(1, 0.45, 0.45), 0.35)))
		cheek.scale = Vector3(1.2, 0.8, 0.3)
		_on_face(cheek, side * hr * 0.55, -hr * 0.2, -0.005)
	_eye_z = _face_point(_eye_x, _eye_y).z + 0.1
	var nose := Util.sphere(hr * 0.16, skin_m)
	_on_face(nose, 0, -hr * 0.05, -hr * 0.04)
	if acc == "tache" or acc == "beard":
		return
	_build_mouth(hr, 0.0)


func _build_mouth(hr: float, out: float) -> void:
	# A cheeky D-shaped grin: a half dome with its flat side up
	var grin := Util.hemisphere(hr * 0.25, Util.mat(Color(0.4, 0.08, 0.1)))
	grin.rotation.x = PI
	grin.scale = Vector3(1.0, 0.6, 0.3)
	_on_face(grin, 0, -hr * 0.36, out - 0.01)
	var teeth := Util.box(Vector3(hr * 0.34, hr * 0.05, 0.02), Util.mat(Color.WHITE))
	_on_face(teeth, 0, -hr * 0.385, out + 0.005)


func _build_hair(style: String, hr: float, col: Color) -> void:
	var m := Util.mat(col, true)
	var cap := Util.hemisphere(hr * 1.07, m, Vector3(0, hr * 0.02, -hr * 0.05))
	cap.rotation.x = -0.5
	# Hats fit over the hair cap
	_fit_c = Vector3(0, hr * 0.03, -hr * 0.04)
	_fit_r = hr * 1.09
	match style:
		"short":
			head.add_child(cap)
			for side in [-1.0, 1.0]:
				var burn := Util.box(Vector3(0.05, hr * 0.4, hr * 0.22), m, Vector3(side * hr * 0.93, hr * 0.1, hr * 0.12))
				burn.rotation.z = side * 0.25
				head.add_child(burn)
		"spiky":
			head.add_child(cap)
			for i in 7:
				var a := -1.2 + i * 0.4
				var spike := Util.cylinder(0.09, 0.32, m, Vector3(sin(a) * hr * 0.5, hr * 0.85, -cos(a) * 0.1 - 0.05), false, 0.0)
				spike.rotation = Vector3(-0.3, 0, -a * 0.6)
				head.add_child(spike)
		"afro":
			head.add_child(Util.sphere(hr * 1.35, m, Vector3(0, hr * 0.55, -hr * 0.4)))
			_fit_c = Vector3(0, hr * 0.55, -hr * 0.4)
			_fit_r = hr * 1.37
		"ponytail":
			head.add_child(cap)
			head.add_child(Util.sphere(0.1, m, Vector3(0, hr * 0.3, -hr * 1.05)))
			var tail := Util.capsule(0.11, 0.6, m, Vector3(0, -hr * 0.3, -hr * 1.2))
			tail.rotation.x = 0.35
			head.add_child(tail)
		"bun":
			head.add_child(cap)
			head.add_child(Util.sphere(hr * 0.45, m, Vector3(0, hr * 1.05, -hr * 0.25)))
		"long":
			head.add_child(cap)
			var back := Util.sphere(hr * 1.04, m, Vector3(0, -hr * 0.3, -hr * 0.32))
			back.scale = Vector3(1.0, 1.05, 0.75)
			head.add_child(back)
		"mohawk":
			for i in 5:
				var z := hr * (0.6 - i * 0.35)
				var fin := Util.box(Vector3(0.08, 0.32, 0.22), m, Vector3(0, hr * 0.95 - absf(z) * 0.35, z))
				head.add_child(fin)
			_fit_r = hr * 1.02
		"mullet":
			head.add_child(cap)
			var back := Util.sphere(hr * 0.8, m, Vector3(0, -hr * 0.5, -hr * 0.5))
			back.scale = Vector3(1.05, 1.0, 0.7)
			head.add_child(back)
		"quiff":
			head.add_child(cap)
			var quiff := Util.capsule(0.16, 0.6, m, Vector3(0, hr * 0.95, hr * 0.35))
			quiff.rotation.x = 1.1
			head.add_child(quiff)
		"combover":
			# Hair only round the back and sides, shiny on top
			var back := Util.hemisphere(hr * 1.05, m, Vector3(0, -hr * 0.05, -hr * 0.05))
			back.rotation.x = -1.35
			head.add_child(back)
			# A few brave strands combed over the top, lying on the scalp
			for i in 3:
				var z := hr * (i - 1) * 0.22
				var top := sqrt(maxf(hr * hr - z * z, 0.0)) * 1.03
				var a := Vector3(-hr * 0.8, hr * 0.5, z)
				a = a.normalized() * hr * 1.02
				var mid := Vector3(0, top, z)
				var b := Vector3(hr * 0.75, hr * 0.55, z).normalized() * hr * 1.02
				head.add_child(_bar(a, mid, 0.025, m))
				head.add_child(_bar(mid, b, 0.025, m))
				head.add_child(Util.sphere(0.025, m, mid))
			_fit_r = hr * 1.04
		_:
			head.add_child(cap)


func _build_vest(style: String, tr: float, th: float) -> void:
	if style == "none":
		return
	var cols := {"utility": Color(0.35, 0.4, 0.3), "tool": Color(0.55, 0.4, 0.25), "radio": Color(0.15, 0.15, 0.2),
		"stab": Color(0.2, 0.22, 0.28), "tactical": Color(0.15, 0.17, 0.12), "fishing": Color(0.45, 0.5, 0.4),
		"medal": Color(0.8, 0.1, 0.15)}
	var c: Color = cols.get(style, Color(0.3, 0.3, 0.3))
	var vm := Util.mat(c, true)
	if style == "medal":
		# A sash wrapped diagonally round the body, shoulder to hip
		var tilt := 0.7
		var sash := Util.torus(tr * 0.97, tr * 1.13, vm)
		sash.scale = Vector3(1.0 / cos(tilt), 2.2, 1)
		var holder := Node3D.new()
		var mid := 0.7 * tr + (th - 1.4 * tr) * 0.5
		holder.position = Vector3(0, mid, 0)
		holder.rotation.z = tilt
		holder.add_child(sash)
		torso.add_child(holder)
		for i in 3:
			var x := -tr * 0.35 + i * tr * 0.35
			var y := mid + x * tan(tilt)
			var medal := Node3D.new()
			medal.add_child(_bar(Vector3(0, 0.03, 0), Vector3(0, 0.12, 0), 0.03, Util.mat(Color(0.2, 0.35, 0.9))))
			var disc := Util.cylinder(0.065, 0.025, Util.metal(Color(1, 0.8, 0.2), false))
			disc.rotation.x = PI / 2
			medal.add_child(disc)
			_stick(torso, medal, y - 0.06, x, 0.04)
		return
	var vest_top := 0.0
	if _robot:
		torso.add_child(Util.box(Vector3(tr * 2.08, th * 0.62, tr * 1.68), vm, Vector3(0, th * 0.55, 0)))
		vest_top = th * 0.86
	else:
		# Fitted: a straight body plus a tapered shoulder piece that follows the capsule's top curve
		var lo := th * 0.18
		var hi := th - 0.7 * tr
		torso.add_child(Util.cylinder(tr * 1.06, hi - lo, vm, Vector3(0, (lo + hi) * 0.5, 0)))
		var sh := minf(tr * 0.55, _neck_y - hi)
		var top_r := sqrt(maxf(tr * tr - sh * sh, 0.0)) * 1.06 + 0.02
		torso.add_child(Util.cylinder(tr * 1.06, sh, vm, Vector3(0, hi + sh * 0.5, 0), false, top_r))
		vest_top = hi + sh
		# Open front with a zip
		torso.add_child(_bar(_torso_point(lo + 0.02, 0, tr * 0.065), _torso_point(vest_top - 0.03, 0, tr * 0.065), 0.02, Util.mat(c.darkened(0.45))))
	var out := tr * 0.06
	var pocket := c.lightened(0.2) if style != "stab" else c.darkened(0.3)
	match style:
		"utility", "fishing", "tool":
			for side in [-1.0, 1.0]:
				for row in 2:
					_stick(torso, Util.box(Vector3(0.17, 0.15, 0.05), Util.mat(pocket, true)), th * (0.3 + row * 0.2), side * tr * 0.45, out + 0.02)
			if style == "tool":
				_stick(torso, Util.box(Vector3(0.04, 0.26, 0.04), Util.metal(Color(0.7, 0.7, 0.75), false)), th * 0.55, tr * 0.3, out + 0.04)
				_stick(torso, Util.box(Vector3(0.1, 0.08, 0.05), Util.mat(Color(0.85, 0.2, 0.1))), th * 0.44, tr * 0.3, out + 0.05)
			if style == "fishing":
				_stick(torso, Util.sphere(0.05, Util.mat(Color(1, 0.3, 0.1))), th * 0.66, -tr * 0.45, out + 0.03)
				_stick(torso, Util.sphere(0.04, Util.mat(Color(0.2, 0.6, 1.0))), th * 0.64, -tr * 0.3, out + 0.03)
		"radio":
			# Radio clipped to the chest, aerial alongside the shoulder (clear of the face)
			var radio := Node3D.new()
			radio.add_child(Util.box(Vector3(0.13, 0.22, 0.08), Util.mat(Color(0.1, 0.1, 0.1), true)))
			radio.add_child(Util.sphere(0.03, Util.glow(Color(0.2, 1, 0.3), 2.0), Vector3(-0.03, 0.07, 0.045)))
			radio.add_child(Util.cylinder(0.018, 0.16, Util.mat(Color(0.1, 0.1, 0.1)), Vector3(0.04, 0.18, 0)))
			_stick(torso, radio, th * 0.6, tr * 0.5, out + 0.04)
			torso.add_child(_bar(_torso_point(th * 0.52, tr * 0.5, out + 0.02), _torso_point(th * 0.3, tr * 0.7, out + 0.01), 0.012, Util.mat(Color(0.1, 0.1, 0.1))))
		"stab":
			_stick(torso, Util.box(Vector3(tr * 1.2, 0.12, 0.03), Util.mat(Color(0.9, 0.9, 0.9))), th * 0.55, 0, out + 0.01)
			_stick(torso, _decal("WARDEN", 30, Color(0.1, 0.1, 0.15)), th * 0.55, 0, out + 0.03)
		"tactical":
			for i in 3:
				_stick(torso, Util.box(Vector3(0.13, 0.19, 0.06), Util.mat(pocket, true)), th * 0.36, -tr * 0.5 + i * tr * 0.5, out + 0.02)
			_stick(torso, Util.box(Vector3(tr * 1.4, 0.07, 0.03), Util.mat(Color(0.1, 0.1, 0.1))), th * 0.6, 0, out + 0.01)


func _build_hat(style: String, hr: float) -> void:
	var dark := Color(0.1, 0.1, 0.16)
	var hat := Node3D.new()
	# A touch of tilt back so the brim shows the face
	hat.rotation.x = -0.08
	head.add_child(hat)
	var m := 0.015  # snug margin over the head
	match style:
		"cap", "inspector":
			var ring := _ring(0.4)
			var y := ring.x
			var r := ring.y + m
			var crown_col := dark if style == "cap" else Color(0.95, 0.95, 0.95)
			var band_col := Color(0.95, 0.8, 0.1) if style == "cap" else Color(0.08, 0.08, 0.1)
			var top := _fit_c.y + _fit_r + hr * 0.12
			# Band hugging the head
			hat.add_child(Util.cylinder(r, hr * 0.24, Util.mat(dark, true), Vector3(0, y + hr * 0.12, 0)))
			hat.add_child(Util.cylinder(r + 0.012, hr * 0.12, Util.mat(band_col), Vector3(0, y + hr * 0.13, 0)))
			# Crown flares out over the top
			var ch := top - (y + hr * 0.24)
			hat.add_child(Util.cylinder(r, ch, Util.mat(crown_col, true), Vector3(0, y + hr * 0.24 + ch * 0.5, 0), false, r * 1.18))
			# Peak: a disc sunk into the band, so only the front half shows
			var peak := Util.cylinder(r * 0.78, 0.035, Util.mat(Color(0.05, 0.05, 0.08), true), Vector3(0, y + 0.01, r * 0.5))
			peak.rotation.x = 0.3
			peak.scale = Vector3(1.0, 1.0, 0.9)
			hat.add_child(peak)
			var badge := Util.box(Vector3(0.14, 0.11, 0.03), Util.metal(Color(0.95, 0.85, 0.3), false), Vector3(0, y + hr * 0.36, r * 1.03))
			badge.rotation.x = -0.25
			hat.add_child(badge)
			if style == "inspector":
				hat.add_child(_bar(Vector3(-r * 0.6, y + 0.04, r * 0.82), Vector3(r * 0.6, y + 0.04, r * 0.82), 0.018, Util.metal(Color(1, 0.8, 0.2), false)))
			_hat_top = top
		"baseball", "baseball_back":
			if style == "baseball_back":
				# Spin round the middle of the hair, not the face, so it stays centred
				hat.rotation.y = PI
				hat.position.z = _fit_c.z * 2.0
			var cap_col := Color(0.15, 0.3, 0.75)
			var ring := _ring(0.25)
			var r := ring.y + m
			var top := _fit_c.y + _fit_r + 0.03
			var dome := Util.hemisphere(r, Util.mat(cap_col, true), Vector3(0, ring.x, _fit_c.z))
			dome.scale.y = (top - ring.x) / r
			hat.add_child(dome)
			var brim := Util.cylinder(r * 0.8, 0.035, Util.mat(cap_col.darkened(0.25), true), Vector3(0, ring.x + 0.01, _fit_c.z + r * 0.62))
			brim.rotation.x = 0.12
			brim.scale = Vector3(0.95, 1, 1.1)
			hat.add_child(brim)
			hat.add_child(Util.sphere(0.05, Util.mat(cap_col.darkened(0.3)), Vector3(0, top - 0.01, _fit_c.z)))
			# Logo printed on the front panel
			var ly := ring.x + (top - ring.x) * 0.38
			var lz := _fit_c.z + r * sqrt(maxf(1.0 - pow((ly - ring.x) / (top - ring.x), 2.0), 0.0))
			var logo := _decal("TW", 40, Color.WHITE)
			logo.position = Vector3(0, ly, lz + 0.01)
			logo.rotation.x = -0.5
			hat.add_child(logo)
			_hat_top = top
		"bobble":
			var ring := _ring(0.2)
			var r := ring.y + m
			var top := _fit_c.y + _fit_r + 0.06
			var dome := Util.hemisphere(r, Util.mat(Color(0.85, 0.15, 0.2), true), Vector3(0, ring.x, _fit_c.z))
			dome.scale.y = (top - ring.x) / r
			hat.add_child(dome)
			hat.add_child(Util.cylinder(r + 0.03, hr * 0.32, Util.mat(Color.WHITE, true), Vector3(0, ring.x + hr * 0.1, _fit_c.z)))
			hat.add_child(Util.sphere(0.16, Util.mat(Color.WHITE, true), Vector3(0, top + 0.1, _fit_c.z)))
			_hat_top = top + 0.26
		"hardhat":
			var ring := _ring(0.3)
			var r := ring.y + m
			var top := _fit_c.y + _fit_r + 0.05
			var yel := Util.mat(Color(1, 0.8, 0.1), true)
			var dome := Util.hemisphere(r, yel, Vector3(0, ring.x, _fit_c.z))
			dome.scale.y = (top - ring.x) / r
			hat.add_child(dome)
			hat.add_child(Util.cylinder(r * 1.28, 0.04, yel, Vector3(0, ring.x + 0.01, _fit_c.z + 0.05)))
			var ridge := Util.capsule(0.04, r * 1.4, yel, Vector3(0, top - 0.02, _fit_c.z))
			ridge.rotation.x = PI / 2
			hat.add_child(ridge)
			_hat_top = top
		"tophat":
			var ring := _ring(0.5)
			var r := ring.y + m
			var h := hr * 1.4
			var tm := Util.mat(dark, true)
			hat.add_child(Util.cylinder(r * 1.5, 0.05, tm, Vector3(0, ring.x, 0)))
			hat.add_child(Util.cylinder(r * 0.98, h, tm, Vector3(0, ring.x + h * 0.5, 0), false, r * 1.05))
			hat.add_child(Util.cylinder(r * 1.0, h * 0.16, Util.mat(Color(0.75, 0.1, 0.15)), Vector3(0, ring.x + h * 0.12, 0)))
			_hat_top = ring.x + h
		"cone":
			var ring := _ring(0.42)
			var r := ring.y + m
			var h := hr * 1.9
			var om := Util.mat(Color(1, 0.45, 0.05), true)
			hat.add_child(Util.cylinder(r, h, om, Vector3(0, ring.x + h * 0.5, 0), false, 0.05))
			# White reflective band, matched to the cone's slope
			var b0 := 0.45
			var b1 := 0.62
			hat.add_child(Util.cylinder(lerpf(r, 0.05, b0) + 0.01, h * (b1 - b0), Util.mat(Color.WHITE), Vector3(0, ring.x + h * (b0 + b1) * 0.5, 0), false, lerpf(r, 0.05, b1) + 0.01))
			hat.add_child(Util.box(Vector3(r * 2.15, 0.05, r * 2.15), om, Vector3(0, ring.x, 0)))
			_hat_top = ring.x + h
		"helmet":
			var ring := _ring(0.28)
			var r := ring.y + m
			var navy := Util.mat(Color(0.08, 0.1, 0.25), true)
			var h := _fit_r * 1.6
			var dome := Util.hemisphere(r, navy, Vector3(0, ring.x, _fit_c.z))
			dome.scale.y = h / r
			hat.add_child(dome)
			hat.add_child(Util.cylinder(r + 0.03, 0.05, navy, Vector3(0, ring.x + 0.02, _fit_c.z)))
			var silver := Util.metal(Color(0.85, 0.85, 0.9), false)
			hat.add_child(Util.sphere(0.07, silver, Vector3(0, ring.x + h + 0.03, _fit_c.z)))
			var star := Util.cylinder(0.11, 0.03, silver, Vector3(0, ring.x + h * 0.4, _fit_c.z + r * 0.93), false, 0.11)
			star.rotation.x = PI / 2 - 0.35
			hat.add_child(star)
			hat.add_child(_bar(Vector3(-r, ring.x, _fit_c.z), Vector3(0, ring.x - hr * 0.62, _fit_c.z + hr * 0.75), 0.02, Util.mat(Color(0.1, 0.1, 0.1))))
			hat.add_child(_bar(Vector3(r, ring.x, _fit_c.z), Vector3(0, ring.x - hr * 0.62, _fit_c.z + hr * 0.75), 0.02, Util.mat(Color(0.1, 0.1, 0.1))))
			_hat_top = ring.x + h + 0.1
		"crown":
			var ring := _ring(0.55)
			var r := ring.y + m
			var gold := Util.metal(Color(1, 0.8, 0.2))
			var bh := hr * 0.42
			# Velvet cushion fills the crown so hair doesn't show through the gaps
			var velvet := Util.hemisphere(r * 0.96, Util.mat(Color(0.6, 0.05, 0.15), true), Vector3(0, ring.x, 0))
			velvet.scale.y = 0.75
			hat.add_child(velvet)
			hat.add_child(Util.cylinder(r, bh, gold, Vector3(0, ring.x + bh * 0.5, 0), false, r * 1.08))
			for i in 6:
				var a := i * TAU / 6.0
				var pt := Util.prism(Vector3(r * 0.7, hr * 0.32, 0.04), gold)
				pt.position = Vector3(sin(a) * r * 1.07, ring.x + bh + hr * 0.15, cos(a) * r * 1.07)
				pt.rotation.y = a
				hat.add_child(pt)
				hat.add_child(Util.sphere(0.035, Util.metal(Color(1, 0.9, 0.5), false), pt.position + Vector3(0, hr * 0.17, 0)))
				var gem := Util.sphere(0.055, Util.glow(Color(0.9, 0.1, 0.3) if i % 2 else Color(0.2, 0.5, 1.0), 0.8))
				gem.position = Vector3(sin(a + TAU / 12.0) * r * 1.05, ring.x + bh * 0.5, cos(a + TAU / 12.0) * r * 1.05)
				gem.rotation.y = a + TAU / 12.0
				gem.scale = Vector3(1, 1, 0.5)
				hat.add_child(gem)
			_hat_top = ring.x + bh + hr * 0.35
		_:
			hat.queue_free()


func _build_accessory(style: String, hr: float, tr: float, th: float, hair_col: Color, has_hat: bool) -> void:
	match style:
		"shades":
			var fm := Util.mat(Color(0.05, 0.05, 0.08))
			var lens_m := Util.metal(Color(0.1, 0.12, 0.2), false)
			var z := _eye_z + 0.01
			for side in [-1.0, 1.0]:
				var lens := Util.sphere(hr * 0.27, lens_m, Vector3(side * _eye_x, _eye_y, z))
				lens.scale = Vector3(1.15, 0.8, 0.25)
				head.add_child(lens)
				var rim := Util.torus(hr * 0.27, hr * 0.33, fm, Vector3(side * _eye_x, _eye_y, z))
				rim.rotation.x = PI / 2
				rim.scale = Vector3(1.1, 1.0, 0.8)
				head.add_child(rim)
				# Arm runs back along the side of the head to the ear
				var hinge := Vector3(side * (_eye_x + hr * 0.33), _eye_y, z - 0.02)
				var ear := Vector3(side * hr * 1.04, _eye_y - hr * 0.05, -hr * 0.1)
				head.add_child(_bar(hinge, ear, 0.02, fm))
			head.add_child(_bar(Vector3(-_eye_x + hr * 0.3, _eye_y + 0.02, z), Vector3(_eye_x - hr * 0.3, _eye_y + 0.02, z), 0.022, fm))
		"tache":
			var tm := Util.mat(hair_col.darkened(0.2), true)
			for side in [-1.0, 1.0]:
				var half := Util.capsule(0.065, hr * 0.5, tm)
				half.rotation.z = side * (PI / 2 - 0.35)
				_on_face(half, side * hr * 0.2, -hr * 0.27, 0.02)
			_build_mouth(hr, 0.0)
		"beard":
			var bm := Util.mat(hair_col, true)
			var b := Util.sphere(hr * 0.78, bm, Vector3(0, -hr * 0.5, hr * 0.36))
			b.scale = Vector3(1.12, 0.9, 0.78)
			head.add_child(b)
			for side in [-1.0, 1.0]:
				var half := Util.capsule(0.06, hr * 0.45, Util.mat(hair_col.darkened(0.15), true))
				half.rotation.z = side * (PI / 2 - 0.3)
				_on_face(half, side * hr * 0.2, -hr * 0.27, 0.03)
			# Mouth peeking out of the beard
			var mouth := Util.sphere(hr * 0.12, Util.mat(Color(0.35, 0.08, 0.1)), Vector3(0, -hr * 0.42, hr * 0.97))
			mouth.scale = Vector3(1.4, 0.55, 0.4)
			head.add_child(mouth)
		"bowtie":
			var bow := Node3D.new()
			var red := Util.mat(Color(0.85, 0.1, 0.2), true)
			for side in [-1.0, 1.0]:
				var w := Util.prism(Vector3(0.16, 0.15, 0.06), red, Vector3(side * 0.085, 0, 0))
				w.rotation.z = side * PI / 2
				bow.add_child(w)
			bow.add_child(Util.sphere(0.045, red))
			_stick(torso, bow, _neck_y - 0.07, 0, 0.0)
		"headphones":
			var r := maxf(_fit_r, hr * 1.06) + 0.02
			var c := _fit_c if _fit_r < hr * 1.3 else Vector3.ZERO
			if not has_hat:
				# Arc over the top of the head, ear to ear
				var bm := Util.mat(Color(0.15, 0.15, 0.2), true)
				var steps := 9
				var prev := Vector3(-r - 0.02, 0, -hr * 0.05)
				for i in range(1, steps + 1):
					var a := PI - PI * i / float(steps)
					var cur := Vector3(cos(a) * (r + 0.02), c.y + sin(a) * (r + 0.04 - c.y), -hr * 0.05)
					if i == steps:
						cur = Vector3(r + 0.02, 0, -hr * 0.05)
					head.add_child(_bar(prev, cur, 0.04, bm))
					head.add_child(Util.sphere(0.04, bm, cur))
					prev = cur
			for side in [-1.0, 1.0]:
				var cup := Util.cylinder(0.15, 0.12, Util.mat(Color(0.95, 0.2, 0.4), true), Vector3(side * (r + 0.02), 0, -hr * 0.05))
				cup.rotation.z = PI / 2
				head.add_child(cup)
				var pad := Util.cylinder(0.1, 0.13, Util.mat(Color(0.15, 0.15, 0.2)), Vector3(side * (r + 0.02), 0, -hr * 0.05))
				pad.rotation.z = PI / 2
				head.add_child(pad)
		"parrot":
			var p := _shoulder_perch(1.0, 0.12)
			var red := Util.mat(Color(0.95, 0.15, 0.1), true)
			var bird := Util.capsule(0.11, 0.36, red, Vector3(0, 0.2, 0))
			bird.rotation.x = -0.25
			p.add_child(bird)
			p.add_child(Util.sphere(0.1, red, Vector3(0, 0.42, 0.06)))
			var beak := Util.cylinder(0.04, 0.1, Util.mat(Color(1, 0.8, 0.1)), Vector3(0, 0.4, 0.17), false, 0.0)
			beak.rotation.x = PI / 2
			p.add_child(beak)
			for side in [-1.0, 1.0]:
				p.add_child(Util.sphere(0.02, Util.mat(Color(0.05, 0.05, 0.05)), Vector3(side * 0.07, 0.45, 0.12)))
				var wing := Util.sphere(0.1, Util.mat(Color(0.15, 0.5, 0.95), true), Vector3(side * 0.09, 0.2, -0.02))
				wing.scale = Vector3(0.35, 1.2, 0.8)
				p.add_child(wing)
			var tail := Util.box(Vector3(0.08, 0.3, 0.03), Util.mat(Color(0.2, 0.75, 0.3)), Vector3(0, 0.0, -0.13))
			tail.rotation.x = 0.5
			p.add_child(tail)
			p.add_child(Util.box(Vector3(0.12, 0.03, 0.06), Util.mat(Color(0.4, 0.4, 0.4)), Vector3(0, 0.01, 0.02)))
		"pigeon":
			# Pigeon nesting on top of the head (or hat)
			var p := Node3D.new()
			p.position = Vector3(0, _hat_top - 0.03, _fit_c.z * 0.5)
			head.add_child(p)
			var grey := Util.mat(Color(0.6, 0.62, 0.68), true)
			var pb := Util.sphere(0.13, grey, Vector3(0, 0.1, 0))
			pb.scale = Vector3(0.9, 0.85, 1.3)
			p.add_child(pb)
			p.add_child(Util.sphere(0.08, Util.mat(Color(0.4, 0.55, 0.5), true), Vector3(0, 0.22, 0.12)))
			var beak := Util.cylinder(0.025, 0.07, Util.mat(Color(0.95, 0.7, 0.3)), Vector3(0, 0.21, 0.22), false, 0.0)
			beak.rotation.x = PI / 2
			p.add_child(beak)
			for side in [-1.0, 1.0]:
				p.add_child(Util.sphere(0.018, Util.mat(Color(0.9, 0.4, 0.1)), Vector3(side * 0.05, 0.25, 0.17)))
			var tail := Util.box(Vector3(0.12, 0.03, 0.14), grey, Vector3(0, 0.12, -0.18))
			tail.rotation.x = -0.3
			p.add_child(tail)
		"scarf":
			var nr := _torso_radius(_neck_y)
			var green := Util.mat(Color(0.2, 0.6, 0.3), true)
			torso.add_child(Util.torus(nr * 0.6, nr * 1.12, green, Vector3(0, _neck_y + 0.03, 0)))
			var tail := Node3D.new()
			tail.add_child(Util.box(Vector3(0.15, 0.42, 0.05), Util.mat(Color(0.85, 0.15, 0.15), true), Vector3(0, -0.21, 0)))
			tail.add_child(Util.box(Vector3(0.155, 0.06, 0.055), Util.mat(Color.WHITE), Vector3(0, -0.3, 0)))
			_stick(torso, tail, _neck_y - 0.02, tr * 0.35, 0.03)
		"cape":
			cape = Node3D.new()
			cape.position = Vector3(0, _shoulder_y + 0.06, -_torso_radius(_shoulder_y) - 0.04)
			torso.add_child(cape)
			var cm := Util.mat(Color(0.85, 0.1, 0.15), true)
			# Flattened cone: narrow at the shoulders, flaring out at the hem
			var cloth := Util.cylinder(tr * 1.3, th * 1.1, cm, Vector3(0, -th * 0.55, 0), false, tr * 0.8)
			cloth.scale = Vector3(1, 1, 0.08)
			cape.add_child(cloth)
			# Clasp ties over the shoulders
			for side in [-1.0, 1.0]:
				torso.add_child(_bar(cape.position + Vector3(side * tr * 0.7, 0, 0), _torso_point(_neck_y - 0.05, side * tr * 0.25, 0.02), 0.03, cm))
			_stick(torso, Util.sphere(0.05, Util.metal(Color(1, 0.8, 0.2), false)), _neck_y - 0.06, 0, 0.02)
			cape.rotation.x = 0.2
		"lanyard":
			var gold := Util.mat(Color(1, 0.8, 0.2))
			var card_y := th * 0.42
			var hook := _torso_point(card_y + 0.15, 0, 0.03)
			for side in [-1.0, 1.0]:
				torso.add_child(_bar(_torso_point(_neck_y, side * tr * 0.35, 0.02), hook, 0.018, gold))
			var card := Node3D.new()
			card.add_child(Util.box(Vector3(0.2, 0.26, 0.025), Util.mat(Color.WHITE, true)))
			card.add_child(Util.box(Vector3(0.08, 0.09, 0.01), Util.mat(Color(0.6, 0.75, 0.9)), Vector3(-0.04, 0.04, 0.015)))
			card.add_child(Util.box(Vector3(0.16, 0.025, 0.01), Util.mat(Color(0.9, 0.2, 0.2)), Vector3(0, -0.08, 0.015)))
			_stick(torso, card, card_y, 0, 0.04)


## A spot on top of the shoulder clear of the head, for pets.
func _shoulder_perch(side: float, half_w: float) -> Node3D:
	var p := Node3D.new()
	var z := -0.1
	var y := _shoulder_y + 0.05
	var head_c := head.position
	# Slide outwards until the bird no longer pokes into the head
	var x := torso_r + 0.05
	for i in 20:
		var q := Vector3(x - side * half_w, y + 0.25, z)
		if q.distance_to(head_c) > _fit_r + 0.03:
			break
		x += 0.02
	p.position = Vector3(side * x, y, z)
	torso.add_child(p)
	return p


## Call every frame. speed is 0..1 (1 = sprinting).
func animate(delta: float, speed: float) -> void:
	if speed > 0.05:
		walk_t += delta * lerpf(8.0, 16.0, speed)
		var swing := sin(walk_t) * lerpf(0.5, 0.9, speed)
		leg_l.rotation.x = swing
		leg_r.rotation.x = -swing
		if punch_t <= 0.0:
			arm_r.rotation.x = swing * 0.8
		arm_l.rotation.x = -swing * 0.5 - 0.6
		body.position.y = absf(sin(walk_t)) * 0.12
		body.rotation.z = sin(walk_t) * 0.06
	else:
		var k := 1.0 - exp(-12.0 * delta)
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, k)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, k)
		if punch_t <= 0.0:
			arm_r.rotation.x = lerpf(arm_r.rotation.x, 0.0, k)
		arm_l.rotation.x = lerpf(arm_l.rotation.x, -0.7, k)
		body.position.y = lerpf(body.position.y, 0.0, k)
		body.rotation.z = lerpf(body.rotation.z, 0.0, k)
	if cape:
		cape.rotation.x = lerpf(cape.rotation.x, 0.15 + speed * 0.9, 1.0 - exp(-6.0 * delta))
	if punch_t > 0.0:
		punch_t -= delta
		# Fast jab out, slower pull back
		var p := 1.0 - clampf(punch_t / 0.3, 0.0, 1.0)
		var reach := sin(minf(p * 2.2, 1.0) * PI * 0.5) * (1.0 - smoothstep(0.55, 1.0, p))
		if bat_swing:
			# Wind up over the shoulder, then a big sweep across the front
			arm_r.rotation.x = -PI * 0.55
			arm_r.rotation.z = lerpf(1.3, -1.1, smoothstep(0.0, 0.45, p)) * (1.0 - smoothstep(0.6, 1.0, p))
			torso.rotation.y = lerpf(0.6, -0.7, smoothstep(0.0, 0.45, p)) * (1.0 - smoothstep(0.6, 1.0, p))
			if punch_t <= 0.0:
				arm_r.rotation.z = 0.0
		else:
			arm_r.rotation.x = -PI * 0.5 * reach
			torso.rotation.y = -0.35 * reach


func punch() -> void:
	punch_t = 0.3


## Rampage mode: the eyes glow red.
func set_red_eyes(on: bool) -> void:
	for e in eye_whites:
		if is_instance_valid(e):
			e.material_override = Util.glow(Color(1, 0.05, 0.05), 3.0) if on else null


## Puts a melee weapon in the right hand (see career.gd WEAPONS). "fists" removes it.
func set_weapon(id: String) -> void:
	bat_swing = id == "bat"
	if arm_r:
		arm_r.rotation.z = 0.0
	if weapon:
		weapon.queue_free()
		weapon = null
	if id == "fists" or arm_r == null:
		return
	weapon = Node3D.new()
	weapon.position = Vector3(0, -0.62, 0.05)
	arm_r.add_child(weapon)
	match id:
		"bat":
			# A big wooden baseball bat
			var wood := Util.mat(Color(0.78, 0.55, 0.3), true)
			var bat := Util.cylinder(0.11, 1.1, wood, Vector3(0, -0.62, 0), false, 0.05)
			bat.rotation.x = PI
			weapon.add_child(bat)
			weapon.add_child(Util.sphere(0.11, wood, Vector3(0, -1.17, 0)))
			weapon.add_child(Util.cylinder(0.06, 0.22, Util.mat(Color(0.12, 0.12, 0.14)), Vector3(0, -0.05, 0)))
		"newspaper":
			var roll := Util.cylinder(0.07, 0.75, Util.mat(Color(0.92, 0.92, 0.88), true), Vector3(0, -0.3, 0))
			weapon.add_child(roll)
			weapon.add_child(Util.cylinder(0.075, 0.12, Util.mat(Color(0.2, 0.2, 0.25)), Vector3(0, -0.45, 0)))
		"printer":
			weapon.add_child(Util.box(Vector3(0.3, 0.45, 0.16), Util.mat(Color(0.2, 0.22, 0.3), true), Vector3(0, -0.2, 0.05)))
			weapon.add_child(Util.box(Vector3(0.22, 0.12, 0.02), Util.glow(Color(0.3, 0.9, 1.0), 1.5), Vector3(0, -0.12, 0.14)))
			weapon.add_child(Util.box(Vector3(0.2, 0.25, 0.01), Util.mat(Color(1, 0.95, 0.6)), Vector3(0, -0.5, 0.05)))
		"walkie":
			weapon.add_child(Util.box(Vector3(0.18, 0.4, 0.12), Util.mat(Color(0.1, 0.1, 0.1), true), Vector3(0, -0.15, 0.05)))
			weapon.add_child(Util.cylinder(0.025, 0.35, Util.mat(Color(0.1, 0.1, 0.1)), Vector3(0.05, -0.5, 0.05)))
			weapon.add_child(Util.sphere(0.035, Util.glow(Color(1, 0.2, 0.2), 2.5), Vector3(-0.05, 0.03, 0.12)))
		"brolly":
			weapon.add_child(Util.cylinder(0.03, 1.1, Util.mat(Color(0.15, 0.1, 0.1)), Vector3(0, -0.5, 0)))
			weapon.add_child(Util.cylinder(0.12, 0.7, Util.mat(Color(0.1, 0.1, 0.3), true), Vector3(0, -0.6, 0), false, 0.03))
			weapon.add_child(Util.torus(0.04, 0.08, Util.mat(Color(0.15, 0.1, 0.1)), Vector3(0.04, 0.05, 0)))
		"fish":
			var f := Util.sphere(0.2, Util.mat(Color(0.55, 0.65, 0.75), true), Vector3(0, -0.35, 0))
			f.scale = Vector3(0.6, 1.8, 0.35)
			weapon.add_child(f)
			weapon.add_child(Util.prism(Vector3(0.3, 0.2, 0.05), Util.mat(Color(0.5, 0.6, 0.7)), Vector3(0, -0.8, 0)))
			weapon.add_child(Util.sphere(0.03, Util.mat(Color(0.05, 0.05, 0.05)), Vector3(0.06, -0.08, 0.06)))
		"cone":
			var cone := Util.cylinder(0.22, 0.8, Util.mat(Color(1, 0.45, 0.05), true), Vector3(0, -0.4, 0), false, 0.04)
			cone.rotation.x = PI
			weapon.add_child(cone)
			var stripe := Util.cylinder(0.15, 0.1, Util.mat(Color.WHITE), Vector3(0, -0.45, 0), false, 0.12)
			stripe.rotation.x = PI
			weapon.add_child(stripe)


## A torch held out in front at night, with a soft cartoon beam.
func set_torch(on: bool) -> void:
	if torch:
		torch.queue_free()
		torch = null
	if not on:
		return
	torch = Node3D.new()
	torch.position = Vector3(torso_r * 0.6, torso_h * 0.55, torso_r + 0.15)
	torso.add_child(torch)
	var t := Util.cylinder(0.07, 0.32, Util.mat(Color(0.15, 0.15, 0.2), true), Vector3.ZERO)
	t.rotation.x = PI / 2
	torch.add_child(t)
	var lens := Util.cylinder(0.09, 0.04, Util.glow(Color(1, 0.95, 0.7), 4.0), Vector3(0, 0, 0.17))
	lens.rotation.x = PI / 2
	torch.add_child(lens)
	var light := SpotLight3D.new()
	light.light_color = Color(1, 0.94, 0.75)
	light.light_energy = 6.0
	light.spot_range = 16.0
	light.spot_angle = 28.0
	light.spot_attenuation = 0.6
	light.shadow_enabled = false
	light.position = Vector3(0, 0, 0.2)
	light.rotation.x = deg_to_rad(-25) + PI  # SpotLight shines down -Z, so flip to face forward and tilt down
	light.rotation.y = 0.0
	torch.add_child(light)
	# Beam: a long transparent cone
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 1.6
	cm.height = 6.0
	cm.radial_segments = 16
	beam.mesh = cm
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bm.albedo_color = Color(1, 0.9, 0.55, 0.09)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.material_override = bm
	beam.rotation.x = PI / 2 - deg_to_rad(-25) * -1.0
	beam.position = Vector3(0, -1.2, 3.1)
	beam.rotation.x = deg_to_rad(90 + 25)
	torch.add_child(beam)


func idle_pose() -> void:
	arm_l.rotation.x = -0.7
