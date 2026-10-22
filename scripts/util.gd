extends RefCounted
## Helpers for building cartoon meshes and labels from code.

static var _mats := {}
static var _font: FontFile


static func mat(color: Color, outline := false, fade := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [color.to_html(), outline, fade]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if fade:
		# Buildings between the camera and the street dither away when the camera gets close
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		m.distance_fade_min_distance = 14.0
		m.distance_fade_max_distance = 20.0
	if outline:
		m.next_pass = _outline_mat()
	_mats[key] = m
	return m


static func glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "glow|%s|%s" % [color.to_html(), energy]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


static func metal(color: Color, outline := true) -> StandardMaterial3D:
	var key := "metal|%s|%s" % [color.to_html(), outline]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 0.9
	m.roughness = 0.3
	if outline:
		m.next_pass = _outline_mat()
	_mats[key] = m
	return m


static func _outline_mat() -> StandardMaterial3D:
	if _mats.has("outline"):
		return _mats["outline"]
	var o := StandardMaterial3D.new()
	o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	o.albedo_color = Color(0.08, 0.06, 0.1)
	o.cull_mode = BaseMaterial3D.CULL_FRONT
	o.grow = true
	o.grow_amount = 0.025
	_mats["outline"] = o
	return o


static func box(size: Vector3, color, pos := Vector3.ZERO, outline := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _instance(mesh, color, pos, outline)


static func sphere(radius: float, color, pos := Vector3.ZERO, outline := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	return _instance(mesh, color, pos, outline)


static func hemisphere(radius: float, color, pos := Vector3.ZERO, outline := false) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius
	mesh.is_hemisphere = true
	mesh.radial_segments = 24
	mesh.rings = 8
	return _instance(mesh, color, pos, outline)


static func cylinder(radius: float, height: float, color, pos := Vector3.ZERO, outline := false,
		top_radius := -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	return _instance(mesh, color, pos, outline)


static func capsule(radius: float, height: float, color, pos := Vector3.ZERO, outline := false) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(height, radius * 2.0)
	return _instance(mesh, color, pos, outline)


static func torus(inner: float, outer: float, color, pos := Vector3.ZERO, outline := false) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	return _instance(mesh, color, pos, outline)


static func prism(size: Vector3, color, pos := Vector3.ZERO) -> MeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = size
	return _instance(mesh, color, pos, false)


static func font() -> FontFile:
	if _font == null:
		_font = FontFile.new()
		_font.load_dynamic_font("res://fonts/LilitaOne-Regular.ttf")
	return _font


static func label3d(text: String, size: int, color: Color, pos := Vector3.ZERO) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font = font()
	l.font_size = size
	l.outline_size = maxi(size / 4, 6)
	l.modulate = color
	l.outline_modulate = Color(0.05, 0.05, 0.1)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.pixel_size = 0.01
	l.position = pos
	return l


static func _instance(mesh: Mesh, color, pos: Vector3, outline: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = color if color is Material else mat(color, outline)
	mi.position = pos
	return mi
