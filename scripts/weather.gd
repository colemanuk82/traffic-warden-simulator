extends Node3D
## Weather for a shift: rain, storm (rain + lightning), snow, blizzard, fog or wind.
## Follows a target so the particles always fall around the camera's view.

const Util := preload("res://scripts/util.gd")

const INFO := {
	"clear": {"name": "Sunny", "tip": ""},
	"rain": {"name": "Rain", "tip": "Slippery pavements!"},
	"storm": {"name": "Thunderstorm", "tip": "Slippery, and very loud"},
	"snow": {"name": "Snow", "tip": "Wading through snow is slow"},
	"blizzard": {"name": "Blizzard", "tip": "Can't see a thing!"},
	"fog": {"name": "Pea-souper Fog", "tip": "Keep your eyes peeled"},
	"wind": {"name": "Blustery", "tip": "Hold on to your hat"},
}

var kind := "clear"
var main
var target: Node3D
var world
var flash_timer := 8.0
var particles: Array[CPUParticles3D] = []
var base_sun := 1.0
var base_ambient := 0.65


func setup(weather: String, the_world, follow: Node3D) -> void:
	kind = weather
	world = the_world
	target = follow
	var env: Environment = world.env
	var sun: DirectionalLight3D = world.sun
	match kind:
		"rain", "storm":
			sun.light_energy *= 0.55
			env.background_color = env.background_color.darkened(0.45)
			env.ambient_light_energy = 0.5
			_rain(1800 if kind == "rain" else 2600, 4.0 if kind == "storm" else 0.0)
			_puddles()
		"snow":
			_snow(1400, 0.6)
		"blizzard":
			_snow(3000, 7.0)
			_fog(Color(0.85, 0.88, 0.95), 0.02)
		"fog":
			_fog(Color(0.75, 0.77, 0.8), 0.016)
			sun.light_energy *= 0.7
		"wind":
			_leaves()
	base_sun = sun.light_energy
	base_ambient = env.ambient_light_energy


func speed_mult() -> float:
	return {"snow": 0.9, "blizzard": 0.85}.get(kind, 1.0)


func grip() -> float:
	return {"rain": 0.35, "storm": 0.3}.get(kind, 1.0)


func ambience() -> String:
	return {"rain": "rain", "storm": "rain", "blizzard": "wind", "snow": "wind", "wind": "wind"}.get(kind, "")


func _process(delta: float) -> void:
	if target:
		global_position = target.global_position
	if kind == "storm":
		flash_timer -= delta
		if flash_timer <= 0.0:
			flash_timer = randf_range(5.0, 10.0)
			_lightning()


func _lightning() -> void:
	## A proper cartoon bolt: a warning glow on the ground, then a jagged bolt, a white flash,
	## a scorch mark and sparks. Wardens standing on the spot get zapped.
	var env: Environment = world.env
	var sun: DirectionalLight3D = world.sun
	var spot := _strike_point()
	var warn := Util.cylinder(2.2, 0.03, Util.glow(Color(0.6, 0.8, 1.0), 2.0), spot + Vector3(0, 0.1, 0))
	world.add_child(warn)
	var wt := create_tween().set_loops(4)
	wt.tween_property(warn, "scale", Vector3(1.2, 1, 1.2), 0.11)
	wt.tween_property(warn, "scale", Vector3(0.8, 1, 0.8), 0.11)
	await get_tree().create_timer(0.9).timeout
	if not is_instance_valid(warn):
		return
	warn.queue_free()
	var bolt := _bolt(spot)
	world.add_child(bolt)
	var tw := create_tween()
	tw.tween_property(env, "ambient_light_energy", 3.5, 0.04)
	tw.parallel().tween_property(sun, "light_energy", base_sun * 5.0, 0.04)
	tw.tween_property(env, "ambient_light_energy", base_ambient, 0.12)
	tw.parallel().tween_property(sun, "light_energy", base_sun, 0.12)
	tw.tween_property(env, "ambient_light_energy", 2.2, 0.05)
	tw.tween_property(env, "ambient_light_energy", base_ambient, 0.3)
	get_tree().create_timer(0.25).timeout.connect(bolt.queue_free)
	if main and main.hud:
		main.hud.flash()
	Audio.sfx("zap", randf_range(0.9, 1.1))
	Audio.sfx("thunder", randf_range(0.85, 1.0))
	var scorch := Util.cylinder(1.4, 0.02, Color(0.08, 0.07, 0.07), spot + Vector3(0, 0.09, 0))
	world.add_child(scorch)
	var st := create_tween()
	st.tween_interval(6.0)
	st.tween_property(scorch, "scale", Vector3(0.01, 1, 0.01), 2.0)
	st.tween_callback(scorch.queue_free)
	_sparks(spot)
	if main:
		main.on_lightning(spot)


func _strike_point() -> Vector3:
	## Usually near a warden, to keep you on your toes
	if target and randf() < 0.55:
		var off := Vector3(randf_range(-1.0, 1.0), 0, randf_range(-1.0, 1.0)).normalized() * randf_range(2.5, 8.0)
		var sp: Vector3 = world.clamp_move(target.global_position, target.global_position + off)
		sp.y = world.height_at(sp)
		return sp
	var r: Rect2 = world.walk_rects[randi() % world.walk_rects.size()]
	var p := Vector3(randf_range(r.position.x, r.end.x), 0, randf_range(r.position.y, r.end.y))
	p.y = world.height_at(p)
	return p


func _bolt(spot: Vector3) -> Node3D:
	var root := Node3D.new()
	var mat := Util.glow(Color(0.85, 0.92, 1.0), 8.0)
	var p := spot + Vector3(randf_range(-4, 4), 40, randf_range(-4, 4))
	var steps := 9
	for i in steps:
		var t := float(i + 1) / steps
		var next := p.lerp(spot, 1.0 / (steps - i))
		if i < steps - 1:
			next += Vector3(randf_range(-1.6, 1.6), 0, randf_range(-1.6, 1.6))
		for width in [0.35, 0.12]:
			var seg := MeshInstance3D.new()
			var bm := BoxMesh.new()
			var len := p.distance_to(next)
			bm.size = Vector3(width, len, width)
			seg.mesh = bm
			seg.material_override = mat if width < 0.2 else Util.glow(Color(0.5, 0.65, 1.0), 4.0)
			root.add_child(seg)
			seg.position = (p + next) / 2.0
			var up := (next - p).normalized()
			seg.basis = _basis_y_along(up)
		# The odd fork
		if randf() < 0.3 and t < 0.8:
			var fork_end := next + Vector3(randf_range(-4, 4), -randf_range(3, 6), randf_range(-4, 4))
			var f := MeshInstance3D.new()
			var fm := BoxMesh.new()
			fm.size = Vector3(0.1, next.distance_to(fork_end), 0.1)
			f.mesh = fm
			f.material_override = mat
			root.add_child(f)
			f.position = (next + fork_end) / 2.0
			f.basis = _basis_y_along((fork_end - next).normalized())
		p = next
	var light := OmniLight3D.new()
	light.light_color = Color(0.8, 0.9, 1.0)
	light.light_energy = 12.0
	light.omni_range = 25.0
	light.position = spot + Vector3(0, 3, 0)
	root.add_child(light)
	return root


static func _basis_y_along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var x := y.cross(Vector3.FORWARD)
	if x.length() < 0.01:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _sparks(spot: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 50
	p.lifetime = 0.8
	p.explosiveness = 1.0
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.06, 0.06, 0.3)
	p.mesh = mesh
	p.material_override = Util.glow(Color(1, 0.95, 0.6), 5.0)
	p.direction = Vector3(0, 1, 0)
	p.spread = 80.0
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 12.0
	p.gravity = Vector3(0, -25, 0)
	p.particle_flag_align_y = true
	p.position = spot + Vector3(0, 0.2, 0)
	world.add_child(p)
	get_tree().create_timer(1.5).timeout.connect(p.queue_free)


func _make(amount: int, mesh: Mesh, color: Color, lifetime: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = false
	p.mesh = mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	p.material_override = m
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(26, 0.5, 20)
	p.position = Vector3(0, 16, -2)
	p.preprocess = lifetime
	add_child(p)
	particles.append(p)
	return p


func _rain(amount: int, wind: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.04, 0.9, 0.04)
	var p := _make(amount, mesh, Color(0.75, 0.85, 1.0, 0.55), 1.0)
	p.direction = Vector3(0.15 * wind, -1, 0)
	p.spread = 3.0
	p.gravity = Vector3(0, -20, 0)
	p.initial_velocity_min = 18.0
	p.initial_velocity_max = 22.0
	p.particle_flag_align_y = true


func _snow(amount: int, wind: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	mesh.radial_segments = 6
	mesh.rings = 3
	var p := _make(amount, mesh, Color(1, 1, 1, 0.95), 5.0)
	p.direction = Vector3(wind * 0.2, -1, 0)
	p.spread = 25.0
	p.gravity = Vector3(wind, -1.5, 0)
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.0
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.6


func _leaves() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.25, 0.03, 0.18)
	var p := _make(140, mesh, Color(0.85, 0.55, 0.2, 1.0), 3.5)
	p.position = Vector3(-26, 3, -2)
	p.emission_box_extents = Vector3(2, 3, 20)
	p.direction = Vector3(1, 0.1, 0)
	p.spread = 15.0
	p.gravity = Vector3(2, -0.6, 0)
	p.initial_velocity_min = 12.0
	p.initial_velocity_max = 18.0
	p.angular_velocity_min = -400.0
	p.angular_velocity_max = 400.0
	p.color = Color(1, 1, 1)


func _fog(color: Color, density: float) -> void:
	var env: Environment = world.env
	env.fog_enabled = true
	env.fog_light_color = color
	env.fog_density = density
	env.fog_sky_affect = 0.0
	env.background_color = color


func _puddles() -> void:
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.45, 0.55, 0.72)
	water.roughness = 0.05
	water.metallic = 0.6
	for i in 40:
		var r: Rect2 = world.walk_rects[randi() % world.walk_rects.size()]
		var p := Vector3(randf_range(r.position.x, r.end.x), 0.08, randf_range(r.position.y, r.end.y))
		p.y += world.height_at(p)
		var puddle := Util.cylinder(randf_range(0.6, 1.4), 0.02, water, p)
		puddle.scale.z = randf_range(0.5, 1.0)
		world.add_child(puddle)
