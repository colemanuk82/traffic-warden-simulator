extends RefCounted
## Fills the empty ground of every level with houses, shops and parks, so the streets are lined
## with buildings on all sides; plus the hill village and steep terrace themes.

const Util := preload("res://scripts/util.gd")

const CELL := 11.0
const VIEW := 30.0  # cells further than this from the street are out of shot, so stay empty


# ---------------------------------------------------------------- filling the gaps

static func dress(w) -> void:
	var theme: String = w.def.theme
	if theme in ["carpark", "multistorey"]:
		return
	var reg: Rect2 = w.region
	var x := reg.position.x
	while x <= reg.end.x - CELL:
		var z := reg.position.y
		while z <= reg.end.y - CELL:
			_fill_cell(w, theme, Rect2(x + 1.0, z + 1.0, CELL - 2.0, CELL - 2.0))
			z += CELL
		x += CELL


static func _fill_cell(w, theme: String, r: Rect2) -> void:
	if w._blocked(r) or not w._scatter_allowed(r.get_center()):
		return
	if theme == "seaside" and r.end.y > 9.0:
		return
	var c := r.get_center()
	var best_d := INF
	var best_q := c
	for wr in w.walk_rects:
		var q := Vector2(clampf(c.x, wr.position.x, wr.end.x), clampf(c.y, wr.position.y, wr.end.y))
		var d := c.distance_to(q)
		if d < best_d:
			best_d = d
			best_q = q
	if best_d > VIEW:
		return
	var rng: RandomNumberGenerator = w.rng
	if best_d < 12.0 and rng.randf() < 0.8:
		var dir := best_q - c
		var facing := Vector3(signf(dir.x), 0, 0) if absf(dir.x) > absf(dir.y) else Vector3(0, 0, signf(dir.y))
		if facing == Vector3.ZERO:
			facing = Vector3(0, 0, 1)
		var dressed := _building(w, theme, r, facing)
		match "" if dressed else season(w):
			"halloween":
				_spooky_front(w, r, facing)
			"xmas":
				_festive_front(w, r, facing)
	else:
		w.footprints.append(r)
		park_tile(w, theme, r)
		match season(w):
			"halloween":
				_spooky_park(w, r)
			"xmas":
				_festive_park(w, r)


## Puts up a building on a spare plot. Returns true if its maker already did the seasonal dressing.
static func _building(w, theme: String, r: Rect2, facing: Vector3) -> bool:
	var rng: RandomNumberGenerator = w.rng
	if theme == "halloween" and w.has_method("_spooky_house"):
		w._spooky_house(r, rng.randf_range(4.5, 7), facing, 1.5)
		return true
	if theme == "xmas" and w.has_method("_xmas_shop"):
		w._xmas_shop(r, rng.randf_range(5, 8), facing, 0.5)
		return true
	match theme:
		"town":
			w._shop(r, rng.randf_range(5, 10), facing, 0.3)
		"seaside":
			w._hotel(r, rng.randf_range(6, 12), facing, 0.5)
		"snow":
			w._cottage(r, rng.randf_range(3.5, 5), facing, 1.5)
		"city":
			w._tower(r, rng.randf_range(10, 26), facing, 0.3)
		"posh":
			w._mansion(r, rng.randf_range(6, 9), facing, 1.5)
		"terraces":
			terrace(w, r, rng.randf_range(6, 8), facing, 0.5)
		"hills":
			_stone_cottage(w, r, rng.randf_range(4, 6), facing, 1.5)
		_:
			# Mix a corner shop into the houses now and then
			if rng.randf() < 0.25:
				w._shop(r, rng.randf_range(5, 7), facing, 0.3)
			else:
				w._suburb_house(r, rng.randf_range(4.5, 8), facing, 1.5)
	return false


## A square of park: mown grass, trees, flower beds, a bench and the odd pond.
static func park_tile(w, theme: String, r: Rect2) -> void:
	var rng: RandomNumberGenerator = w.rng
	w.park_rects.append(r)
	var snow := theme == "snow" or season(w) == "xmas"
	var spooky := season(w) == "halloween"
	var night: bool = w.def.get("night", false)
	var grass := Color(0.42, 0.74, 0.33) if not snow else Color(0.95, 0.97, 1.0)
	if spooky:
		grass = Color(0.36, 0.42, 0.22)  # autumn grass
	if theme == "city":
		grass = Color(0.2, 0.4, 0.22)
	var c := r.get_center()
	# Mown stripes
	var stripes := 3
	for i in stripes:
		var sw := (r.size.x + 2.0) / stripes
		var col := grass if i % 2 == 0 else grass.lightened(0.08)
		w.add_child(Util.box(Vector3(sw, 0.06, r.size.y + 2.0), col, Vector3(r.position.x - 1.0 + sw * (i + 0.5), 0.02, c.y)))
	var roll := rng.randf()
	if spooky and roll < 0.42:
		_spooky_park_feature(w, c, rng, roll)
	elif roll < 0.1 and not snow:
		# Duck pond
		w.add_child(Util.cylinder(3.2, 0.12, Color(0.55, 0.45, 0.3), Vector3(c.x, 0.03, c.y)))
		w.add_child(Util.cylinder(2.8, 0.1, Color(0.3, 0.55, 0.85), Vector3(c.x, 0.06, c.y)))
		for i in 2:
			var d := Vector3(c.x + rng.randf_range(-1.5, 1.5), 0.25, c.y + rng.randf_range(-1.5, 1.5))
			w.add_child(Util.sphere(0.22, Color.WHITE, d, true))
			w.add_child(Util.sphere(0.12, Color.WHITE, d + Vector3(0.2, 0.2, 0), true))
			w.add_child(Util.cylinder(0.04, 0.12, Color(1, 0.6, 0.1), d + Vector3(0.32, 0.2, 0)))
	elif roll < 0.3:
		# Flower bed
		var bed := Rect2(c - Vector2(2.2, 1.2), Vector2(4.4, 2.4))
		w.add_child(Util.box(Vector3(bed.size.x, 0.25, bed.size.y), Color(0.45, 0.3, 0.2), Vector3(c.x, 0.12, c.y), true))
		var cols := [Color(1, 0.3, 0.35), Color(1, 0.85, 0.2), Color(0.7, 0.4, 1.0), Color(1, 0.6, 0.85), Color.WHITE]
		for i in 14:
			var fp := Vector3(rng.randf_range(bed.position.x + 0.3, bed.end.x - 0.3), 0.38, rng.randf_range(bed.position.y + 0.3, bed.end.y - 0.3))
			w.add_child(Util.sphere(0.16, cols[rng.randi() % cols.size()], fp))
	elif roll < 0.42:
		# Bench, bin and a lamp
		w.add_child(Util.box(Vector3(1.8, 0.12, 0.5), Color(0.55, 0.35, 0.2), Vector3(c.x, 0.5, c.y), true))
		w.add_child(Util.box(Vector3(1.8, 0.5, 0.1), Color(0.55, 0.35, 0.2), Vector3(c.x, 0.8, c.y - 0.25), true))
		for bx in [-0.75, 0.75]:
			w.add_child(Util.box(Vector3(0.1, 0.5, 0.45), Color(0.2, 0.2, 0.22), Vector3(c.x + bx, 0.25, c.y)))
		w.add_child(Util.cylinder(0.25, 0.8, Color(0.2, 0.4, 0.25), Vector3(c.x + 1.6, 0.4, c.y)))
		w.add_child(Util.box(Vector3(0.2, 3.6, 0.2), Color(0.2, 0.2, 0.25), Vector3(c.x - 1.8, 1.8, c.y)))
		w.add_child(Util.sphere(0.3, Util.glow(Color(1, 0.9, 0.6), 2.5 if night else 0.6), Vector3(c.x - 1.8, 3.7, c.y)))
	# Trees round the edge
	var trees := rng.randi_range(1, 3)
	for i in trees:
		var tp := Vector3(rng.randf_range(r.position.x + 1.0, r.end.x - 1.0), 0, rng.randf_range(r.position.y + 1.0, r.end.y - 1.0))
		if Vector2(tp.x, tp.z).distance_to(c) < 3.4:
			tp.x = r.position.x + 1.2 if tp.x < c.x else r.end.x - 1.2
		if snow:
			w._pine(tp)
		elif spooky:
			if rng.randf() < 0.5 and w.has_method("_dead_tree"):
				w._dead_tree(tp)
			else:
				autumn_tree(w, tp, rng)
		else:
			park_tree(w, tp, rng)


## Halloween parks: a murky bubbling pond, a pumpkin patch or a crooked bench under a lantern.
static func _spooky_park_feature(w, c: Vector2, rng: RandomNumberGenerator, roll: float) -> void:
	if roll < 0.12:
		w.add_child(Util.cylinder(3.2, 0.12, Color(0.3, 0.25, 0.18), Vector3(c.x, 0.03, c.y)))
		w.add_child(Util.cylinder(2.8, 0.1, Color(0.25, 0.4, 0.2), Vector3(c.x, 0.06, c.y)))
		for i in 5:
			var b := Vector3(c.x + rng.randf_range(-1.8, 1.8), 0.14, c.y + rng.randf_range(-1.8, 1.8))
			w.add_child(Util.sphere(rng.randf_range(0.08, 0.18), Util.glow(Color(0.5, 1.0, 0.3), 0.8), b))
	elif roll < 0.3:
		w.add_child(Util.box(Vector3(4.4, 0.2, 2.4), Color(0.3, 0.2, 0.12), Vector3(c.x, 0.1, c.y), true))
		for i in 5:
			var pp := Vector3(c.x + rng.randf_range(-1.8, 1.8), 0.2, c.y + rng.randf_range(-0.9, 0.9))
			if w.has_method("_pumpkin"):
				w._pumpkin(pp)
			else:
				w.add_child(Util.sphere(0.35, Color(1, 0.5, 0.05), pp + Vector3(0, 0.25, 0), true))
	else:
		w.add_child(Util.box(Vector3(1.8, 0.12, 0.5), Color(0.3, 0.22, 0.15), Vector3(c.x, 0.5, c.y), true))
		w.add_child(Util.box(Vector3(1.8, 0.5, 0.1), Color(0.3, 0.22, 0.15), Vector3(c.x, 0.8, c.y - 0.25), true))
		for bx in [-0.75, 0.75]:
			w.add_child(Util.box(Vector3(0.1, 0.5, 0.45), Color(0.15, 0.15, 0.17), Vector3(c.x + bx, 0.25, c.y)))
		w.add_child(Util.box(Vector3(0.2, 3.6, 0.2), Color(0.15, 0.15, 0.18), Vector3(c.x - 1.8, 1.8, c.y)))
		w.add_child(Util.sphere(0.3, Util.glow(Color(1, 0.55, 0.15), 2.5), Vector3(c.x - 1.8, 3.7, c.y)))


## A tree in autumn colours: orange, red and gold.
static func autumn_tree(w, p: Vector3, rng: RandomNumberGenerator) -> void:
	w.add_child(Util.cylinder(0.3, 2.6, Color(0.35, 0.24, 0.16), p + Vector3(0, 1.3, 0)))
	var leaf := [Color(0.95, 0.45, 0.1), Color(0.8, 0.2, 0.1), Color(0.95, 0.7, 0.15)][rng.randi() % 3] as Color
	w.add_child(Util.sphere(1.7, leaf, p + Vector3(0, 3.5, 0), true))
	w.add_child(Util.sphere(1.1, leaf.lightened(0.1), p + Vector3(-0.7, 4.3, 0.4), true))
	w.add_child(Util.sphere(1.0, leaf.darkened(0.1), p + Vector3(0.8, 3.9, -0.3), true))


static func park_tree(w, p: Vector3, rng: RandomNumberGenerator) -> void:
	var kind := rng.randi() % 3
	var trunk := Color(0.45, 0.3, 0.2)
	match kind:
		0:
			w._tree(p)
		1:
			# Tall round oak
			w.add_child(Util.cylinder(0.3, 2.6, trunk, p + Vector3(0, 1.3, 0)))
			var leaf := Color.from_hsv(rng.randf_range(0.24, 0.33), 0.6, rng.randf_range(0.45, 0.65))
			w.add_child(Util.sphere(1.8, leaf, p + Vector3(0, 3.6, 0), true))
			w.add_child(Util.sphere(1.2, leaf.lightened(0.1), p + Vector3(-0.8, 4.4, 0.4), true))
			w.add_child(Util.sphere(1.1, leaf.darkened(0.05), p + Vector3(0.9, 4.0, -0.3), true))
		2:
			# Blossom tree
			w.add_child(Util.cylinder(0.22, 2.0, trunk, p + Vector3(0, 1.0, 0)))
			var pink := Color(1.0, 0.7, 0.82) if rng.randf() < 0.6 else Color(1, 0.95, 0.95)
			w.add_child(Util.sphere(1.3, pink, p + Vector3(0, 2.8, 0), true))
			w.add_child(Util.sphere(0.9, pink.lightened(0.1), p + Vector3(0.5, 3.5, 0.2), true))


# ---------------------------------------------------------------- hill village and steep terraces

static func build_theme(w) -> void:
	match w.def.theme:
		"hills":
			w._line_buildings(Vector2(6, 9), Vector2(4, 6), 6.0, 2.5, func(r: Rect2, h: float, f: Vector3, s: float) -> void:
				if w.rng.randf() < 0.35:
					w._suburb_house(r, h, f, s)
				else:
					_stone_cottage(w, r, h, f, s))
			w._scatter(16, func(p: Vector3) -> void: _sheep(w, p))
			w._scatter(40, func(p: Vector3) -> void: park_tree(w, p, w.rng))
			w._scatter(10, func(p: Vector3) -> void: _haybale(w, p))
		"terraces":
			w._line_buildings(Vector2(4.5, 5.5), Vector2(6, 8), 7.0, 0.4, func(r: Rect2, h: float, f: Vector3, s: float) -> void:
				terrace(w, r, h, f, s))
			w._scatter(14, func(p: Vector3) -> void: park_tree(w, p, w.rng))


static func _stone_cottage(w, r: Rect2, h: float, facing: Vector3, setback: float) -> void:
	var rng: RandomNumberGenerator = w.rng
	var stone: Color = [Color(0.82, 0.76, 0.62), Color(0.75, 0.7, 0.6), Color(0.9, 0.86, 0.75), Color(0.95, 0.95, 0.92)][rng.randi() % 4]
	var node: Node3D = w._add_building(r, h, stone, facing)
	var s: Vector3 = node.get_meta("size")
	w._roof(node, [Color(0.35, 0.3, 0.3), Color(0.6, 0.35, 0.25), Color(0.75, 0.65, 0.4)][rng.randi() % 3])
	var door := Color.from_hsv(rng.randf(), 0.6, 0.55)
	w._part(node, Vector3(1.1, 2.0, 0.2), door, Vector3(0, 1.0, s.z / 2.0 + 0.05))
	w._windows(node, Color(0.6, 0.8, 0.95), 2, 2.2, 1.8)
	# Dry stone wall and a gate along the front garden
	w._part(node, Vector3(s.x - 0.2, 0.8, 0.6), Color(0.6, 0.57, 0.5), Vector3(0, 0.4, s.z / 2.0 + setback - 0.4))
	w.add_perch(node, Vector3(rng.randf_range(-s.x * 0.3, s.x * 0.3), 0.8, s.z / 2.0 + setback - 0.4))
	# Roses round the door
	for i in 5:
		w._part(node, Vector3(0.25, 0.25, 0.25), Color(1, 0.35, 0.45) if i % 2 else Color(0.3, 0.6, 0.25), Vector3(-0.8 + (i % 2) * 1.6, 0.6 + i * 0.35, s.z / 2.0 + 0.15))


## A narrow, brightly painted terraced house with a chimney, like the steep streets of Bristol.
static func terrace(w, r: Rect2, h: float, facing: Vector3, _setback: float) -> void:
	var rng: RandomNumberGenerator = w.rng
	var pastel := [Color(0.98, 0.7, 0.7), Color(0.7, 0.85, 1.0), Color(1.0, 0.92, 0.6), Color(0.75, 0.95, 0.8),
		Color(0.9, 0.75, 1.0), Color(1.0, 0.82, 0.6), Color(0.95, 0.95, 0.95)]
	var c: Color = pastel[rng.randi() % pastel.size()]
	var node: Node3D = w._add_building(r, h, c, facing)
	var s: Vector3 = node.get_meta("size")
	w._part(node, Vector3(s.x + 0.1, 0.35, s.z + 0.1), c.darkened(0.35), Vector3(0, s.y, 0))
	if not node.get_meta("low"):
		w._part(node, Vector3(0.8, 1.2, 0.8), Color(0.55, 0.35, 0.3), Vector3(s.x * 0.3, s.y + 0.6, -s.z * 0.2))
	w._part(node, Vector3(1.0, 2.1, 0.2), Color.from_hsv(rng.randf(), 0.7, 0.4), Vector3(-s.x * 0.2, 1.05, s.z / 2.0 + 0.05))
	w._part(node, Vector3(1.4, 1.2, 0.1), Color(0.6, 0.8, 0.95), Vector3(s.x * 0.18, 1.5, s.z / 2.0 + 0.04))
	w._windows(node, Color(0.6, 0.8, 0.95), 2, 2.4, 3.8)


static func _sheep(w, p: Vector3) -> void:
	var wool := Color(0.97, 0.97, 0.94)
	var face := Color(0.15, 0.13, 0.13)
	var body := Util.sphere(0.6, wool, p + Vector3(0, 0.75, 0), true)
	body.scale = Vector3(1.3, 0.9, 0.9)
	w.add_child(body)
	w.add_child(Util.sphere(0.28, face, p + Vector3(0.75, 0.95, 0), true))
	for x in [-0.4, 0.4]:
		for z in [-0.25, 0.25]:
			w.add_child(Util.cylinder(0.07, 0.45, face, p + Vector3(x, 0.22, z)))


static func _haybale(w, p: Vector3) -> void:
	var bale := Util.cylinder(0.8, 1.2, Color(0.9, 0.78, 0.4), p + Vector3(0, 0.8, 0), true)
	bale.rotation.x = PI / 2
	w.add_child(bale)


# ---------------------------------------------------------------- Halloween and Christmas dressing

## "halloween", "xmas" or "" for the level being built.
static func season(w) -> String:
	var d: Dictionary = w.def
	var sn: String = d.get("season", "")
	if sn != "":
		return sn
	if d.get("deco", "") == "xmas" or d.theme in ["xmas", "christmas"] or d.id in ["xmas", "ev_xmas"]:
		return "xmas"
	if d.theme in ["halloween", "spooky"] or d.id == "halloween":
		return "halloween"
	return ""


## Door position and the direction along the front of a filler building.
static func _front(w, r: Rect2, facing: Vector3) -> Array:
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	var depth := r.size.y if absf(facing.z) > 0.5 else r.size.x
	var width := r.size.x if absf(facing.z) > 0.5 else r.size.y
	var along := Vector3(facing.z, 0, -facing.x)
	var top := 3.0 if w._occludes(r) else 4.5
	return [c + facing * (depth / 2.0 + 0.35), along, width, top]


static func _lights_along(w, start: Vector3, along: Vector3, width: float, y: float, cols: Array) -> void:
	var n := int(width / 0.6)
	for i in n:
		var p := start + along * (-width / 2.0 + 0.3 + i * 0.6)
		w.add_child(Util.sphere(0.1, Util.glow(cols[i % cols.size()], 3.5), Vector3(p.x, y - absf(sin(i * 0.9)) * 0.15, p.z)))


static func pumpkin(w, p: Vector3, size := 0.35) -> void:
	var body := Util.sphere(size, Color(1, 0.5, 0.05), p + Vector3(0, size * 0.8, 0), true)
	body.scale = Vector3(1.2, 0.85, 1.2)
	w.add_child(body)
	w.add_child(Util.cylinder(0.05, 0.18, Color(0.3, 0.5, 0.15), p + Vector3(0, size * 1.6, 0)))
	for x in [-0.12, 0.12]:
		w.add_child(Util.box(Vector3(0.09, 0.09, 0.05), Util.glow(Color(1, 0.85, 0.2), 4.0), p + Vector3(x * size / 0.35, size * 0.95, size * 1.15)))


static func _spooky_front(w, r: Rect2, facing: Vector3) -> void:
	var f := _front(w, r, facing)
	var door: Vector3 = f[0]
	var along: Vector3 = f[1]
	for side in [-1.0, 1.0]:
		pumpkin(w, door + along * side * 1.0 + facing * 0.4, w.rng.randf_range(0.28, 0.4))
	_lights_along(w, door - facing * 0.3, along, f[2], f[3] - 0.4, [Color(1, 0.5, 0.05), Color(0.6, 0.2, 1.0)])
	if w.rng.randf() < 0.4:
		# A bat on the roof
		var bp: Vector3 = door - facing * 1.0 + Vector3(0, f[3] + 1.0, 0)
		var wing := Util.prism(Vector3(1.0, 0.35, 0.05), Color(0.08, 0.05, 0.1), bp)
		wing.rotation.z = PI
		w.add_child(wing)
		w.add_child(Util.sphere(0.15, Color(0.08, 0.05, 0.1), bp + Vector3(0, 0.05, 0)))


static func _spooky_park(w, r: Rect2) -> void:
	var rng: RandomNumberGenerator = w.rng
	var c := r.get_center()
	for i in rng.randi_range(2, 4):
		var gp := Vector3(rng.randf_range(r.position.x + 1, r.end.x - 1), 0, rng.randf_range(r.position.y + 1, r.end.y - 1))
		var stone := Util.box(Vector3(0.8, 1.0, 0.2), Color(0.55, 0.55, 0.6), gp + Vector3(0, 0.5, 0), true)
		stone.rotation.z = rng.randf_range(-0.15, 0.15)
		w.add_child(stone)
		w.add_child(Util.label3d("RIP", 26, Color(0.25, 0.25, 0.3), gp + Vector3(0, 0.7, 0.12)))
	pumpkin(w, Vector3(c.x + 2.5, 0, c.y + 2.0), 0.45)
	if rng.randf() < 0.5:
		var ghost := Util.capsule(0.45, 1.3, Color(0.95, 0.97, 1.0, 1.0), Vector3(c.x - 2.0, 1.6, c.y))
		w.add_child(ghost)
		for x in [-0.15, 0.15]:
			w.add_child(Util.sphere(0.08, Color(0.05, 0.05, 0.05), Vector3(c.x - 2.0 + x, 1.9, c.y + 0.42)))


static func _festive_front(w, r: Rect2, facing: Vector3) -> void:
	var f := _front(w, r, facing)
	var door: Vector3 = f[0]
	var along: Vector3 = f[1]
	_lights_along(w, door - facing * 0.3, along, f[2], f[3] - 0.4, [Color(1, 0.2, 0.2), Color(0.2, 1, 0.3), Color(1, 0.85, 0.2), Color(0.3, 0.5, 1)])
	var wreath := Util.torus(0.22, 0.38, Color(0.1, 0.45, 0.15), door + Vector3(0, 1.6, 0) - facing * 0.15)
	wreath.basis = Basis.looking_at(facing) * Basis(Vector3.RIGHT, PI / 2)
	w.add_child(wreath)
	w.add_child(Util.sphere(0.09, Color(0.9, 0.1, 0.1), door + Vector3(0, 1.3, 0) - facing * 0.1))
	if w.rng.randf() < 0.35:
		snowman(w, door + facing * 1.6 + along * 1.8)


static func snowman(w, p: Vector3) -> void:
	w.add_child(Util.sphere(0.6, Color.WHITE, p + Vector3(0, 0.55, 0), true))
	w.add_child(Util.sphere(0.42, Color.WHITE, p + Vector3(0, 1.4, 0), true))
	w.add_child(Util.cylinder(0.06, 0.35, Color(1, 0.5, 0.1), p + Vector3(0, 1.45, 0.5)))
	w.add_child(Util.cylinder(0.3, 0.45, Color(0.1, 0.1, 0.12), p + Vector3(0, 2.0, 0)))
	w.add_child(Util.box(Vector3(0.9, 0.12, 0.2), Color(0.85, 0.1, 0.1), p + Vector3(0, 1.08, 0.1)))


static func _festive_park(w, r: Rect2) -> void:
	var rng: RandomNumberGenerator = w.rng
	var c := Vector3(r.get_center().x, 0, r.get_center().y)
	if rng.randf() < 0.5:
		var t := c + Vector3(2.0, 0, -1.5)
		w.add_child(Util.cylinder(0.25, 0.8, Color(0.4, 0.28, 0.2), t + Vector3(0, 0.4, 0)))
		for i in 3:
			w.add_child(Util.cylinder(1.6 - i * 0.45, 1.4, Color(0.1, 0.42, 0.2), t + Vector3(0, 1.3 + i * 1.0, 0), false, 0.1))
		for i in 10:
			var a := i * 2.1
			var y := 1.0 + (i % 5) * 0.6
			var rad := 1.55 - (y - 1.0) * 0.38
			var col: Color = [Color(1, 0.2, 0.2), Color(1, 0.85, 0.2), Color(0.3, 0.6, 1)][i % 3]
			w.add_child(Util.sphere(0.13, Util.glow(col, 2.5), t + Vector3(sin(a) * rad, y, cos(a) * rad)))
		w.add_child(Util.sphere(0.3, Util.glow(Color(1, 0.9, 0.3), 4.0), t + Vector3(0, 4.3, 0)))
		for i in 3:
			var g := t + Vector3(-1.2 + i * 1.1, 0.25, 1.6)
			w.add_child(Util.box(Vector3(0.5, 0.5, 0.5), Color.from_hsv(rng.randf(), 0.7, 0.9), g, true))
	else:
		snowman(w, c + Vector3(-2.0, 0, 1.0))
