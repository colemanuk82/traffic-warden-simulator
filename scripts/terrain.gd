extends RefCounted
## Hills and split-level car parks. A level can carry a "terrain" entry:
##   {"type": "hills", "amp": 3.0, "wave": Vector2(70, 90), "rise": 0.0}
##       rolling hills, plus an optional steady climb towards the north (-z)
##   {"type": "decks", "knots": [[x, h], ...]}
##       flat car park decks joined by straight ramps: the height only changes along x
## The world is built flat first; apply() then lifts everything onto the ground, drapes the
## roads, paving and grass over the slopes, and gives the traffic lanes their heights.

const STEP := 1.5
const BIG_STEP := 2.5


static func height(t: Dictionary, x: float, z: float) -> float:
	if t.is_empty():
		return 0.0
	match t.type:
		"hills":
			var amp := float(t.get("amp", 3.0))
			var w: Vector2 = t.get("wave", Vector2(70, 90))
			var h := amp * (0.55 * sin(x * TAU / w.x + 0.7) + 0.35 * sin(z * TAU / w.y + 1.3)
				+ 0.2 * sin((x + z) * TAU / (w.x * 0.55) + 2.1))
			return h - z * float(t.get("rise", 0.0))
		"decks":
			var k: Array = t.knots
			if x <= float(k[0][0]):
				return float(k[0][1])
			for i in range(1, k.size()):
				if x <= float(k[i][0]):
					var f := (x - float(k[i - 1][0])) / (float(k[i][0]) - float(k[i - 1][0]))
					return lerpf(float(k[i - 1][1]), float(k[i][1]), f)
			return float(k[-1][1])
	return 0.0


static func normal(t: Dictionary, x: float, z: float) -> Vector3:
	if t.is_empty():
		return Vector3.UP
	var e := 0.5
	var dx := (height(t, x + e, z) - height(t, x - e, z)) / (2.0 * e)
	var dz := (height(t, x, z + e) - height(t, x, z - e)) / (2.0 * e)
	return Vector3(-dx, 1.0, -dz).normalized()


## Nose-up angle for something at p facing along fwd (cars use it on hills and ramps).
static func pitch(t: Dictionary, p: Vector3, fwd: Vector3) -> float:
	if t.is_empty():
		return 0.0
	var a := height(t, p.x + fwd.x, p.z + fwd.z)
	var b := height(t, p.x - fwd.x, p.z - fwd.z)
	return atan2(a - b, 2.0)


# ---------------------------------------------------------------- lifting a built world

static func apply(world) -> void:
	var t: Dictionary = world.def.get("terrain", {})
	if t.is_empty():
		return
	var hf := func(p: Vector3) -> float: return height(t, p.x, p.z)
	for lane in world.lanes:
		lane.drape(hf)
	for s in world.spots:
		var p: Vector3 = s.pos
		p.y = height(t, p.x, p.z)
		s.pos = p
		var lp: Vector3 = p - s.normal * (world.SPOT_OFFSET - world.LANE_OFFSET)
		lp.y = height(t, lp.x, lp.z)
		s.s = s.lane.project(lp)
	for c in world.get_children():
		_lift(world, t, c)


static func _lift(world, t: Dictionary, c: Node) -> void:
	if not c is Node3D or c is WorldEnvironment or c is DirectionalLight3D:
		return
	var n: Node3D = c
	if n.has_meta("terrain_done"):
		return
	var p := n.position
	if n is MeshInstance3D and n.mesh is BoxMesh:
		var s: Vector3 = n.mesh.size
		var upright := absf(n.rotation.x) < 0.01 and absf(n.rotation.z) < 0.01
		var flat := s.y <= 1.05 and maxf(s.x, s.z) > 2.5 and upright
		if flat:
			_drape_box(world, t, n)
			return
		if s.y <= 0.45 and upright:
			_tilt(t, n)
			return
		if maxf(s.x, s.z) > 6.0:
			# Long walls and big buildings sink into the slope rather than float off it
			n.position.y += _min_height(t, n, Vector2(s.x, s.z))
			return
	elif n is MeshInstance3D and n.mesh is CylinderMesh and n.mesh.height <= 0.25:
		_tilt(t, n)
		return
	elif n is Label3D and n.billboard == BaseMaterial3D.BILLBOARD_DISABLED and absf(absf(n.rotation.x) - PI / 2.0) < 0.05:
		n.position.y += height(t, p.x, p.z)
		return
	elif n.has_meta("size"):
		var sz: Vector3 = n.get_meta("size")
		n.position.y += _min_height(t, n, Vector2(sz.x, sz.z))
		return
	n.position.y += height(t, p.x, p.z)


static func _tilt(t: Dictionary, n: Node3D) -> void:
	var p := n.position
	n.position.y += height(t, p.x, p.z)
	var up := normal(t, p.x, p.z)
	var q := Quaternion(Vector3.UP, up)
	n.basis = Basis(q) * n.basis


static func _min_height(t: Dictionary, n: Node3D, size: Vector2) -> float:
	var lo := INF
	var steps_x := maxi(int(size.x / 4.0), 1)
	var steps_z := maxi(int(size.y / 4.0), 1)
	for i in steps_x + 1:
		for j in steps_z + 1:
			var local := Vector3(-size.x / 2.0 + size.x * i / steps_x, 0, -size.y / 2.0 + size.y * j / steps_z)
			var w := n.transform * local
			lo = minf(lo, height(t, w.x, w.z))
	return lo - 0.1


## Replaces a flat box (road, pavement, grass, markings) with a mesh that follows the ground.
static func _drape_box(world, t: Dictionary, n: MeshInstance3D) -> void:
	var s: Vector3 = n.mesh.size
	var step := BIG_STEP if maxf(s.x, s.z) > 60.0 else STEP
	var nx := maxi(int(ceil(s.x / step)), 1)
	var nz := maxi(int(ceil(s.z / step)), 1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in nx + 1:
		for j in nz + 1:
			var local := Vector3(-s.x / 2.0 + s.x * i / nx, s.y / 2.0, -s.z / 2.0 + s.z * j / nz)
			var w := n.transform * local
			w.y += height(t, w.x, w.z)
			st.set_normal(normal(t, w.x, w.z))
			st.set_uv(Vector2(float(i) / nx, float(j) / nz))
			st.add_vertex(w)
	# Wind the triangles so they face up whichever way the box was turned
	var p0 := n.transform * Vector3(-1, 0, -1)
	var p1 := n.transform * Vector3(1, 0, -1)
	var p2 := n.transform * Vector3(-1, 0, 1)
	var up := (p2 - p0).cross(p1 - p0).y < 0.0
	for i in nx:
		for j in nz:
			var a := i * (nz + 1) + j
			var b := (i + 1) * (nz + 1) + j
			if up:
				st.add_index(a)
				st.add_index(a + 1)
				st.add_index(b)
				st.add_index(b)
				st.add_index(a + 1)
				st.add_index(b + 1)
			else:
				st.add_index(a)
				st.add_index(b)
				st.add_index(a + 1)
				st.add_index(b)
				st.add_index(b + 1)
				st.add_index(a + 1)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = n.material_override
	mi.set_meta("terrain_done", true)
	world.add_child(mi)
	n.queue_free()
