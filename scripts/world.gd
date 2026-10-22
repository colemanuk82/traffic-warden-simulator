extends Node3D
## Builds a level from its definition (levels.gd): roads, pavements, parking spots, lanes,
## themed buildings, decorations and lighting. Also answers "can the warden walk here?".

const Util := preload("res://scripts/util.gd")
const Lane := preload("res://scripts/lane.gd")
const Terrain := preload("res://scripts/terrain.gd")
const Scenery := preload("res://scripts/scenery.gd")

const ROAD_HALF := 4.0
const PAVE_HALF := 8.0
const LANE_OFFSET := 1.3
const SPOT_OFFSET := 3.0
const SPOT_SPACING := 7.5
const SHOP_NAMES := ["CHIPPY", "BAKERY", "BOOKIES", "THE CROWN", "LAUNDRETTE", "NEWSAGENT", "CAFE", "BARBER",
	"KEBABS", "POUND SHOP", "CHEMIST", "TOY SHOP", "BUTCHER", "FLORIST", "VAPE", "CHARITY"]
const NEON_NAMES := ["NOODLES", "KARAOKE", "HOTEL", "24/7", "ARCADE", "PIZZA", "CLUB", "SUSHI", "BAR", "CINEMA"]
const XMAS_NAMES := ["TOY SHOP", "MINCE PIES", "GIFTS", "SANTA'S", "CRACKERS", "BAKERY", "THE HOLLY", "JUMPERS",
	"TINSEL TOWN", "SWEET SHOP", "BOOKS", "DECORATIONS"]

var def: Dictionary
var rng: RandomNumberGenerator
var bounds: Rect2
var segments: Array = []  # {a: Vector2, b: Vector2, road: int}
var road_rects: Array[Rect2] = []
var pave_rects: Array[Rect2] = []
var walk_rects: Array[Rect2] = []
var lanes: Array = []
var spots: Array[Dictionary] = []
var footprints: Array[Rect2] = []
var lights: Array[OmniLight3D] = []
var region: Rect2
var env: Environment
var sun: DirectionalLight3D
var sea_material: ShaderMaterial
var road_puddles: Array[Vector3] = []
var slow_zones: Array = []  # [Vector2 centre, radius]
var bus_stops := 0
var path_rects: Array[Rect2] = []
var lifted := false  # true once the terrain has lifted everything onto the hills


func build(level: Dictionary, random: RandomNumberGenerator, with_spots := true) -> void:
	def = level
	rng = random
	bounds = def.bounds
	region = bounds.grow(24.0)
	for ri in def.roads.size():
		var pts: Array = def.roads[ri]
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			segments.append({"a": a, "b": b, "road": ri})
			road_rects.append(_seg_rect(a, b, ROAD_HALF))
			var pr := _seg_rect(a, b, PAVE_HALF)
			pave_rects.append(pr)
			var w := pr.intersection(bounds)
			if w.has_area():
				walk_rects.append(w)
	# Footpaths and alleys: walkable shortcuts that keep buildings away (added after the road pavements
	# so that pave_rects[i] still matches segments[i])
	for r in def.get("paths", []):
		var pr: Rect2 = r
		path_rects.append(pr)
		pave_rects.append(pr)
		walk_rects.append(pr.intersection(bounds))
	# Open tarmac you can walk across without any paving drawn (car park lots)
	for r in def.get("open", []):
		var o: Rect2 = r
		walk_rects.append(o.intersection(bounds))
	_build_environment()
	_build_ground()
	_build_roads()
	_build_lanes()
	if with_spots:
		_build_spots()
	_build_edges()
	_build_paths()
	_build_theme()
	_build_event_deco()
	Terrain.apply(self)
	lifted = true
	_trim_shadows(self)


## Small props and flat ground pieces don't need to cast shadows: skipping them keeps
## the shadow pass cheap now the streets are lined with houses, trees and park furniture.
func _trim_shadows(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and c.mesh:
			var sz: Vector3 = c.get_aabb().size * c.global_basis.get_scale().abs() if c.is_inside_tree() else c.get_aabb().size * c.scale.abs()
			if sz.y < 0.2 or maxf(sz.x, maxf(sz.y, sz.z)) < 0.7:
				c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trim_shadows(c)


func _seg_rect(a: Vector2, b: Vector2, half: float) -> Rect2:
	var r := Rect2(a, Vector2.ZERO).expand(b)
	return r.grow(half)


static func _v3(p: Vector2, y := 0.0) -> Vector3:
	return Vector3(p.x, y, p.y)


static func _left(d: Vector3) -> Vector3:
	return Vector3(d.z, 0, -d.x)


static func yaw_of(d: Vector3) -> float:
	## Rotation that points local +X along d
	return atan2(-d.z, d.x)


# ---------------------------------------------------------------- queries

## Ground height at p (hills and car park ramps; 0 on flat levels).
func height_at(p: Vector3) -> float:
	return Terrain.height(def.get("terrain", {}), p.x, p.z)


## Nose-up angle for a car at p facing fwd.
func pitch_at(p: Vector3, fwd: Vector3) -> float:
	return Terrain.pitch(def.get("terrain", {}), p, fwd)


## The nearest walkable point to p, for spawning safely.
func nearest_walkable(p: Vector3) -> Vector3:
	if is_walkable(p):
		return p
	var q := Vector2(p.x, p.z)
	var best := q
	var best_d := INF
	for r in walk_rects:
		var inner := r.grow(-0.6)
		if not inner.has_area():
			inner = r
		var c := Vector2(clampf(q.x, inner.position.x, inner.end.x), clampf(q.y, inner.position.y, inner.end.y))
		var d := c.distance_to(q)
		if d < best_d:
			best_d = d
			best = c
	return Vector3(best.x, p.y, best.y)


func is_walkable(p: Vector3) -> bool:
	var q := Vector2(p.x, p.z)
	for r in walk_rects:
		if r.has_point(q):
			return true
	return false


## 1.0 normally; less when wading through rubbish bags.
func speed_at(p: Vector3) -> float:
	var q := Vector2(p.x, p.z)
	for z in slow_zones:
		if q.distance_to(z[0]) < z[1]:
			return 0.55
	return 1.0


## A random spot the warden can reach, at least min_dist from a point.
func random_walk_point(r: RandomNumberGenerator, away_from := Vector3.ZERO, min_dist := 0.0, pavement := false) -> Vector3:
	var p := Vector3.ZERO
	for i in 80:
		var w: Rect2 = walk_rects[r.randi() % walk_rects.size()].grow(-1.0)
		p = Vector3(r.randf_range(w.position.x, w.end.x), 0, r.randf_range(w.position.y, w.end.y))
		if pavement and _in_road(Vector2(p.x, p.z)):
			continue
		if p.distance_to(away_from) >= min_dist:
			break
	p.y = height_at(p) if lifted else 0.0
	return p


## Puddles along the kerbs that cheeky drivers aim for when it rains.
func build_road_puddles() -> void:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.35, 0.45, 0.62)
	water.roughness = 0.05
	water.metallic = 0.5
	for i in segments.size():
		var a: Vector2 = segments[i].a
		var b: Vector2 = segments[i].b
		var d := (b - a).normalized()
		var n := Vector2(d.y, -d.x)
		var len := a.distance_to(b)
		var t := rng.randf_range(4.0, 10.0)
		while t < len:
			for side in [-1.0, 1.0]:
				var q: Vector2 = a + d * (t + side * 3.0) + n * side * (ROAD_HALF - 0.9)
				var junction := false
				for j in road_rects.size():
					if j != i and road_rects[j].grow(1.0).has_point(q):
						junction = true
				if junction or not bounds.grow(-2.0).has_point(q):
					continue
				var gh := height_at(_v3(q))
				var puddle := Util.cylinder(rng.randf_range(0.9, 1.3), 0.02, water, _v3(q, 0.075 + gh))
				puddle.scale = Vector3(1.5, 1, 0.8) if absf(d.x) > 0.5 else Vector3(0.8, 1, 1.5)
				add_child(puddle)
				road_puddles.append(_v3(q, gh))
			t += rng.randf_range(10.0, 16.0)


func clamp_move(old: Vector3, new: Vector3) -> Vector3:
	if is_walkable(new):
		return new
	var a := Vector3(new.x, new.y, old.z)
	if is_walkable(a):
		return a
	var b := Vector3(old.x, new.y, new.z)
	if is_walkable(b):
		return b
	return old


func _in_road(p: Vector2, except := -1) -> bool:
	for i in road_rects.size():
		if i != except and road_rects[i].has_point(p):
			return true
	return false


func _blocked(r: Rect2) -> bool:
	for p in pave_rects:
		if p.grow(0.4).intersects(r):
			return true
	for f in footprints:
		if f.intersects(r):
			return true
	return false


func _occludes(r: Rect2) -> bool:
	## True if street the warden can walk on lies just north of (behind) this footprint
	var north := Rect2(r.position.x, r.position.y - 18.0, r.size.x, 18.0)
	for w in walk_rects:
		if w.intersects(north):
			return true
	return false


# ---------------------------------------------------------------- environment

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = def.sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = def.ambient
	env.ambient_light_energy = 0.32
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.9
	if def.get("night", false):
		env.glow_enabled = true
		env.glow_intensity = 1.1
		env.glow_bloom = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_color = def.sun
	sun.light_energy = def.sun_energy * 0.7
	sun.shadow_enabled = Game.shadows_on()
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _build_ground() -> void:
	var g := region.grow(30.0)
	add_child(Util.box(Vector3(g.size.x, 1, g.size.y), def.ground, Vector3(g.get_center().x, -0.5, g.get_center().y)))


func _build_roads() -> void:
	var pave_col := Color(0.62, 0.61, 0.6) if def.theme not in ["snow", "xmas"] else Color(0.85, 0.87, 0.92)
	if def.theme == "posh":
		pave_col = Color(0.86, 0.8, 0.68)
	elif def.theme == "halloween":
		pave_col = Color(0.42, 0.4, 0.46)
	var road_col := Color(0.3, 0.3, 0.33) if def.theme not in ["city", "halloween"] else Color(0.2, 0.2, 0.24)
	var clip := region.grow(10.0)
	for i in segments.size():
		var pr := pave_rects[i].intersection(clip)
		add_child(Util.box(Vector3(pr.size.x, 0.08, pr.size.y), pave_col, _v3(pr.get_center(), 0.0)))
	for i in segments.size():
		var rr := road_rects[i].intersection(clip)
		add_child(Util.box(Vector3(rr.size.x, 0.06, rr.size.y), road_col, _v3(rr.get_center(), 0.03)))
	# Dashed centre lines and kerbs, skipped inside junctions
	var white := Color(0.95, 0.95, 0.95)
	var kerb := pave_col.lightened(0.15)
	for i in segments.size():
		var a: Vector2 = segments[i].a
		var b: Vector2 = segments[i].b
		var d := (b - a).normalized()
		var n := Vector2(d.y, -d.x)
		var yaw := yaw_of(_v3(d))
		var t := 0.0
		var len := a.distance_to(b)
		while t < len:
			var p := a + d * t
			if clip.has_point(p):
				if int(t / 2.0) % 3 == 0 and not _in_road(p, i):
					var dash := Util.box(Vector3(2.0, 0.02, 0.15), white, _v3(p + d, 0.07))
					dash.rotation.y = yaw
					add_child(dash)
				for side in [-1.0, 1.0]:
					var kp: Vector2 = p + d + n * side * (ROAD_HALF + 0.12)
					if not _in_road(kp, i) and not _in_road(kp - d * 1.0, i) and not _in_road(kp + d * 1.0, i):
						var k := Util.box(Vector3(2.0, 0.16, 0.25), kerb, _v3(kp, 0.04))
						k.rotation.y = yaw
						add_child(k)
			t += 2.0


func _build_lanes() -> void:
	for road in def.roads:
		var pts: Array = road
		for dir in [1, -1]:
			var ordered: Array = pts.duplicate()
			if dir < 0:
				ordered.reverse()
			var out := PackedVector3Array()
			for i in ordered.size():
				var p: Vector3 = _v3(ordered[i])
				var off := Vector3.ZERO
				if i == 0:
					off = _left(_v3(ordered[1] - ordered[0]).normalized())
				elif i == ordered.size() - 1:
					off = _left(_v3(ordered[i] - ordered[i - 1]).normalized())
				else:
					var din := _v3(ordered[i] - ordered[i - 1]).normalized()
					var dout := _v3(ordered[i + 1] - ordered[i]).normalized()
					off = _left(din) + _left(dout)
					if din.dot(dout) > 0.99:
						off = _left(din)
				out.append(p + off * LANE_OFFSET)
			lanes.append(Lane.new(out))


func _build_spots() -> void:
	var inner := bounds.grow(-3.0)
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var d2 := (b - a).normalized()
		var d := _v3(d2)
		var len := a.distance_to(b)
		var t := 5.0
		while t < len - 5.0:
			for side in [1.0, -1.0]:
				var n: Vector3 = _left(d) * side
				var centre: Vector3 = _v3(a + d2 * t) + n * SPOT_OFFSET
				var c2 := Vector2(centre.x, centre.z)
				if not inner.has_point(c2) or not _flat_at(c2):
					continue
				var junction := false
				for j in pave_rects.size():
					if j != i and pave_rects[j].grow(2.5).has_point(c2):
						junction = true
				if junction:
					continue
				var lane = lanes[seg.road * 2 + (0 if side > 0.0 else 1)]
				var lane_point: Vector3 = centre - n * (SPOT_OFFSET - LANE_OFFSET)
				var travel: Vector3 = d * side
				var spot := {
					"pos": centre, "normal": n, "dir": travel, "lane": lane, "s": lane.project(lane_point),
					"type": _spot_type(), "car": null, "label": null,
				}
				_mark_spot(spot)
				spots.append(spot)
			t += SPOT_SPACING


func _spot_type() -> String:
	## Meter bays, double yellows, disabled bays (blue badge holders only) and the odd bus stop
	var r := rng.randf()
	if r < 0.07 and bus_stops < 2 + segments.size():
		bus_stops += 1
		return "busstop"
	if r < 0.19:
		return "disabled"
	return "meter" if rng.randf() >= float(def.get("yellow_chance", 0.4)) else "yellow"


func _mark_spot(spot: Dictionary) -> void:
	var c: Vector3 = spot.pos
	var n: Vector3 = spot.normal
	var d: Vector3 = spot.dir
	var yaw := yaw_of(d)
	if spot.type == "disabled":
		var blue := Color(0.15, 0.4, 0.95)
		for p in [[Vector3(5.2, 0.02, 0.12), c - n * 1.0], [Vector3(0.12, 0.02, 2.0), c - d * 2.6], [Vector3(0.12, 0.02, 2.0), c + d * 2.6]]:
			var m := Util.box(p[0], Color(0.95, 0.95, 0.95), p[1] + Vector3(0, 0.075, 0))
			m.rotation.y = yaw
			add_child(m)
		var sq := Util.box(Vector3(1.3, 0.02, 1.3), blue, c + Vector3(0, 0.08, 0))
		sq.rotation.y = yaw
		add_child(sq)
		var icon := Util.label3d("P", 80, Color.WHITE, c + Vector3(0, 0.1, 0))
		icon.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		icon.rotation = Vector3(-PI / 2, yaw, 0)
		add_child(icon)
		var sp: Vector3 = c + n * 1.6 + d * 2.2
		add_child(Util.cylinder(0.06, 2.0, Color(0.6, 0.6, 0.65), sp + Vector3(0, 1.0, 0)))
		var sign := Util.box(Vector3(0.6, 0.6, 0.06), blue, sp + Vector3(0, 2.1, 0), true)
		sign.rotation.y = yaw + PI / 2
		add_child(sign)
		add_child(Util.label3d("BLUE BADGE\nONLY", 26, Color.WHITE, sp + Vector3(0, 2.75, 0)))
		return
	if spot.type == "busstop":
		var yellow := Color(1, 0.85, 0.1)
		for p in [[Vector3(7.0, 0.02, 0.15), c - n * 1.1], [Vector3(7.0, 0.02, 0.15), c + n * 1.0],
				[Vector3(0.15, 0.02, 2.1), c - d * 3.5], [Vector3(0.15, 0.02, 2.1), c + d * 3.5]]:
			var m := Util.box(p[0], yellow, p[1] + Vector3(0, 0.075, 0))
			m.rotation.y = yaw
			add_child(m)
		var txt := Util.label3d("BUS STOP", 70, yellow, c + Vector3(0, 0.1, 0))
		txt.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		txt.rotation = Vector3(-PI / 2, yaw, 0)
		add_child(txt)
		# Shelter on the pavement behind the stop
		var sh: Vector3 = c + n * 2.6
		var shelter := Node3D.new()
		shelter.position = sh
		shelter.rotation.y = yaw
		add_child(shelter)
		shelter.add_child(Util.box(Vector3(3.2, 0.12, 1.4), Color(0.2, 0.25, 0.3), Vector3(0, 2.5, 0), true))
		shelter.add_child(Util.box(Vector3(3.2, 2.4, 0.06), Color(0.7, 0.85, 0.95, 1.0), Vector3(0, 1.25, 0.65)))
		for x in [-1.55, 1.55]:
			shelter.add_child(Util.box(Vector3(0.1, 2.5, 1.3), Color(0.2, 0.25, 0.3), Vector3(x, 1.25, 0)))
		shelter.add_child(Util.box(Vector3(2.2, 0.1, 0.4), Color(0.5, 0.35, 0.2), Vector3(0, 0.6, 0.3)))
		var flag := Util.box(Vector3(0.7, 0.7, 0.06), Color(0.85, 0.1, 0.1), Vector3(-1.9, 2.6, -0.4), true)
		shelter.add_child(flag)
		shelter.add_child(Util.cylinder(0.06, 2.8, Color(0.6, 0.6, 0.65), Vector3(-1.9, 1.4, -0.4)))
		shelter.add_child(Util.label3d("BUS", 30, Color.WHITE, Vector3(-1.9, 3.1, -0.4)))
		return
	if spot.type == "meter":
		var white := Color(0.95, 0.95, 0.95)
		var parts := [
			[Vector3(5.2, 0.02, 0.12), c - n * 1.0],
			[Vector3(0.12, 0.02, 2.0), c - d * 2.6],
			[Vector3(0.12, 0.02, 2.0), c + d * 2.6],
		]
		for p in parts:
			var m := Util.box(p[0], white, p[1] + Vector3(0, 0.075, 0))
			m.rotation.y = yaw
			add_child(m)
		var mp: Vector3 = c + n * 1.6 + d * 2.2
		add_child(Util.cylinder(0.07, 1.2, Color(0.4, 0.4, 0.45), mp + Vector3(0, 0.6, 0)))
		add_child(Util.box(Vector3(0.35, 0.45, 0.3), Color(0.2, 0.25, 0.35), mp + Vector3(0, 1.4, 0), true))
		var label := Util.label3d("", 40, Color.WHITE, mp + Vector3(0, 2.3, 0))
		add_child(label)
		spot.label = label
	else:
		var yellow := Color(1, 0.85, 0.1)
		for off in [0.8, 0.55]:
			var line := Util.box(Vector3(6.5, 0.02, 0.12), yellow, c + n * off + Vector3(0, 0.075, 0))
			line.rotation.y = yaw
			add_child(line)


func _build_edges() -> void:
	## Striped barriers across the pavement where the walkable area meets the edge of the map
	for w in walk_rects:
		var edges := [
			[Vector2(w.position.x, w.position.y), Vector2(w.end.x, w.position.y), absf(w.position.y - bounds.position.y) < 0.01],
			[Vector2(w.position.x, w.end.y), Vector2(w.end.x, w.end.y), absf(w.end.y - bounds.end.y) < 0.01],
			[Vector2(w.position.x, w.position.y), Vector2(w.position.x, w.end.y), absf(w.position.x - bounds.position.x) < 0.01],
			[Vector2(w.end.x, w.position.y), Vector2(w.end.x, w.end.y), absf(w.end.x - bounds.end.x) < 0.01],
		]
		for e in edges:
			if not e[2]:
				continue
			var a: Vector2 = e[0]
			var b: Vector2 = e[1]
			var len := a.distance_to(b)
			var d := (b - a) / len
			var k := 0
			var t := 0.5
			while t < len:
				var p := a + d * t
				if not _in_road(p):
					var col := Color(1, 0.8, 0.1) if k % 2 == 0 else Color(0.1, 0.1, 0.12)
					var bar := Util.box(Vector3(1.0, 0.25, 0.2), col, _v3(p, 0.9))
					bar.rotation.y = yaw_of(_v3(d))
					add_child(bar)
					if k % 3 == 0:
						add_child(Util.box(Vector3(0.1, 0.9, 0.1), Color(0.9, 0.9, 0.9), _v3(p, 0.45)))
				k += 1
				t += 1.0


# ---------------------------------------------------------------- solids and buildings

func add_solid(size: Vector3, color, pos: Vector3, outline := true) -> MeshInstance3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	shape.shape = bs
	body.add_child(shape)
	body.position = pos
	add_child(body)
	var m := Util.box(size, color, pos, outline)
	add_child(m)
	return m


func _add_building(r: Rect2, height: float, color: Color, facing: Vector3) -> Node3D:
	## A box building whose front (local +Z) faces the road. Returns the node to decorate.
	footprints.append(r)
	# Anything that would hide the street from the camera is kept low
	var low := _occludes(r)
	if low:
		height = minf(height, 3.0)
	var fade := false
	var node := Node3D.new()
	node.position = _v3(r.get_center())
	node.rotation.y = atan2(facing.x, facing.z)
	add_child(node)
	var along := r.size.x if absf(facing.z) > 0.5 else r.size.y
	var depth := r.size.y if absf(facing.z) > 0.5 else r.size.x
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(along - 0.2, height, depth)
	m.mesh = bm
	m.material_override = Util.mat(color, false, fade)
	m.position.y = height / 2.0
	node.add_child(m)
	node.set_meta("size", Vector3(along, height, depth))
	node.set_meta("fade", fade)
	node.set_meta("low", low)
	return node


func _part(node: Node3D, size: Vector3, color, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	if color is Material:
		m.material_override = color
	else:
		m.material_override = Util.mat(color, false, node.get_meta("fade", false) and (size.y > 2.0 or pos.y > 2.0))
	m.position = pos
	node.add_child(m)
	return m


func _roof(node: Node3D, color: Color, snow := false) -> void:
	var s: Vector3 = node.get_meta("size")
	if node.get_meta("low"):
		_part(node, Vector3(s.x + 0.2, 0.3, s.z + 0.2), Color(0.97, 0.98, 1.0) if snow else color, Vector3(0, s.y + 0.15, 0))
		return
	var p := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(s.z + 0.4, 2.2, s.x)
	p.mesh = pm
	p.material_override = Util.mat(Color(0.97, 0.98, 1.0) if snow else color, false, node.get_meta("fade", false))
	p.position.y = s.y + 1.1
	p.rotation.y = PI / 2
	node.add_child(p)


func _windows(node: Node3D, color, rows: int, spacing := 2.2, start := 1.6) -> void:
	var s: Vector3 = node.get_meta("size")
	var cols := maxi(int(s.x / 2.4), 1)
	for row in rows:
		var y := start + row * spacing
		if y > s.y - 0.8:
			break
		for c in cols:
			var x := -s.x / 2.0 + (c + 0.5) * s.x / cols
			_part(node, Vector3(1.0, 1.0, 0.1), color, Vector3(x, y, s.z / 2.0 + 0.02))


func _build_theme() -> void:
	match def.theme:
		"suburb":
			_line_buildings(Vector2(6, 10), Vector2(4.5, 8), 6.0, 2.0, _suburb_house)
			_scatter(60, _tree)
		"town":
			_line_buildings(Vector2(6, 9), Vector2(5, 10), 7.0, 0.5, _shop)
			_scatter(25, _market_stall)
			_scatter(20, _tree)
		"seaside":
			_build_beach()
			_line_buildings(Vector2(7, 11), Vector2(6, 12), 7.0, 0.5, _hotel)
			_scatter(20, _tree)
		"snow":
			_build_green()
			_line_buildings(Vector2(6, 9), Vector2(3.5, 5), 6.0, 2.0, _cottage)
			_scatter(70, _pine)
		"city":
			_build_plaza()
			_line_buildings(Vector2(8, 13), Vector2(10, 26), 9.0, 0.5, _tower)
			_scatter(20, _tree)
		"posh":
			_line_buildings(Vector2(12, 16), Vector2(6, 9), 10.0, 5.0, _mansion)
			_scatter(40, _topiary)
			_scatter(6, _fountain)
		"carpark":
			_build_supermarket()
		"multistorey":
			_build_multistorey()
		"halloween":
			_build_graveyard(Rect2(-11.5, 38.5, 23, 50))
			_line_buildings(Vector2(7, 10), Vector2(4.5, 7.5), 6.0, 2.0, _spooky_house)
			_scatter(45, _dead_tree)
			_scatter(30, _pumpkin)
			add_child(Util.sphere(5.0, Util.glow(Color(1.0, 0.95, 0.75), 1.6), Vector3(-30, 34, -70)))
		"xmas":
			_build_xmas_square(Rect2(-30, -36, 58, 28))
			_line_buildings(Vector2(6, 9), Vector2(5, 9), 7.0, 0.5, _xmas_shop)
			_bunting_along(Color(1, 0.2, 0.2), Color(1, 0.85, 0.3), 3.2, true)
			_scatter(30, _pine)
			_scatter(10, _snowman)
		"hills", "terraces":
			Scenery.build_theme(self)
	_street_furniture()
	Scenery.dress(self)


func _line_buildings(width: Vector2, height: Vector2, depth: float, setback: float, maker: Callable) -> void:
	for seg in segments:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var d := (b - a).normalized()
		var len := a.distance_to(b)
		for side in [1.0, -1.0]:
			var n: Vector2 = Vector2(d.y, -d.x) * side
			var t := 0.0
			while t < len:
				var w := rng.randf_range(width.x, width.y)
				var centre: Vector2 = a + d * (t + w / 2.0) + n * (PAVE_HALF + setback + depth / 2.0)
				var half := Vector2(absf(d.x) * w + absf(d.y) * depth, absf(d.y) * w + absf(d.x) * depth) / 2.0
				var r := Rect2(centre - half, half * 2.0)
				if region.has_point(centre) and not _blocked(r):
					var facing := -_v3(n)
					maker.call(r, rng.randf_range(height.x, height.y), facing, setback)
				t += w


func _scatter(count: int, maker: Callable) -> void:
	for i in count * 3:
		if count <= 0:
			return
		var p := Vector2(rng.randf_range(region.position.x, region.end.x), rng.randf_range(region.position.y, region.end.y))
		var r := Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3))
		if _blocked(r) or not _scatter_allowed(p):
			continue
		footprints.append(r)
		maker.call(_v3(p))
		count -= 1


func _scatter_allowed(p: Vector2) -> bool:
	if def.theme == "seaside" and p.y > 9.0:
		return false
	return true


# ---------------------------------------------------------------- themed makers

func _suburb_house(r: Rect2, h: float, facing: Vector3, setback: float) -> void:
	var palette := [Color(0.9, 0.6, 0.5), Color(0.95, 0.85, 0.6), Color(0.65, 0.75, 0.9),
		Color(0.85, 0.7, 0.85), Color(0.7, 0.85, 0.7), Color(0.8, 0.5, 0.45)]
	var c: Color = palette[rng.randi() % palette.size()]
	var node := _add_building(r, h, c, facing)
	var s: Vector3 = node.get_meta("size")
	_roof(node, c.darkened(0.45))
	_part(node, Vector3(1.2, 2.2, 0.2), c.darkened(0.5), Vector3(0, 1.1, s.z / 2.0 + 0.05))
	_windows(node, Color(0.6, 0.8, 0.95), 2, 2.6, 2.0 if h > 5 else 3.2)
	if not node.get_meta("low"):
		_part(node, Vector3(0.7, 1.4, 0.7), c.darkened(0.3), Vector3(s.x * 0.3, h + 1.6, 0))
	# Front garden hedge or wall
	var hedge := rng.randf() < 0.5
	_part(node, Vector3(s.x - 0.4, 0.9 if hedge else 0.6, 0.7),
		Color(0.3, 0.55, 0.25) if hedge else Color(0.75, 0.45, 0.35), Vector3(0, 0.45, s.z / 2.0 + setback - 0.4))


func _shop(r: Rect2, h: float, facing: Vector3, _setback: float) -> void:
	var palette := [Color(0.85, 0.75, 0.6), Color(0.7, 0.4, 0.35), Color(0.6, 0.65, 0.7), Color(0.9, 0.9, 0.85), Color(0.5, 0.35, 0.3)]
	var c: Color = palette[rng.randi() % palette.size()]
	var node := _add_building(r, h, c, facing)
	var s: Vector3 = node.get_meta("size")
	var front := s.z / 2.0
	var shop_col := Color.from_hsv(rng.randf(), 0.65, 0.85)
	_part(node, Vector3(s.x - 0.4, 3.0, 0.3), shop_col, Vector3(0, 1.5, front + 0.1))
	_part(node, Vector3(s.x - 1.6, 1.8, 0.1), Color(0.55, 0.75, 0.9), Vector3(0, 1.2, front + 0.3))
	var awning := _part(node, Vector3(s.x - 0.2, 0.12, 1.4), shop_col.lightened(0.3), Vector3(0, 3.1, front + 0.8))
	awning.rotation.x = 0.35
	_windows(node, Color(0.55, 0.7, 0.85), 3, 2.4, 4.6)
	var sign := Util.label3d(SHOP_NAMES[rng.randi() % SHOP_NAMES.size()], 64, Color.WHITE, Vector3(0, minf(3.7, s.y - 0.4), front + 0.4))
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign.no_depth_test = false
	node.add_child(sign)


func _hotel(r: Rect2, h: float, facing: Vector3, _setback: float) -> void:
	var palette := [Color(1.0, 0.85, 0.85), Color(0.85, 0.95, 1.0), Color(1.0, 0.95, 0.75), Color(0.85, 1.0, 0.9), Color(1, 1, 1)]
	var c: Color = palette[rng.randi() % palette.size()]
	var node := _add_building(r, h, c, facing)
	var s: Vector3 = node.get_meta("size")
	_windows(node, Color(0.5, 0.75, 0.95), 4, 2.6, 1.8)
	for row in range(1, 4):
		var y := row * 2.6 + 0.6
		if y < s.y - 1.0:
			_part(node, Vector3(s.x - 0.6, 0.12, 0.8), Color.WHITE, Vector3(0, y, s.z / 2.0 + 0.4))
	_part(node, Vector3(s.x + 0.2, 0.4, s.z + 0.2), c.darkened(0.3), Vector3(0, s.y + 0.2, 0))


func _cottage(r: Rect2, h: float, facing: Vector3, setback: float) -> void:
	var palette := [Color(0.85, 0.8, 0.7), Color(0.75, 0.7, 0.65), Color(0.9, 0.85, 0.75), Color(0.7, 0.55, 0.45)]
	var c: Color = palette[rng.randi() % palette.size()]
	var node := _add_building(r, h, c, facing)
	var s: Vector3 = node.get_meta("size")
	_roof(node, c, true)
	_part(node, Vector3(1.1, 2.0, 0.2), Color(0.45, 0.2, 0.15), Vector3(0, 1.0, s.z / 2.0 + 0.05))
	_windows(node, Util.glow(Color(1.0, 0.8, 0.4), 1.2), 1, 2.0, 2.0)
	_part(node, Vector3(s.x - 0.4, 0.8, 0.4), Color(0.55, 0.4, 0.3), Vector3(0, 0.4, s.z / 2.0 + setback - 0.4))
	_part(node, Vector3(s.x - 0.3, 0.15, 0.5), Color.WHITE, Vector3(0, 0.85, s.z / 2.0 + setback - 0.4))


func _tower(r: Rect2, h: float, facing: Vector3, _setback: float) -> void:
	var c := Color.from_hsv(rng.randf_range(0.6, 0.8), 0.3, rng.randf_range(0.15, 0.3))
	var node := _add_building(r, h, c, facing)
	var s: Vector3 = node.get_meta("size")
	var lit_cols := [Color(1, 0.85, 0.5), Color(0.5, 0.9, 1), Color(1, 0.5, 0.9)]
	var lit: Color = lit_cols[rng.randi() % lit_cols.size()]
	var floor_y := 3.0
	while floor_y < s.y - 1.0:
		if rng.randf() < 0.7:
			_part(node, Vector3(s.x * rng.randf_range(0.4, 0.85), 0.9, 0.1), Util.glow(lit, 1.6), Vector3(rng.randf_range(-0.5, 0.5), floor_y, s.z / 2.0 + 0.03))
		floor_y += 2.6
	var neon := Color.from_hsv(rng.randf(), 0.8, 1.0)
	_part(node, Vector3(s.x - 0.4, 0.15, 0.15), Util.glow(neon, 3.0), Vector3(0, 2.6, s.z / 2.0 + 0.1))
	if rng.randf() < 0.6:
		var sign := Util.label3d(NEON_NAMES[rng.randi() % NEON_NAMES.size()], 90, neon.lightened(0.3), Vector3(0, minf(4.5, s.y - 0.8), s.z / 2.0 + 0.3))
		sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		sign.no_depth_test = false
		sign.outline_modulate = neon.darkened(0.5)
		node.add_child(sign)


func _mansion(r: Rect2, h: float, facing: Vector3, setback: float) -> void:
	var palette := [Color(0.98, 0.96, 0.9), Color(0.95, 0.9, 0.8), Color(0.9, 0.92, 0.95)]
	var c: Color = palette[rng.randi() % palette.size()]
	var node := _add_building(r, h, c, facing)
	var s: Vector3 = node.get_meta("size")
	_roof(node, Color(0.3, 0.32, 0.4))
	_windows(node, Color(0.5, 0.65, 0.85), 2, 2.8, 2.0)
	for i in 4:
		var x := -2.4 + i * 1.6
		var col := Util.cylinder(0.25, s.y - 0.5, Color.WHITE, Vector3(x, (s.y - 0.5) / 2.0, s.z / 2.0 + 1.0))
		node.add_child(col)
	_part(node, Vector3(6.4, 0.5, 2.0), Color.WHITE, Vector3(0, s.y - 0.25, s.z / 2.0 + 1.0))
	_part(node, Vector3(1.4, 2.6, 0.2), Color(0.3, 0.2, 0.15), Vector3(0, 1.3, s.z / 2.0 + 0.05))
	# Gold gate posts and a neat hedge
	var front := s.z / 2.0 + setback - 0.4
	for x in [-s.x / 2.0 + 1.0, s.x / 2.0 - 1.0]:
		_part(node, Vector3(0.6, 1.6, 0.6), Color(0.95, 0.93, 0.88), Vector3(x, 0.8, front))
		node.add_child(Util.sphere(0.3, Util.metal(Color(1, 0.8, 0.2), false), Vector3(x, 1.9, front)))
	_part(node, Vector3(s.x - 3.2, 1.1, 0.6), Color(0.2, 0.45, 0.2), Vector3(0, 0.55, front))


# ---------------------------------------------------------------- Halloween

func _spooky_house(r: Rect2, h: float, facing: Vector3, setback: float) -> void:
	var palette := [Color(0.3, 0.26, 0.36), Color(0.25, 0.3, 0.28), Color(0.38, 0.3, 0.28), Color(0.22, 0.22, 0.28)]
	var c: Color = palette[rng.randi() % palette.size()]
	var node := _add_building(r, h, c, facing)
	var s: Vector3 = node.get_meta("size")
	var front := s.z / 2.0
	_roof(node, Color(0.12, 0.1, 0.15))
	_part(node, Vector3(1.2, 2.2, 0.2), Color(0.2, 0.1, 0.08), Vector3(0, 1.1, front + 0.05))
	var lit: Color = [Color(1, 0.6, 0.15), Color(0.5, 1, 0.4), Color(0.8, 0.4, 1.0)][rng.randi() % 3]
	_windows(node, Util.glow(lit, 1.4), 2, 2.6, 2.0 if h > 5 else 3.2)
	# Pumpkins on the doorstep and a cobweb in the corner
	for x in [-1.2, 1.2]:
		if rng.randf() < 0.7:
			var pk := Node3D.new()
			pk.position = Vector3(x, 0, front + 0.6)
			node.add_child(pk)
			_pumpkin_mesh(pk, 0.4)
	var web := Util.label3d("#", 60, Color(0.85, 0.85, 0.9, 0.7), Vector3(s.x / 2.0 - 0.5, s.y - 0.5, front + 0.1))
	web.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	web.no_depth_test = false
	node.add_child(web)
	# Rickety garden fence
	var front_y := front + setback - 0.4
	var x := -s.x / 2.0 + 0.4
	while x < s.x / 2.0 - 0.3:
		if absf(x) > 0.8:
			_part(node, Vector3(0.12, 0.9 + rng.randf_range(-0.2, 0.1), 0.08), Color(0.25, 0.2, 0.18), Vector3(x, 0.45, front_y))
		x += 0.45
	if rng.randf() < 0.25 and not node.get_meta("low"):
		var sign := Util.label3d("HAUNTED", 50, Color(0.6, 1, 0.5), Vector3(0, minf(s.y + 0.6, 7.0), front + 0.2))
		node.add_child(sign)


func _pumpkin_mesh(parent: Node3D, size: float) -> void:
	var body := Util.sphere(size, Util.mat(Color(1, 0.5, 0.05), true), Vector3(0, size * 0.8, 0))
	body.scale = Vector3(1.2, 0.85, 1.2)
	parent.add_child(body)
	parent.add_child(Util.cylinder(size * 0.12, size * 0.4, Color(0.25, 0.45, 0.15), Vector3(0, size * 1.6, 0)))
	var face := Util.glow(Color(1, 0.85, 0.25), 3.0)
	for x in [-0.35, 0.35]:
		parent.add_child(Util.prism(Vector3(size * 0.35, size * 0.3, 0.04), face, Vector3(x * size, size * 0.95, size * 1.15)))
	parent.add_child(Util.box(Vector3(size * 0.8, size * 0.15, 0.04), face, Vector3(0, size * 0.55, size * 1.15)))


func _pumpkin(p: Vector3) -> void:
	var n := Node3D.new()
	n.position = p
	n.rotation.y = rng.randf_range(-0.6, 0.6)
	add_child(n)
	_pumpkin_mesh(n, rng.randf_range(0.4, 0.75))


func _dead_tree(p: Vector3) -> void:
	var bark := Color(0.2, 0.15, 0.13)
	add_child(Util.cylinder(0.25, 3.2, bark, p + Vector3(0, 1.6, 0), false, 0.1))
	for i in 4:
		var a := i * TAU / 4.0 + rng.randf() * 0.8
		var branch := Util.cylinder(0.1, 1.6, bark, p + Vector3(sin(a) * 0.55, 2.6 + i * 0.2, cos(a) * 0.55), false, 0.03)
		branch.rotation = Vector3(cos(a) * 0.9, 0, -sin(a) * 0.9)
		add_child(branch)


func _build_graveyard(r: Rect2) -> void:
	## The old graveyard inside the loop of the lane: railings, wonky headstones, a crypt and some mist
	footprints.append(r)
	add_child(Util.box(Vector3(r.size.x, 0.1, r.size.y), Color(0.16, 0.2, 0.12), _v3(r.get_center(), 0.02)))
	var x := r.position.x
	while x <= r.end.x:
		add_child(Util.cylinder(0.05, 1.6, Color(0.1, 0.1, 0.12), Vector3(x, 0.8, r.position.y)))
		add_child(Util.sphere(0.08, Color(0.1, 0.1, 0.12), Vector3(x, 1.65, r.position.y)))
		x += 0.6
	add_child(Util.box(Vector3(r.size.x, 0.08, 0.08), Color(0.1, 0.1, 0.12), Vector3(r.get_center().x, 1.4, r.position.y)))
	var stone := Color(0.55, 0.55, 0.6)
	var words := ["R.I.P.", "BOO", "R.I.P.", "TOWED", "FINED", "R.I.P."]
	var gz := r.position.y + 3.0
	var row := 0
	while gz < r.position.y + 18.0:
		var gx := r.position.x + 2.0 + (row % 2) * 1.2
		while gx < r.end.x - 1.5:
			var g := Node3D.new()
			g.position = Vector3(gx, 0, gz)
			g.rotation = Vector3(rng.randf_range(-0.15, 0.1), 0, rng.randf_range(-0.15, 0.15))
			add_child(g)
			g.add_child(Util.box(Vector3(1.0, 1.1, 0.25), Util.mat(stone, true), Vector3(0, 0.55, 0)))
			var top := Util.cylinder(0.5, 0.25, Util.mat(stone, true), Vector3(0, 1.1, 0))
			top.rotation.x = PI / 2
			g.add_child(top)
			if rng.randf() < 0.5:
				var l := Util.label3d(words[rng.randi() % words.size()], 26, Color(0.2, 0.2, 0.25), Vector3(0, 0.75, 0.14))
				l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
				l.no_depth_test = false
				l.outline_size = 0
				g.add_child(l)
			gx += 2.6
		gz += 3.2
		row += 1
	# Crypt
	var crypt := Vector3(r.get_center().x, 0, r.position.y + 22.0)
	add_child(Util.box(Vector3(5, 3, 4), Util.mat(Color(0.45, 0.45, 0.5), true), crypt + Vector3(0, 1.5, 0)))
	var roof := Util.prism(Vector3(5.6, 1.4, 4.4), Color(0.3, 0.3, 0.35), crypt + Vector3(0, 3.7, 0))
	add_child(roof)
	add_child(Util.box(Vector3(1.4, 2.0, 0.1), Color(0.08, 0.06, 0.08), crypt + Vector3(0, 1.0, -2.02)))
	var ghost := Util.label3d("WOOO...", 50, Color(0.7, 1, 0.75, 0.8), crypt + Vector3(0, 5.2, 0))
	add_child(ghost)


# ---------------------------------------------------------------- Christmas Eve

func _xmas_shop(r: Rect2, h: float, facing: Vector3, _setback: float) -> void:
	var palette := [Color(0.75, 0.25, 0.22), Color(0.9, 0.85, 0.75), Color(0.3, 0.45, 0.35), Color(0.55, 0.35, 0.3), Color(0.85, 0.8, 0.88)]
	var c: Color = palette[rng.randi() % palette.size()]
	var node := _add_building(r, h, c, facing)
	var s: Vector3 = node.get_meta("size")
	var front := s.z / 2.0
	_roof(node, c, true)
	var shop_col: Color = [Color(0.8, 0.1, 0.12), Color(0.1, 0.5, 0.2), Color(0.9, 0.75, 0.2)][rng.randi() % 3]
	_part(node, Vector3(s.x - 0.4, 3.0, 0.3), shop_col, Vector3(0, 1.5, front + 0.1))
	_part(node, Vector3(s.x - 1.6, 1.8, 0.1), Util.glow(Color(1, 0.85, 0.5), 1.0), Vector3(0, 1.2, front + 0.3))
	_windows(node, Util.glow(Color(1, 0.8, 0.45), 1.2), 2, 2.4, 4.6)
	# Snow on the shop front, a wreath on the door and fairy lights along the top
	_part(node, Vector3(s.x - 0.2, 0.15, 0.8), Color(0.97, 0.98, 1.0), Vector3(0, 3.05, front + 0.4))
	var wreath := Util.torus(0.25, 0.42, Util.mat(Color(0.1, 0.45, 0.2), true), Vector3(s.x / 2.0 - 0.9, 2.2, front + 0.4))
	wreath.rotation.x = PI / 2
	node.add_child(wreath)
	node.add_child(Util.sphere(0.1, Util.mat(Color(0.9, 0.1, 0.1)), Vector3(s.x / 2.0 - 0.9, 1.9, front + 0.45)))
	var t := -s.x / 2.0 + 0.4
	var i := 0
	while t < s.x / 2.0 - 0.2:
		var bulb: Color = [Color(1, 0.2, 0.2), Color(0.3, 1, 0.4), Color(1, 0.85, 0.3), Color(0.4, 0.6, 1)][i % 4]
		node.add_child(Util.sphere(0.09, Util.glow(bulb, 3.0), Vector3(t, 3.0 - absf(sin(t)) * 0.15, front + 0.3)))
		t += 0.6
		i += 1
	var sign := Util.label3d(XMAS_NAMES[rng.randi() % XMAS_NAMES.size()], 64, Color.WHITE, Vector3(0, minf(3.7, s.y - 0.4), front + 0.4))
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign.no_depth_test = false
	node.add_child(sign)


func _snowman(p: Vector3) -> void:
	add_child(Util.sphere(0.9, Util.mat(Color.WHITE, true), p + Vector3(0, 0.8, 0)))
	add_child(Util.sphere(0.6, Util.mat(Color.WHITE, true), p + Vector3(0, 2.0, 0)))
	add_child(Util.cylinder(0.08, 0.4, Color(1, 0.5, 0.1), p + Vector3(0, 2.0, 0.65)))
	add_child(Util.cylinder(0.4, 0.5, Color(0.1, 0.1, 0.1), p + Vector3(0, 2.75, 0)))
	add_child(Util.box(Vector3(1.0, 0.15, 0.3), Color(0.85, 0.1, 0.1), p + Vector3(0, 1.55, 0.2)))


func _build_xmas_square(r: Rect2) -> void:
	## The town square: a giant tree with presents, Santa's grotto and market stalls round the edge
	footprints.append(r.grow(2.0))
	add_child(Util.box(Vector3(r.size.x, 0.09, r.size.y), Color(0.78, 0.76, 0.8), _v3(r.get_center(), 0.0)))
	var tree := Vector3(r.get_center().x - 8.0, 0, r.position.y + 6.0)
	add_solid(Vector3(3.0, 1.6, 3.0), Color(0.55, 0.15, 0.12), tree + Vector3(0, 0.8, 0))
	for i in 5:
		add_child(Util.cylinder(4.2 - i * 0.8, 2.6, Color(0.08, 0.38, 0.18), tree + Vector3(0, 2.6 + i * 1.8, 0), false, 0.15))
	for i in 30:
		var a := i * 2.4
		var y := 2.0 + (i % 10) * 0.85
		var rad := 4.0 - (y - 2.0) * 0.45
		var col: Color = [Color(1, 0.2, 0.2), Color(1, 0.85, 0.2), Color(0.3, 0.6, 1), Color(0.95, 0.95, 1)][i % 4]
		add_child(Util.sphere(0.25, Util.glow(col, 2.5), tree + Vector3(sin(a) * rad, y, cos(a) * rad)))
	add_child(Util.sphere(0.7, Util.glow(Color(1, 0.9, 0.3), 5.0), tree + Vector3(0, 11.6, 0)))
	var tl := OmniLight3D.new()
	tl.light_color = Color(1, 0.85, 0.5)
	tl.light_energy = 3.0
	tl.omni_range = 14.0
	tl.position = tree + Vector3(0, 5, 3)
	add_child(tl)
	lights.append(tl)
	for i in 7:
		var a := i * TAU / 7.0
		var c: Color = [Color(0.9, 0.15, 0.15), Color(0.15, 0.6, 0.25), Color(0.2, 0.4, 0.95), Color(0.95, 0.8, 0.2)][i % 4]
		var gift := tree + Vector3(sin(a) * 2.2, 0.35, cos(a) * 2.2 + 0.4)
		add_child(Util.box(Vector3(0.8, 0.7, 0.8), Util.mat(c, true), gift))
		add_child(Util.box(Vector3(0.82, 0.72, 0.15), Color(1, 0.9, 0.4), gift))
	# Santa's grotto
	var grotto := Vector3(r.get_center().x + 12.0, 0, r.position.y + 4.5)
	add_solid(Vector3(6, 3.2, 4), Color(0.5, 0.32, 0.2), grotto + Vector3(0, 1.6, 0))
	add_child(Util.prism(Vector3(6.6, 1.6, 4.6), Color(0.97, 0.98, 1.0), grotto + Vector3(0, 4.0, 0)))
	add_child(Util.box(Vector3(1.4, 2.0, 0.1), Util.glow(Color(1, 0.75, 0.4), 1.5), grotto + Vector3(0, 1.0, 2.02)))
	add_child(Util.label3d("SANTA'S GROTTO", 64, Color(1, 0.3, 0.3), grotto + Vector3(0, 5.6, 0)))
	add_child(Util.label3d("BACK SOON - ON MY ROUNDS!", 30, Color.WHITE, grotto + Vector3(0, 2.6, 2.1)))
	# Market stalls along the back of the square
	var x := r.position.x + 3.0
	while x < r.end.x - 8.0:
		if absf(x - tree.x) > 6.0:
			_market_stall(Vector3(x, 0, r.position.y + 2.0))
		x += 6.0
	add_child(Util.label3d("MERRY CHRISTMAS!", 90, Color(1, 0.85, 0.3), Vector3(r.get_center().x, 8.0, r.position.y - 2.0)))


func _tree(p: Vector3) -> void:
	add_child(Util.cylinder(0.25, 2.0, Color(0.45, 0.3, 0.2), p + Vector3(0, 1.0, 0)))
	var leaf := Color(0.3, 0.6, 0.25) if def.theme != "city" else Color(0.15, 0.35, 0.25)
	add_child(Util.sphere(1.4, leaf, p + Vector3(0, 2.8, 0)))
	add_child(Util.sphere(1.0, leaf.lightened(0.1), p + Vector3(0.6, 3.6, 0.3)))


func _pine(p: Vector3) -> void:
	add_child(Util.cylinder(0.2, 1.0, Color(0.4, 0.28, 0.2), p + Vector3(0, 0.5, 0)))
	for i in 3:
		var y := 1.2 + i * 1.0
		var rad := 1.5 - i * 0.4
		add_child(Util.cylinder(rad, 1.4, Color(0.15, 0.4, 0.25), p + Vector3(0, y, 0), false, 0.05))
		add_child(Util.cylinder(rad * 0.6, 0.4, Color.WHITE, p + Vector3(0, y + 0.45, 0), false, 0.05))


func _topiary(p: Vector3) -> void:
	add_child(Util.cylinder(0.5, 0.6, Color(0.7, 0.4, 0.3), p + Vector3(0, 0.3, 0)))
	add_child(Util.sphere(0.8, Color(0.2, 0.5, 0.2), p + Vector3(0, 1.3, 0)))
	add_child(Util.sphere(0.5, Color(0.2, 0.5, 0.2), p + Vector3(0, 2.3, 0)))


func _fountain(p: Vector3) -> void:
	add_child(Util.cylinder(1.4, 0.6, Color(0.9, 0.88, 0.85), p + Vector3(0, 0.3, 0)))
	add_child(Util.cylinder(1.2, 0.1, Color(0.4, 0.7, 0.95), p + Vector3(0, 0.6, 0)))
	add_child(Util.cylinder(0.25, 1.6, Color(0.9, 0.88, 0.85), p + Vector3(0, 1.2, 0)))
	add_child(Util.sphere(0.5, Util.metal(Color(1, 0.8, 0.2), false), p + Vector3(0, 2.2, 0)))


func _market_stall(p: Vector3) -> void:
	var c := Color.from_hsv(rng.randf(), 0.6, 0.9)
	add_child(Util.box(Vector3(2.4, 0.9, 1.2), Color(0.55, 0.4, 0.25), p + Vector3(0, 0.45, 0)))
	for x in [-1.1, 1.1]:
		add_child(Util.box(Vector3(0.1, 2.2, 0.1), Color(0.4, 0.3, 0.2), p + Vector3(x, 1.1, 0)))
	add_child(Util.box(Vector3(2.6, 0.15, 1.6), c, p + Vector3(0, 2.2, 0)))
	for i in 4:
		add_child(Util.sphere(0.18, Color.from_hsv(rng.randf(), 0.8, 0.9), p + Vector3(-0.8 + i * 0.5, 1.05, 0)))


func _build_beach() -> void:
	add_child(Util.box(Vector3(region.size.x + 60, 0.2, 16), Color(0.98, 0.88, 0.6), Vector3(region.get_center().x, 0.0, 16)))
	var sea := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(region.size.x + 80, 60)
	pm.subdivide_width = 80
	pm.subdivide_depth = 30
	sea.mesh = pm
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode diffuse_toon, specular_toon;
uniform vec3 deep : source_color = vec3(0.1, 0.45, 0.8);
uniform vec3 foam : source_color = vec3(0.85, 0.95, 1.0);
varying float h;
void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	h = sin(w.x * 0.35 + TIME * 1.4) * 0.5 + sin(w.z * 0.5 + TIME * 1.1) * 0.5;
	VERTEX.y += h * 0.18;
}
void fragment() {
	float f = smoothstep(0.75, 0.95, h);
	ALBEDO = mix(deep, foam, f * 0.6);
	ROUGHNESS = 0.2;
}
"""
	sea_material = ShaderMaterial.new()
	sea_material.shader = sh
	sea.material_override = sea_material
	sea.position = Vector3(region.get_center().x, 0.05, 54)
	add_child(sea)
	# Beach huts, deckchairs and a pier
	var x := bounds.position.x + 2.0
	while x < 20.0:
		var c := Color.from_hsv(rng.randf(), 0.55, 0.95)
		add_child(Util.box(Vector3(2.2, 2.2, 2.0), c, Vector3(x, 1.1, 13.0)))
		var roof := Util.prism(Vector3(2.6, 0.9, 2.2), Color.WHITE, Vector3(x, 2.65, 13.0))
		add_child(roof)
		x += rng.randf_range(3.0, 4.5)
	for i in 10:
		var p := Vector3(rng.randf_range(bounds.position.x, 30), 0.1, rng.randf_range(16, 22))
		var c := Color.from_hsv(rng.randf(), 0.7, 0.95)
		add_child(Util.cylinder(0.05, 2.0, Color.WHITE, p + Vector3(0, 1.0, 0)))
		add_child(Util.cylinder(1.2, 0.3, c, p + Vector3(0, 2.0, 0), false, 0.1))
	for i in 14:
		add_child(Util.box(Vector3(4.0, 0.3, 2.0), Color(0.6, 0.45, 0.3), Vector3(-10, 0.6, 22.0 + i * 2.0)))
	for i in range(0, 14, 2):
		for xx in [-11.8, -8.2]:
			add_child(Util.cylinder(0.15, 2.0, Color(0.45, 0.3, 0.2), Vector3(xx, 0.0, 22.0 + i * 2.0)))
	footprints.append(Rect2(region.position.x, 9.0, region.size.x, 60))


func _build_green() -> void:
	## Snowy village green inside the U, with a frozen pond and a Christmas tree
	var green := Rect2(-21.5, -17.5, 43, 60)
	add_child(Util.box(Vector3(green.size.x, 0.12, green.size.y), Color(0.97, 0.98, 1.0), Vector3(0, 0.0, green.get_center().y)))
	add_child(Util.cylinder(6.0, 0.1, Color(0.7, 0.85, 0.95), Vector3(-8, 0.08, 10)))
	var tree := Vector3(8, 0, 2)
	add_child(Util.cylinder(0.4, 1.2, Color(0.4, 0.28, 0.2), tree + Vector3(0, 0.6, 0)))
	for i in 4:
		add_child(Util.cylinder(3.0 - i * 0.65, 2.2, Color(0.1, 0.4, 0.2), tree + Vector3(0, 1.6 + i * 1.5, 0), false, 0.1))
	for i in 16:
		var a := i * 2.4
		var y := 1.2 + (i % 8) * 0.7
		var rad := 3.0 - (y - 1.2) * 0.42
		var col: Color = [Color(1, 0.2, 0.2), Color(1, 0.85, 0.2), Color(0.3, 0.6, 1)][i % 3]
		add_child(Util.sphere(0.2, Util.glow(col, 2.0), tree + Vector3(sin(a) * rad, y, cos(a) * rad)))
	add_child(Util.sphere(0.5, Util.glow(Color(1, 0.9, 0.3), 4.0), tree + Vector3(0, 7.8, 0)))
	for p in [Vector3(-14, 0, -6), Vector3(14, 0, 18), Vector3(-2, 0, 22)]:
		add_child(Util.sphere(0.9, Color.WHITE, p + Vector3(0, 0.8, 0)))
		add_child(Util.sphere(0.6, Color.WHITE, p + Vector3(0, 2.0, 0)))
		add_child(Util.cylinder(0.08, 0.4, Color(1, 0.5, 0.1), p + Vector3(0, 2.0, 0.65)))
		add_child(Util.cylinder(0.4, 0.5, Color(0.1, 0.1, 0.1), p + Vector3(0, 2.75, 0)))
	footprints.append(Rect2(-12, -14, 24, 40))


func _build_plaza() -> void:
	var c := Vector3(0, 0, 0)
	add_child(Util.box(Vector3(22, 0.1, 22), Color(0.25, 0.22, 0.3), c))
	add_child(Util.cylinder(3.0, 0.5, Color(0.4, 0.4, 0.5), c + Vector3(0, 0.25, 0)))
	add_child(Util.cylinder(2.7, 0.1, Util.glow(Color(0.3, 0.6, 1.0), 1.5), c + Vector3(0, 0.5, 0)))
	var ring := Util.torus(1.2, 1.5, Util.glow(Color(1.0, 0.3, 0.8), 3.0), c + Vector3(0, 3.0, 0))
	ring.rotation.x = PI / 2
	add_child(ring)
	footprints.append(Rect2(-11, -11, 22, 22))


func _build_paths() -> void:
	var col := Color(0.72, 0.62, 0.5) if def.theme not in ["snow", "city", "xmas", "halloween"] else (Color(0.85, 0.87, 0.92) if def.theme in ["snow", "xmas"] else Color(0.3, 0.28, 0.36))
	var edge_col := Color(0.3, 0.55, 0.25) if def.theme not in ["snow", "city", "xmas", "halloween"] else Color(0.45, 0.45, 0.5)
	for r in path_rects:
		add_child(Util.box(Vector3(r.size.x, 0.1, r.size.y), col, _v3(r.get_center(), 0.0)))
		# Paving stripes, and low hedges or railings along the long sides
		var horizontal := r.size.x > r.size.y
		var length := r.size.x if horizontal else r.size.y
		var t := 1.0
		while t < length:
			var p := Vector2(r.position.x + t, r.get_center().y) if horizontal else Vector2(r.get_center().x, r.position.y + t)
			var stripe := Util.box(Vector3(0.08, 0.02, (r.size.y if horizontal else r.size.x) - 0.6), col.darkened(0.15), _v3(p, 0.06))
			if not horizontal:
				stripe.rotation.y = PI / 2
			add_child(stripe)
			t += 1.0
		for side in [-1.0, 1.0]:
			var t2 := 0.5
			while t2 < length - 0.5:
				var q: Vector2
				if horizontal:
					q = Vector2(r.position.x + t2, r.get_center().y + side * (r.size.y / 2.0 + 0.3))
				else:
					q = Vector2(r.get_center().x + side * (r.size.x / 2.0 + 0.3), r.position.y + t2)
				if not _in_any_walk(q):
					add_child(Util.box(Vector3(1.0, 0.7, 0.5) if horizontal else Vector3(0.5, 0.7, 1.0), edge_col, _v3(q, 0.35)))
				t2 += 1.0
		# A bench and a lamp on the longer ones
		if length > 14.0:
			var mid := r.get_center()
			var off := Vector2(0, r.size.y / 2.0 - 0.5) if horizontal else Vector2(r.size.x / 2.0 - 0.5, 0)
			var along := Vector2(4, 0) if horizontal else Vector2(0, 4)
			add_child(Util.box(Vector3(1.6, 0.1, 0.5) if horizontal else Vector3(0.5, 0.1, 1.6), Color(0.55, 0.35, 0.2), _v3(mid + off, 0.5), true))
			add_child(Util.box(Vector3(0.3, 4.0, 0.3), Color(0.2, 0.2, 0.25), _v3(mid - off + along, 2.0)))
			add_child(Util.box(Vector3(0.6, 0.25, 0.6), Util.glow(Color(1, 0.9, 0.6), 2.5 if def.get("night", false) else 0.6), _v3(mid - off + along, 4.1)))
		add_child(Util.label3d("FOOTPATH", 30, Color(0.95, 0.95, 0.95), _v3(r.get_center(), 1.6)))


func _in_any_walk(q: Vector2) -> bool:
	for w in walk_rects:
		if w.grow(0.1).has_point(q):
			return true
	return false


# ---------------------------------------------------------------- car parks

func _build_supermarket() -> void:
	# The store along the top, with a big sign and trolley bays
	var store := Rect2(-50, -60, 100, 26)
	footprints.append(store)
	var c := Vector3(store.get_center().x, 0, store.get_center().y)
	add_child(Util.box(Vector3(store.size.x, 9.0, store.size.y), Util.mat(Color(0.9, 0.9, 0.88), false, true), c + Vector3(0, 4.5, 0)))
	add_child(Util.box(Vector3(store.size.x + 0.4, 1.6, 0.4), Color(0.1, 0.55, 0.3), Vector3(c.x, 8.0, store.end.y + 0.2)))
	add_child(Util.box(Vector3(30, 3.0, 0.3), Color(0.6, 0.8, 0.95), Vector3(c.x, 1.5, store.end.y + 0.15)))
	var sign := Util.label3d("SUPERSAVE", 220, Color(1, 0.9, 0.2), Vector3(c.x, 11.5, store.end.y))
	sign.outline_modulate = Color(0.1, 0.4, 0.2)
	add_child(sign)
	add_child(Util.label3d("OPEN 24 HOURS", 60, Color.WHITE, Vector3(c.x, 8.0, store.end.y + 0.5)))
	for x in [-40.0, -12.0, 12.0, 40.0]:
		_trolley_bay(Vector3(x, 0, -2.5 if absf(x) > 20.0 else 4.0))
	# Speed bumps, arrows and "SLOW" painted on the aisles
	for seg in segments:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var d := (b - a).normalized()
		var t := 20.0
		while t < a.distance_to(b):
			var q: Vector2 = a + d * t
			if bounds.has_point(q) and not _in_road_except_segment(q, seg):
				var bump := Util.box(Vector3(0.6, 0.12, ROAD_HALF * 2.0 - 0.4), Color(1, 0.85, 0.1), _v3(q, 0.06))
				bump.rotation.y = yaw_of(_v3(d))
				add_child(bump)
			t += 24.0
	_scatter(14, _planter)


func _in_road_except_segment(q: Vector2, seg: Dictionary) -> bool:
	for i in segments.size():
		if segments[i] != seg and road_rects[i].grow(2.0).has_point(q):
			return true
	return false


func _trolley_bay(p: Vector3) -> void:
	add_child(Util.box(Vector3(4.0, 0.1, 1.6), Color(0.2, 0.5, 0.3), p + Vector3(0, 2.4, 0), true))
	for x in [-1.9, 1.9]:
		add_child(Util.box(Vector3(0.1, 2.4, 0.1), Color(0.6, 0.6, 0.65), p + Vector3(x, 1.2, 0)))
	for i in 5:
		var t := Node3D.new()
		t.position = p + Vector3(-1.4 + i * 0.4, 0, 0)
		add_child(t)
		t.add_child(Util.box(Vector3(0.35, 0.55, 0.9), Util.metal(Color(0.75, 0.75, 0.8), false), Vector3(0, 0.7, 0)))
		t.add_child(Util.box(Vector3(0.38, 0.05, 0.05), Color(0.9, 0.1, 0.1), Vector3(0, 1.05, -0.48)))
	add_child(Util.label3d("TROLLEYS", 30, Color.WHITE, p + Vector3(0, 2.9, 0)))
	slow_zones.append([Vector2(p.x, p.z), 0.1])


func _planter(p: Vector3) -> void:
	add_child(Util.box(Vector3(2.0, 0.7, 2.0), Color(0.6, 0.58, 0.55), p + Vector3(0, 0.35, 0), true))
	add_child(Util.sphere(0.9, Color(0.3, 0.6, 0.25), p + Vector3(0, 1.1, 0)))


func _build_multistorey() -> void:
	## A split-level car park: flat decks joined by ramps (see the "decks" terrain in levels.gd).
	## Height is added afterwards by terrain.gd, so everything here is built as if flat.
	var concrete := Color(0.55, 0.55, 0.57)
	var t: Dictionary = def.get("terrain", {})
	var knots: Array = t.get("knots", [])
	var ramps: Array = []  # [x0, x1] bands where the floor slopes
	for i in range(1, knots.size()):
		if absf(float(knots[i][1]) - float(knots[i - 1][1])) > 0.01:
			ramps.append([float(knots[i - 1][0]), float(knots[i][0])])
	# Outer walls, in short pieces so they step up the ramps with the floor
	var r := bounds.grow(1.0)
	var x := r.position.x
	while x < r.end.x:
		for zz in [r.position.y, r.end.y]:
			if not _in_road(Vector2(x + 1.5, zz)):
				add_child(Util.box(Vector3(3.0, 1.2, 0.6), concrete, Vector3(x + 1.5, 0.6, zz), true))
				add_child(Util.box(Vector3(3.02, 0.2, 0.62), Color(1, 0.85, 0.1), Vector3(x + 1.5, 1.1, zz)))
		x += 3.0
	var z := r.position.y
	while z < r.end.y:
		if not _in_road(Vector2(r.end.x, z + 1.5)):
			add_child(Util.box(Vector3(0.6, 1.2, 3.0), concrete, Vector3(r.end.x, 0.6, z + 1.5), true))
			add_child(Util.box(Vector3(0.62, 0.2, 3.02), Color(1, 0.85, 0.1), Vector3(r.end.x, 1.1, z + 1.5)))
		z += 3.0
	# Deck names painted on the floor
	var decks := []
	var prev := bounds.position.x
	for rp in ramps:
		decks.append([prev, rp[0]])
		prev = rp[1]
	decks.append([prev, bounds.end.x])
	var names: Array = t.get("names", ["LEVEL 2", "LEVEL 3", "ROOF"])
	for i in decks.size():
		var cx := (float(decks[i][0]) + float(decks[i][1])) / 2.0
		var l := Util.label3d(names[mini(i, names.size() - 1)], 110, Color(1, 0.85, 0.1), Vector3(cx, 0.2, 0))
		l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		l.rotation.x = -PI / 2
		add_child(l)
	# The gap beside each ramp: a dark drop with railings, so the ramps read as ramps
	for rp in ramps:
		var x0: float = rp[0]
		var x1: float = rp[1]
		for seg in segments:
			if absf(seg.a.y - seg.b.y) > 0.1:
				continue
			# Arrows and RAMP painted on the aisles
			var rz: float = seg.a.y
			var up: bool = (seg.b.x > seg.a.x) == (float(knots[0][1]) < float(knots[-1][1]))
			for k in 2:
				var ax := lerpf(x0, x1, 0.3 + k * 0.4)
				var arrow := Util.label3d("RAMP", 80, Color.WHITE, Vector3(ax, 0.12, rz))
				arrow.billboard = BaseMaterial3D.BILLBOARD_DISABLED
				arrow.rotation = Vector3(-PI / 2, 0, 0)
				add_child(arrow)
			add_child(Util.label3d("UP >" if up else "< DOWN", 50, Color(0.6, 1, 0.6), Vector3((x0 + x1) / 2.0, 3.2, rz - 5.0)))
		var zz := bounds.position.y
		while zz < bounds.end.y:
			var q := Vector2((x0 + x1) / 2.0, zz + 1.0)
			if not _in_any_walk(q) and not _in_road(q):
				var mx := x0 + 0.5
				while mx < x1:
					add_child(Util.box(Vector3(1.0, 0.1, 2.0), Color(0.06, 0.06, 0.08), Vector3(mx + 0.5, 0.12, zz + 1.0)))
					mx += 1.0
			zz += 2.0
		# Railings along the drop
		var rx := x0
		while rx <= x1:
			for edge_z in _gap_edges(rx):
				add_child(Util.box(Vector3(1.0, 0.18, 0.15), Color(1, 0.8, 0.1) if int(rx) % 2 == 0 else Color(0.1, 0.1, 0.12), Vector3(rx, 0.95, edge_z)))
				add_child(Util.box(Vector3(0.1, 0.9, 0.1), Color(0.8, 0.8, 0.82), Vector3(rx, 0.45, edge_z)))
			rx += 1.0
		for ex in [x0, x1]:
			var ez := bounds.position.y
			while ez < bounds.end.y:
				var q := Vector2(ex + (0.6 if ex == x0 else -0.6), ez + 0.5)
				if not _in_any_walk(q) and not _in_road(q):
					add_child(Util.box(Vector3(0.15, 0.18, 1.0), Color(1, 0.8, 0.1), Vector3(ex, 0.95, ez + 0.5)))
					add_child(Util.box(Vector3(0.1, 0.9, 0.1), Color(0.8, 0.8, 0.82), Vector3(ex, 0.45, ez + 0.5)))
				ez += 1.0
	# Pillars on a grid, kept off the aisles, parking bays and ramps; the roof deck has none
	var roof_x: float = float(knots[-1][0]) if not knots.is_empty() else INF
	x = bounds.position.x + 4.0
	while x < bounds.end.x - 2.0:
		z = bounds.position.y + 3.0
		while z < bounds.end.y - 2.0:
			var q := Vector2(x, z)
			var clear := not _in_road(q) and x < roof_x and _flat_at(q)
			for s in spots:
				if Vector2(s.pos.x, s.pos.z).distance_to(q) < 4.0:
					clear = false
			for pr in path_rects:
				if pr.grow(0.8).has_point(q):
					clear = false
			if clear and _in_any_walk(q):
				add_solid(Vector3(1.0, 5.0, 1.0), concrete, _v3(q, 2.5))
				for h in [0.4, 1.2]:
					add_child(Util.box(Vector3(1.04, 0.3, 1.04), Color(1, 0.8, 0.1) if h < 1.0 else Color(0.1, 0.1, 0.1), _v3(q, h)))
			z += 12.0
		x += 12.0
	# Strip lights hanging over the aisles (not over the open roof)
	for seg in segments:
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var d := (b - a).normalized()
		var tt := 6.0
		while tt < a.distance_to(b):
			var q: Vector2 = a + d * tt
			if bounds.has_point(q) and q.x < roof_x:
				var strip := Util.box(Vector3(2.4, 0.12, 0.3), Util.glow(Color(0.85, 0.95, 1.0), 3.0), _v3(q, 4.8))
				strip.rotation.y = yaw_of(_v3(d))
				add_child(strip)
				if lights.size() < 16:
					var light := OmniLight3D.new()
					light.light_color = Color(0.85, 0.95, 1.0)
					light.light_energy = 1.6
					light.omni_range = 11.0
					light.position = _v3(q, 4.4)
					add_child(light)
					lights.append(light)
			tt += 14.0
	# Roof deck: lamp posts and a view of the city lights
	if roof_x < INF:
		for q in [Vector2(roof_x + 4, -9), Vector2(roof_x + 4, 9), Vector2(bounds.end.x - 4, 0)]:
			add_solid(Vector3(0.3, 4.2, 0.3), Color(0.25, 0.25, 0.3), _v3(q, 2.1), false)
			add_child(Util.box(Vector3(0.6, 0.25, 0.6), Util.glow(Color(1, 0.9, 0.6), 2.5), _v3(q, 4.3)))
			if lights.size() < 20:
				var l := OmniLight3D.new()
				l.light_color = Color(1, 0.9, 0.6)
				l.light_energy = 2.2
				l.omni_range = 10.0
				l.position = _v3(q, 3.8)
				add_child(l)
				lights.append(l)
		for i in 30:
			var bx := rng.randf_range(bounds.end.x + 20, bounds.end.x + 80)
			var bz := rng.randf_range(bounds.position.y - 60, bounds.end.y)
			var bh := rng.randf_range(8, 30)
			var tower := Util.box(Vector3(8, bh, 8), Color(0.12, 0.12, 0.18), Vector3(bx, bh / 2.0 - 4.0, bz))
			add_child(tower)
			for k in 3:
				add_child(Util.box(Vector3(6, 0.6, 0.1), Util.glow(Color(1, 0.85, 0.5), 1.5), Vector3(bx, rng.randf_range(0, bh - 5.0), bz + 4.05)))


## Is the floor level here (not on a ramp)?
func _flat_at(q: Vector2) -> bool:
	var t: Dictionary = def.get("terrain", {})
	if t.get("type", "") != "decks":
		return true
	return absf(Terrain.height(t, q.x + 1.0, q.y) - Terrain.height(t, q.x - 1.0, q.y)) < 0.01


## z positions along x where the walkable floor meets the drop beside a ramp.
func _gap_edges(x: float) -> Array:
	var out := []
	var z := bounds.position.y
	var was := _in_any_walk(Vector2(x, z))
	while z < bounds.end.y:
		z += 0.5
		var now := _in_any_walk(Vector2(x, z))
		if now != was:
			out.append(z - 0.25)
		was = now
	return out


# ---------------------------------------------------------------- special event decorations

func _build_event_deco() -> void:
	match def.get("deco", ""):
		"bins":
			for i in 70:
				var p := random_walk_point(rng, Vector3.ZERO, 0.0, true)
				var q := Vector2(p.x, p.z)
				if q.distance_to(def.start) < 4.0:
					continue
				for k in rng.randi_range(2, 4):
					var off := Vector3(rng.randf_range(-0.7, 0.7), 0, rng.randf_range(-0.7, 0.7))
					var bag := Util.sphere(rng.randf_range(0.35, 0.5), Color(0.08, 0.08, 0.1), p + off + Vector3(0, 0.3, 0), true)
					bag.scale.y = 0.8
					add_child(bag)
					add_child(Util.cylinder(0.06, 0.25, Color(0.08, 0.08, 0.1), p + off + Vector3(0, 0.7, 0)))
				if rng.randf() < 0.3:
					add_child(Util.label3d("~ ~ ~", 36, Color(0.5, 0.75, 0.3), p + Vector3(0, 1.4, 0)))
				slow_zones.append([q, 1.3])
		"wedding":
			_bunting_along(Color(1, 0.7, 0.8), Color.WHITE, 3.4)
			var arch_p := Vector3(def.start.x, 0, def.start.y)
			for x in [-2.5, 2.5]:
				add_child(Util.cylinder(0.15, 3.6, Color.WHITE, arch_p + Vector3(x, 1.8, -4.0)))
			for i in 9:
				var a := PI * i / 8.0
				add_child(Util.sphere(0.4, Color(1, 0.6, 0.75) if i % 2 else Color.WHITE,
					arch_p + Vector3(-cos(a) * 2.5, 3.6 + sin(a) * 1.4, -4.0), true))
			add_child(Util.label3d("CONGRATULATIONS!", 70, Color(1, 0.5, 0.7), arch_p + Vector3(0, 5.6, -4.0)))
			_confetti(arch_p + Vector3(0, 6, -4), [Color(1, 0.6, 0.75), Color.WHITE, Color(1, 0.9, 0.4)])
		"football":
			_bunting_along(Color(0.9, 0.1, 0.1), Color(0.1, 0.3, 0.9), 3.6)
			var ball := Util.sphere(2.2, Color.WHITE, Vector3(def.start.x + 14, 2.2, def.start.y - 14), true)
			add_child(ball)
			for i in 10:
				var a := i * TAU / 10.0
				add_child(Util.sphere(0.5, Color(0.1, 0.1, 0.1), ball.position + Vector3(sin(a) * 2.0, cos(a) * 1.2, cos(a * 2.0) * 0.9)))
			add_child(Util.label3d("MATCH DAY!", 90, Color(1, 0.9, 0.2), ball.position + Vector3(0, 3.6, 0)))
		"xmas":
			_bunting_along(Color(1, 0.2, 0.2), Color(0.2, 1, 0.4), 3.0, true)
			_scatter(18, _market_stall)
			add_child(Util.label3d("CHRISTMAS MARKET", 80, Color(1, 0.85, 0.3), Vector3(def.start.x, 6.0, def.start.y - 6.0)))
			_confetti(Vector3(0, 12, 0), [Color.WHITE], 60.0)


func _bunting_along(c1: Color, c2: Color, height: float, lights := false) -> void:
	## Strings of flags (or fairy lights) along the pavements
	for w in walk_rects:
		var horizontal := w.size.x > w.size.y
		var length := w.size.x if horizontal else w.size.y
		for edge in [0.04, 0.96]:
			var t := 1.0
			var i := 0
			while t < length - 1.0:
				var p := Vector3.ZERO
				if horizontal:
					p = Vector3(w.position.x + t, height - absf(sin(t * 0.4)) * 0.6, lerpf(w.position.y, w.end.y, edge))
				else:
					p = Vector3(lerpf(w.position.x, w.end.x, edge), height - absf(sin(t * 0.4)) * 0.6, w.position.y + t)
				var col := c1 if i % 2 == 0 else c2
				if lights:
					add_child(Util.sphere(0.12, Util.glow(col, 3.0), p))
				else:
					var flag := Util.prism(Vector3(0.45, 0.5, 0.04), col, p)
					flag.rotation.z = PI
					if not horizontal:
						flag.rotation.y = PI / 2
					add_child(flag)
				t += 1.2
				i += 1


func _confetti(pos: Vector3, colors: Array, spread := 10.0) -> void:
	for c in colors:
		var p := CPUParticles3D.new()
		p.amount = 80 if spread < 20.0 else 400
		p.lifetime = 4.0
		p.preprocess = 4.0
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.12, 0.02, 0.08) if spread < 20.0 else Vector3(0.08, 0.08, 0.08)
		p.mesh = mesh
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		p.material_override = m
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(spread, 0.5, spread)
		p.direction = Vector3(0, -1, 0)
		p.gravity = Vector3(0, -1.5, 0)
		p.initial_velocity_min = 0.5
		p.initial_velocity_max = 1.5
		p.angular_velocity_min = -300.0
		p.angular_velocity_max = 300.0
		p.position = pos
		add_child(p)


func _street_furniture() -> void:
	## Lamp posts, bins and the odd phone box along the outer pavement edge
	var night: bool = def.get("night", false)
	var lamp_col := Color(0.2, 0.2, 0.25) if def.theme != "posh" else Color(0.75, 0.6, 0.2)
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var a: Vector2 = seg.a
		var b: Vector2 = seg.b
		var d := (b - a).normalized()
		var len := a.distance_to(b)
		for side in [1.0, -1.0]:
			var n: Vector2 = Vector2(d.y, -d.x) * side
			var t := rng.randf_range(2.0, 8.0)
			while t < len:
				var p: Vector2 = a + d * t + n * (PAVE_HALF - 0.6)
				t += rng.randf_range(9.0, 16.0)
				if not bounds.grow(-1.0).has_point(p):
					continue
				var bad := false
				for j in pave_rects.size():
					if j != i and pave_rects[j].grow(1.0).has_point(p):
						bad = true
				for s in spots:
					var mp: Vector3 = s.pos + s.normal * 1.6 + s.dir * 2.2
					if Vector2(mp.x, mp.z).distance_to(p) < 2.5:
						bad = true
				if bad:
					continue
				var pos := _v3(p)
				var roll := rng.randf()
				if roll < 0.55:
					add_solid(Vector3(0.3, 4.2, 0.3), lamp_col, pos + Vector3(0, 2.1, 0), false)
					var bulb_col := Color(1, 0.9, 0.6)
					add_child(Util.box(Vector3(0.6, 0.25, 0.6), Util.glow(bulb_col, 2.5 if night else 0.6), pos + Vector3(0, 4.3, 0)))
					if night and lights.size() < 28:
						var l := OmniLight3D.new()
						l.light_color = bulb_col
						l.light_energy = 2.2
						l.omni_range = 9.0
						l.position = pos + Vector3(0, 3.8, 0)
						add_child(l)
						lights.append(l)
				elif roll < 0.8:
					add_solid(Vector3(0.7, 1.0, 0.7), Color(0.2, 0.35, 0.2), pos + Vector3(0, 0.5, 0))
				elif roll < 0.9:
					add_solid(Vector3(0.6, 1.3, 0.6), Color(0.85, 0.1, 0.1), pos + Vector3(0, 0.65, 0))
				else:
					add_solid(Vector3(1.0, 2.6, 1.0), Color(0.85, 0.1, 0.1), pos + Vector3(0, 1.3, 0))
