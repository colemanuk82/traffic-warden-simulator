extends Node3D
## A cartoon warden built from an outfit (see catalogue.gd). Faces +Z.
## Exposes limbs so the owner can animate walking, punching and diving.

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
var height := 2.2
var torso_r := 0.36
var torso_h := 0.95
var walk_t := 0.0
var punch_t := 0.0


func build(outfit: Dictionary) -> void:
	for c in get_children():
		c.queue_free()
	var type_id: String = outfit.get("type", "classic")
	var shape: Array = SHAPES.get(type_id, SHAPES.classic)
	var leg_len: float = shape[0]
	var tr: float = shape[1]
	var th: float = shape[2]
	var hr: float = shape[3]
	var hunch: float = shape[4]
	torso_r = tr
	torso_h = th
	weapon = null
	torch = null

	var skin: Color = Catalogue.find("skin", outfit.get("skin", "s2")).color
	var hair_col: Color = Catalogue.find("hair_color", outfit.get("hair_color", "brown")).color
	var uni := Catalogue.find("uniform", outfit.get("uniform", "hivis"))
	var robot := type_id == "robot"
	if robot:
		skin = Color(0.7, 0.75, 0.8)
	elif type_id == "alien":
		skin = Color(0.5, 0.9, 0.45)
	var gold: bool = uni.id == "gold"
	var skin_m := Util.metal(skin) if robot else Util.mat(skin, true)
	var jacket_m := Util.metal(uni.jacket) if gold else Util.mat(uni.jacket, true)
	var trouser_m := Util.metal(uni.trousers) if gold else Util.mat(uni.trousers, true)
	var dark := Color(0.08, 0.08, 0.12)

	body = Node3D.new()
	add_child(body)

	# Legs swing from the hips
	var leg_w := tr * 0.5
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		leg.position = Vector3(side * tr * 0.42, leg_len, 0)
		body.add_child(leg)
		leg.add_child(Util.capsule(leg_w * 0.55, leg_len + 0.1, trouser_m, Vector3(0, -leg_len * 0.5, 0)))
		leg.add_child(Util.box(Vector3(leg_w * 1.1, 0.12, 0.34), Util.mat(dark, true), Vector3(0, -leg_len + 0.04, 0.06)))
		if side < 0.0:
			leg_l = leg
		else:
			leg_r = leg

	# Torso (leans forward for granny)
	torso = Node3D.new()
	torso.position = Vector3(0, leg_len, 0)
	torso.rotation.x = hunch
	body.add_child(torso)
	if robot:
		torso.add_child(Util.box(Vector3(tr * 2.0, th, tr * 1.6), jacket_m, Vector3(0, th * 0.5, 0)))
	else:
		torso.add_child(Util.capsule(tr, th + tr * 0.6, jacket_m, Vector3(0, th * 0.5, 0)))
	var stripe_m := Util.mat(uni.stripe)
	torso.add_child(Util.cylinder(tr * 1.03, 0.08, stripe_m, Vector3(0, th * 0.35, 0)))
	if uni.id in ["hivis", "orange", "pink", "council", "ticket"]:
		torso.add_child(Util.cylinder(tr * 1.03, 0.08, stripe_m, Vector3(0, th * 0.6, 0)))
	if uni.id == "tux":
		torso.add_child(Util.box(Vector3(tr * 0.7, th * 0.6, 0.05), Util.mat(Color.WHITE), Vector3(0, th * 0.6, tr * 0.93)))
		torso.add_child(Util.box(Vector3(0.22, 0.1, 0.06), Util.mat(Color(0.8, 0.1, 0.15)), Vector3(0, th * 0.88, tr * 0.98)))
	if uni.id == "camo":
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in 9:
			var a := rng.randf() * TAU
			var y := rng.randf_range(0.15, 0.85) * th
			var blob := Util.sphere(0.1, Util.mat(Color(0.22, 0.28, 0.15) if i % 2 else Color(0.5, 0.45, 0.3)),
				Vector3(sin(a) * tr * 0.92, y, cos(a) * tr * 0.92))
			blob.scale = Vector3(1.2, 0.8, 0.5)
			torso.add_child(blob)
	if gold:
		torso.add_child(Util.label3d("$", 60, Color(1, 0.95, 0.5), Vector3(0, th * 0.55, tr + 0.05)))
	if uni.id == "chief":
		for side in [-1.0, 1.0]:
			torso.add_child(Util.box(Vector3(0.3, 0.06, 0.22), Util.metal(Color(1, 0.8, 0.2), false), Vector3(side * tr * 0.8, th * 0.98, 0)))
		for i in 3:
			torso.add_child(Util.sphere(0.05, Util.metal(Color(1, 0.8, 0.2), false), Vector3(0, th * (0.3 + i * 0.2), tr * 0.98)))
	_build_vest(outfit.get("vest", "none"), tr, th)
	# Badge
	torso.add_child(Util.box(Vector3(0.14, 0.14, 0.04), Util.metal(Color(0.85, 0.85, 0.9), false), Vector3(-tr * 0.45, th * 0.72, tr * 0.88)))

	# Arms swing from the shoulders and point straight down at rest
	var shoulder_y := th * 0.82
	for side in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.position = Vector3(side * (tr + 0.08), shoulder_y, 0)
		torso.add_child(arm)
		arm.add_child(Util.capsule(0.1, 0.6, jacket_m, Vector3(0, -0.26, 0)))
		var fist_r := 0.12
		var fist_m: Material = skin_m
		if outfit.get("accessory", "") == "gloves":
			fist_r = 0.2
			fist_m = Util.mat(Color(0.9, 0.12, 0.12), true)
		arm.add_child(Util.sphere(fist_r, fist_m, Vector3(0, -0.6, 0)))
		if side < 0.0:
			arm_l = arm
			notepad = Util.box(Vector3(0.3, 0.04, 0.38), Util.mat(Color.WHITE, true), Vector3(0, -0.62, 0.22))
			arm.add_child(notepad)
		else:
			arm_r = arm

	# Head
	head = Node3D.new()
	head.position = Vector3(0, th + hr * 0.55, 0)
	torso.add_child(head)
	if robot:
		head.add_child(Util.box(Vector3(hr * 1.8, hr * 1.6, hr * 1.7), skin_m))
		head.add_child(Util.box(Vector3(hr * 1.5, hr * 0.35, 0.05), Util.glow(Color(0.2, 1.0, 1.0), 3.0), Vector3(0, hr * 0.1, hr * 0.86)))
		head.add_child(Util.cylinder(0.03, 0.35, Util.metal(Color(0.5, 0.5, 0.55)), Vector3(0, hr * 0.8 + 0.17, 0)))
		head.add_child(Util.sphere(0.07, Util.glow(Color(1, 0.2, 0.2), 3.0), Vector3(0, hr * 0.8 + 0.37, 0)))
	else:
		head.add_child(Util.sphere(hr, skin_m))
		var eye_r := 0.06 if type_id != "alien" else 0.12
		for side in [-1.0, 1.0]:
			var eye_pos := Vector3(side * hr * 0.36, hr * 0.12, hr * 0.9)
			if type_id == "alien":
				var eye := Util.sphere(eye_r, Util.mat(dark), eye_pos)
				eye.scale = Vector3(0.8, 1.3, 0.5)
				head.add_child(eye)
			else:
				head.add_child(Util.sphere(eye_r * 1.6, Util.mat(Color.WHITE), eye_pos + Vector3(0, 0, -0.02)))
				head.add_child(Util.sphere(eye_r, Util.mat(dark), eye_pos + Vector3(0, 0, 0.06)))
		head.add_child(Util.sphere(hr * 0.16, skin_m, Vector3(0, -hr * 0.05, hr * 0.98)))
		head.add_child(Util.box(Vector3(hr * 0.5, 0.04, 0.04), Util.mat(Color(0.4, 0.1, 0.1)), Vector3(0, -hr * 0.42, hr * 0.86)))
		if type_id == "alien":
			for side in [-1.0, 1.0]:
				var stalk := Util.cylinder(0.025, 0.4, Util.mat(skin), Vector3(side * 0.18, hr + 0.15, 0))
				stalk.rotation.z = -side * 0.4
				head.add_child(stalk)
				head.add_child(Util.sphere(0.07, Util.glow(Color(1, 0.9, 0.2), 2.0), Vector3(side * 0.28, hr + 0.36, 0)))
		if type_id == "granny":
			for side in [-1.0, 1.0]:
				head.add_child(Util.torus(0.07, 0.1, Util.mat(Color(0.6, 0.4, 0.8)), Vector3(side * hr * 0.36, hr * 0.12, hr * 0.97)))
				head.get_child(head.get_child_count() - 1).rotation.x = PI / 2
		if outfit.get("hair", "short") != "bald" or type_id == "granny":
			_build_hair(outfit.get("hair", "short") if outfit.get("hair") != "bald" else "bun", hr, hair_col)
	_build_hat(outfit.get("hat", "cap"), hr, robot)
	_build_accessory(outfit.get("accessory", "none"), hr, tr, th, hair_col)
	height = leg_len + th + hr * 2.0 + 0.3


func _build_hair(style: String, hr: float, col: Color) -> void:
	var m := Util.mat(col, true)
	var cap := Util.hemisphere(hr * 1.07, m, Vector3(0, hr * 0.02, -hr * 0.05))
	cap.rotation.x = -0.5
	match style:
		"short":
			head.add_child(cap)
		"spiky":
			head.add_child(cap)
			for i in 7:
				var a := -1.2 + i * 0.4
				var spike := Util.cylinder(0.09, 0.32, m, Vector3(sin(a) * hr * 0.5, hr * 0.85, -cos(a) * 0.1 - 0.05), false, 0.0)
				spike.rotation = Vector3(-0.3, 0, -a * 0.6)
				head.add_child(spike)
		"afro":
			head.add_child(Util.sphere(hr * 1.35, m, Vector3(0, hr * 0.55, -hr * 0.4)))
		"ponytail":
			head.add_child(cap)
			var tail := Util.capsule(0.11, 0.6, m, Vector3(0, -hr * 0.1, -hr * 1.1))
			tail.rotation.x = 0.4
			head.add_child(tail)
		"bun":
			head.add_child(cap)
			head.add_child(Util.sphere(hr * 0.45, m, Vector3(0, hr * 1.05, -hr * 0.25)))
		"long":
			head.add_child(cap)
			head.add_child(Util.box(Vector3(hr * 2.0, hr * 1.9, hr * 0.5), m, Vector3(0, -hr * 0.45, -hr * 0.7)))
		"mohawk":
			for i in 5:
				var z := hr * (0.6 - i * 0.35)
				var fin := Util.box(Vector3(0.08, 0.32, 0.22), m, Vector3(0, hr * 0.95 - absf(z) * 0.35, z))
				head.add_child(fin)
		"mullet":
			head.add_child(cap)
			head.add_child(Util.box(Vector3(hr * 1.5, hr * 1.4, hr * 0.4), m, Vector3(0, -hr * 0.55, -hr * 0.75)))
		"quiff":
			head.add_child(cap)
			var quiff := Util.capsule(0.16, 0.6, m, Vector3(0, hr * 0.95, hr * 0.35))
			quiff.rotation.x = 1.1
			head.add_child(quiff)
		"combover":
			var flat := Util.hemisphere(hr * 1.04, m, Vector3(-0.03, hr * 0.15, -hr * 0.1))
			flat.scale = Vector3(1, 0.35, 1)
			head.add_child(flat)
			head.add_child(Util.box(Vector3(hr * 1.8, 0.05, 0.12), m, Vector3(0.05, hr * 0.98, 0.0)))
		_:
			head.add_child(cap)


func _build_vest(style: String, tr: float, th: float) -> void:
	if style == "none":
		return
	var cols := {"utility": Color(0.35, 0.4, 0.3), "tool": Color(0.55, 0.4, 0.25), "radio": Color(0.15, 0.15, 0.2),
		"stab": Color(0.2, 0.22, 0.28), "tactical": Color(0.15, 0.17, 0.12), "fishing": Color(0.45, 0.5, 0.4),
		"medal": Color(0.8, 0.1, 0.15)}
	var c: Color = cols.get(style, Color(0.3, 0.3, 0.3))
	if style == "medal":
		var sash := Util.box(Vector3(0.18, th * 1.3, 0.05), Util.mat(c, true), Vector3(0, th * 0.55, tr * 0.95))
		sash.rotation.z = 0.6
		torso.add_child(sash)
		for i in 3:
			torso.add_child(Util.cylinder(0.07, 0.03, Util.metal(Color(1, 0.8, 0.2), false), Vector3(-0.12 + i * 0.12, th * (0.45 + i * 0.12), tr * 1.02)))
			torso.get_child(torso.get_child_count() - 1).rotation.x = PI / 2
		return
	var shell := Util.cylinder(tr * 1.09, th * 0.62, Util.mat(c, true), Vector3(0, th * 0.55, 0))
	torso.add_child(shell)
	var pocket := c.lightened(0.2) if style != "stab" else c.darkened(0.3)
	match style:
		"utility", "fishing", "tool":
			for side in [-1.0, 1.0]:
				for row in 2:
					torso.add_child(Util.box(Vector3(0.18, 0.15, 0.08), Util.mat(pocket, true), Vector3(side * tr * 0.42, th * (0.35 + row * 0.22), tr * 1.06)))
			if style == "tool":
				torso.add_child(Util.box(Vector3(0.05, 0.3, 0.05), Util.metal(Color(0.7, 0.7, 0.75), false), Vector3(tr * 0.42, th * 0.62, tr * 1.12)))
				torso.add_child(Util.box(Vector3(0.12, 0.08, 0.06), Util.mat(Color(0.85, 0.2, 0.1)), Vector3(tr * 0.42, th * 0.48, tr * 1.12)))
			if style == "fishing":
				torso.add_child(Util.sphere(0.06, Util.mat(Color(1, 0.3, 0.1)), Vector3(-tr * 0.42, th * 0.75, tr * 1.08)))
		"radio":
			torso.add_child(Util.box(Vector3(0.14, 0.24, 0.1), Util.mat(Color(0.1, 0.1, 0.1), true), Vector3(-tr * 0.45, th * 0.78, tr * 1.06)))
			torso.add_child(Util.cylinder(0.02, 0.25, Util.mat(Color(0.1, 0.1, 0.1)), Vector3(-tr * 0.4, th * 0.98, tr * 1.06)))
			torso.add_child(Util.sphere(0.04, Util.glow(Color(0.2, 1, 0.3), 2.0), Vector3(-tr * 0.5, th * 0.86, tr * 1.12)))
		"stab":
			torso.add_child(Util.box(Vector3(tr * 1.2, 0.12, 0.05), Util.mat(Color(0.9, 0.9, 0.9)), Vector3(0, th * 0.7, tr * 1.08)))
			torso.add_child(Util.label3d("WARDEN", 18, Color(0.1, 0.1, 0.15), Vector3(0, th * 0.7, tr * 1.12)))
		"tactical":
			for i in 3:
				torso.add_child(Util.box(Vector3(0.14, 0.2, 0.09), Util.mat(pocket, true), Vector3(-tr * 0.5 + i * tr * 0.5, th * 0.4, tr * 1.06)))
			torso.add_child(Util.box(Vector3(tr * 1.6, 0.08, 0.06), Util.mat(Color(0.1, 0.1, 0.1)), Vector3(0, th * 0.62, tr * 1.08)))


func _build_hat(style: String, hr: float, robot: bool) -> void:
	var top := hr * (0.8 if robot else 0.92)
	var dark := Color(0.1, 0.1, 0.16)
	match style:
		"baseball", "baseball_back":
			var cap_col := Color(0.15, 0.3, 0.75)
			var hat := Node3D.new()
			hat.rotation.y = PI if style == "baseball_back" else 0.0
			head.add_child(hat)
			hat.add_child(Util.hemisphere(hr * 1.08, Util.mat(cap_col, true), Vector3(0, top - hr * 0.3, 0)))
			hat.add_child(Util.box(Vector3(hr * 1.3, 0.05, hr * 0.9), Util.mat(cap_col.darkened(0.25), true), Vector3(0, top - hr * 0.3, hr * 1.2)))
			hat.add_child(Util.sphere(0.06, Util.mat(cap_col.darkened(0.3)), Vector3(0, top + hr * 0.75, 0)))
			hat.add_child(Util.label3d("TW", 22, Color.WHITE, Vector3(0, top + hr * 0.15, hr * 1.02)))
		"inspector":
			head.add_child(Util.cylinder(hr * 1.2, 0.3, Util.mat(Color(0.95, 0.95, 0.95), true), Vector3(0, top + 0.12, 0)))
			head.add_child(Util.cylinder(hr * 1.22, 0.1, Util.mat(Color(0.08, 0.08, 0.1)), Vector3(0, top, 0)))
			head.add_child(Util.box(Vector3(hr * 1.5, 0.05, hr * 0.9), Util.mat(Color(0.05, 0.05, 0.08), true), Vector3(0, top - 0.04, hr * 1.25)))
			head.add_child(Util.box(Vector3(hr * 1.2, 0.04, 0.04), Util.metal(Color(1, 0.8, 0.2), false), Vector3(0, top + 0.02, hr * 1.25)))
			head.add_child(Util.sphere(0.09, Util.metal(Color(1, 0.8, 0.2), false), Vector3(0, top + 0.14, hr * 1.2)))
		"cap":
			head.add_child(Util.cylinder(hr * 1.15, 0.28, Util.mat(dark, true), Vector3(0, top + 0.1, 0)))
			head.add_child(Util.cylinder(hr * 1.17, 0.08, Util.mat(Color(0.95, 0.8, 0.1)), Vector3(0, top, 0)))
			head.add_child(Util.box(Vector3(hr * 1.5, 0.05, hr * 0.9), Util.mat(Color(0.05, 0.05, 0.08), true), Vector3(0, top - 0.04, hr * 1.25)))
			head.add_child(Util.box(Vector3(0.16, 0.12, 0.04), Util.metal(Color(0.95, 0.85, 0.3), false), Vector3(0, top + 0.12, hr * 1.16)))
		"bobble":
			var dome := Util.hemisphere(hr * 1.08, Util.mat(Color(0.85, 0.15, 0.2), true), Vector3(0, top - hr * 0.35, 0))
			head.add_child(dome)
			head.add_child(Util.cylinder(hr * 1.1, 0.14, Util.mat(Color.WHITE), Vector3(0, top - hr * 0.3, 0)))
			head.add_child(Util.sphere(0.15, Util.mat(Color.WHITE, true), Vector3(0, top + hr * 0.75, 0)))
		"hardhat":
			head.add_child(Util.hemisphere(hr * 1.1, Util.mat(Color(1, 0.8, 0.1), true), Vector3(0, top - hr * 0.3, 0)))
			head.add_child(Util.cylinder(hr * 1.35, 0.05, Util.mat(Color(1, 0.8, 0.1)), Vector3(0, top - hr * 0.3, 0.05)))
		"tophat":
			head.add_child(Util.cylinder(hr * 0.75, 0.65, Util.mat(dark, true), Vector3(0, top + 0.3, 0)))
			head.add_child(Util.cylinder(hr * 1.2, 0.05, Util.mat(dark, true), Vector3(0, top - 0.02, 0)))
			head.add_child(Util.cylinder(hr * 0.77, 0.1, Util.mat(Color(0.75, 0.1, 0.15)), Vector3(0, top + 0.06, 0)))
		"cone":
			head.add_child(Util.cylinder(hr * 0.85, 0.85, Util.mat(Color(1, 0.45, 0.05), true), Vector3(0, top + 0.35, 0), false, 0.04))
			head.add_child(Util.cylinder(hr * 0.55, 0.12, Util.mat(Color.WHITE), Vector3(0, top + 0.4, 0), false, hr * 0.45))
		"helmet":
			var h := Util.sphere(hr * 1.05, Util.mat(Color(0.08, 0.1, 0.25), true), Vector3(0, top + 0.05, 0))
			h.scale = Vector3(1, 1.4, 1.05)
			head.add_child(h)
			head.add_child(Util.sphere(0.07, Util.metal(Color(0.85, 0.85, 0.9), false), Vector3(0, top + hr * 1.45, 0)))
			head.add_child(Util.box(Vector3(0.2, 0.2, 0.04), Util.metal(Color(0.85, 0.85, 0.9), false), Vector3(0, top + 0.15, hr * 1.06)))
		"crown":
			var gold := Util.metal(Color(1, 0.8, 0.2))
			head.add_child(Util.cylinder(hr * 0.8, 0.25, gold, Vector3(0, top + 0.08, 0)))
			for i in 6:
				var a := i * TAU / 6.0
				head.add_child(Util.sphere(0.06, Util.mat(Color(0.9, 0.1, 0.3) if i % 2 else Color(0.2, 0.5, 1.0)),
					Vector3(sin(a) * hr * 0.8, top + 0.27, cos(a) * hr * 0.8)))


func _build_accessory(style: String, hr: float, tr: float, th: float, hair_col: Color) -> void:
	match style:
		"shades":
			head.add_child(Util.box(Vector3(hr * 1.6, 0.14, 0.06), Util.mat(Color(0.05, 0.05, 0.08)), Vector3(0, hr * 0.14, hr * 0.98)))
		"tache":
			var t := Util.capsule(0.06, hr * 0.9, Util.mat(hair_col.darkened(0.2), true), Vector3(0, -hr * 0.22, hr * 0.95))
			t.rotation.z = PI / 2
			head.add_child(t)
		"beard":
			var b := Util.sphere(hr * 0.7, Util.mat(hair_col, true), Vector3(0, -hr * 0.55, hr * 0.5))
			b.scale = Vector3(1.1, 0.9, 0.7)
			head.add_child(b)
		"bowtie":
			for side in [-1.0, 1.0]:
				var w := Util.prism(Vector3(0.18, 0.16, 0.06), Util.mat(Color(0.85, 0.1, 0.2)), Vector3(side * 0.1, th * 0.98, tr * 0.8))
				w.rotation.z = side * PI / 2
				torso.add_child(w)
		"headphones":
			var band := Util.torus(hr * 1.02, hr * 1.12, Util.mat(Color(0.15, 0.15, 0.2), true), Vector3(0, 0.05, 0))
			band.rotation.z = PI / 2
			head.add_child(band)
			for side in [-1.0, 1.0]:
				var cup := Util.cylinder(0.14, 0.12, Util.mat(Color(0.95, 0.2, 0.4), true), Vector3(side * hr * 1.05, 0, 0))
				cup.rotation.z = PI / 2
				head.add_child(cup)
		"parrot":
			var p := Node3D.new()
			p.position = Vector3(tr + 0.02, th * 0.95, -0.05)
			torso.add_child(p)
			p.add_child(Util.capsule(0.11, 0.38, Util.mat(Color(0.95, 0.15, 0.1), true), Vector3(0, 0.2, 0)))
			p.add_child(Util.sphere(0.1, Util.mat(Color(0.95, 0.15, 0.1), true), Vector3(0, 0.42, 0.04)))
			p.add_child(Util.cylinder(0.04, 0.1, Util.mat(Color(1, 0.8, 0.1)), Vector3(0, 0.4, 0.15), false, 0.0))
			p.get_child(2).rotation.x = PI / 2
			var wing := Util.box(Vector3(0.05, 0.25, 0.18), Util.mat(Color(0.15, 0.5, 0.95)), Vector3(0.1, 0.22, 0))
			p.add_child(wing)
		"scarf":
			torso.add_child(Util.torus(tr * 0.6, tr * 0.95, Util.mat(Color(0.2, 0.6, 0.3), true), Vector3(0, th * 0.98, 0)))
			torso.add_child(Util.box(Vector3(0.16, 0.45, 0.06), Util.mat(Color(0.85, 0.15, 0.15)), Vector3(tr * 0.4, th * 0.75, tr * 0.95)))
		"cape":
			cape = Node3D.new()
			cape.position = Vector3(0, th * 0.95, -tr * 0.9)
			torso.add_child(cape)
			var cloth := Util.box(Vector3(tr * 2.4, th * 1.2, 0.05), Util.mat(Color(0.85, 0.1, 0.15), true), Vector3(0, -th * 0.6, 0))
			cape.add_child(cloth)
			cape.rotation.x = 0.15
		"pigeon":
			var p := Node3D.new()
			p.position = Vector3(-tr - 0.02, th * 0.95, -0.05)
			torso.add_child(p)
			var grey := Util.mat(Color(0.6, 0.62, 0.68), true)
			var body_m := Util.sphere(0.13, grey, Vector3(0, 0.15, 0))
			body_m.scale = Vector3(0.9, 0.9, 1.3)
			p.add_child(body_m)
			p.add_child(Util.sphere(0.08, Util.mat(Color(0.4, 0.55, 0.5), true), Vector3(0, 0.3, 0.1)))
			p.add_child(Util.cylinder(0.03, 0.08, Util.mat(Color(0.95, 0.7, 0.3)), Vector3(0, 0.29, 0.2), false, 0.0))
			p.get_child(2).rotation.x = PI / 2
		"lanyard":
			torso.add_child(Util.torus(tr * 0.55, tr * 0.62, Util.mat(Color(1, 0.8, 0.2)), Vector3(0, th * 0.85, tr * 0.25)))
			torso.get_child(torso.get_child_count() - 1).rotation.x = 1.1
			torso.add_child(Util.box(Vector3(0.2, 0.26, 0.03), Util.mat(Color.WHITE, true), Vector3(0, th * 0.5, tr * 1.0)))


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
		arm_r.rotation.x = -PI * 0.5 * reach
		torso.rotation.y = -0.35 * reach


func punch() -> void:
	punch_t = 0.3


## Puts a melee weapon in the right hand (see career.gd WEAPONS). "fists" removes it.
func set_weapon(id: String) -> void:
	if weapon:
		weapon.queue_free()
		weapon = null
	if id == "fists" or arm_r == null:
		return
	weapon = Node3D.new()
	weapon.position = Vector3(0, -0.62, 0.05)
	arm_r.add_child(weapon)
	match id:
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
