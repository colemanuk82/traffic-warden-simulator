extends AnimatableBody3D
## A cartoon car that follows a lane. Parking cars drive to their spot, wait, then leave.
## Passing cars (spot == null) drive straight through, and hecklers shout at the warden.
## Local +X is the front of the car.

const Util := preload("res://scripts/util.gd")
const World := preload("res://scripts/world.gd")

const DRIVE_SPEED := 11.0
const PASS_SPEED := 13.0
const PARK_DURATION := 1.1
const HECKLE_RANGE := 9.0
const COLORS := [
	Color(0.95, 0.35, 0.35), Color(0.35, 0.6, 0.95), Color(0.45, 0.85, 0.45),
	Color(0.98, 0.7, 0.25), Color(0.75, 0.45, 0.9), Color(0.3, 0.85, 0.85),
	Color(0.95, 0.55, 0.75), Color(0.9, 0.9, 0.9), Color(0.25, 0.25, 0.3),
]
const HECKLE_TEXT := ["GET A PROPER JOB!", "OI! GET A PROPER JOB!", "GET A PROPER JOB, MATE!", "GET A REAL JOB!",
	"JOBSWORTH!", "NOBODY LIKES YOU!", "GET A PROPER JOB, YOU MUPPET!", "GET A PROPER JOB, SUNSHINE!",
	"GOT NOTHING BETTER TO DO?", "MY NAN PARKS WORSE THAN THAT!", "VULTURE!", "WHO HURT YOU?",
	"I PAY YOUR WAGES!", "GOT A QUOTA, HAVE YA?", "HI-VIS, LOW IQ!", "GO CATCH REAL CRIMINALS!",
	"NICE HAT, NAPOLEON!", "GO AND DO SOMETHING USEFUL!", "TYPICAL!", "BOO! BOOOO!"]

var main
var lane
var spot = null  # Dictionary, or null for passing traffic
var heckler := false
var start_parked := false
var kind := ""  # "" random everyday car, or sports, limo, whitevan, getaway, wedding, fan, sleigh, icecream
var boss := {}  # boss drivers: {"id", "name", "hp", ...} (see career.gd)
var expired_chance := 0.35
var splasher := false
var splashed := false
var swerve := 0.0
var swerve_target := 0.0
var clamped := false
var clamp_left := 0.0
var towed := false
var tow_truck: Node3D
var drive_speed := DRIVE_SPEED
var pass_speed := PASS_SPEED
var heckle_lines: Array = HECKLE_TEXT
var s := 0.0
var speed := 0.0
var state := "arriving"  # arriving, parking, parked, unparking, leaving, passing
var park_t := 0.0
var stay_time := 40.0
var meter_time := 0.0
var ticketed := false
var waiting_for_driver := false
var wants_to_leave := false
var leave_timer := -1.0
var blocked_time := 0.0
var ghost_time := 0.0
var honk_cooldown := 0.0
var heckled := false
var pulse := 0.0
var yaw := 0.0
var visual: Node3D
var body_mesh: Node3D
var driver_head: Node3D
var driver_arm: Node3D
var warn_label: Label3D
var warn_sub: Label3D
var honk_label: Label3D
var shout_label: Label3D
var ticket_slip: MeshInstance3D
var clamp_mesh: Node3D
var name_label: Label3D
var car_length := 4.0
var rider: Node3D
var blue_badge := false
var badge_label: Label3D
var bus_wait := 0.0
var bus_stopped_at := -100.0


func _ready() -> void:
	add_to_group("cars")
	sync_to_physics = false
	collision_layer = 1
	collision_mask = 0
	var rng: RandomNumberGenerator = main.rng
	_build_visual(rng)
	stay_time = rng.randf_range(30.0, 60.0)
	if not boss.is_empty():
		stay_time = 999.0
	if spot != null:
		if spot.type == "meter":
			meter_time = 0.0 if rng.randf() < expired_chance else rng.randf_range(10.0, 45.0)
		if start_parked:
			s = spot.s
			state = "parked"
			position = spot.pos
			stay_time = rng.randf_range(15.0, 50.0)
			_show_driver(false)
		else:
			state = "arriving"
			s = 0.0
	else:
		state = "passing"
		s = 0.0
	if state != "parked":
		position = lane.sample(s)
		speed = DRIVE_SPEED
	yaw = World.yaw_of(spot.dir if state == "parked" else lane.tangent(s))
	rotation.y = yaw


func _build_visual(rng: RandomNumberGenerator) -> void:
	var c: Color = COLORS[rng.randi() % COLORS.size()]
	visual = Node3D.new()
	add_child(visual)
	body_mesh = Node3D.new()
	visual.add_child(body_mesh)
	if kind == "":
		var roll := rng.randf()
		if roll < 0.12:
			kind = "sports"
		elif roll < 0.24:
			kind = "4x4"
		elif roll < 0.32:
			kind = "motorbike"
	var width := 1.9
	var wheel_r := 0.36
	var shape := rng.randi() % 3  # 0 hatchback, 1 saloon, 2 van
	var length := 4.0 if shape != 2 else 4.6
	var cab_len := 2.2 if shape == 0 else (2.0 if shape == 1 else 3.4)
	var cab_x := -0.3 if shape != 2 else -0.4
	var body_h := 0.8
	var cab_h := 0.75
	match kind:
		"sports":
			c = [Color(0.95, 0.15, 0.1), Color(1, 0.8, 0.1), Color(0.1, 0.5, 1.0), Color(0.15, 0.9, 0.3)][rng.randi() % 4]
			length = 4.4
			cab_len = 1.6
			cab_x = -0.4
			body_h = 0.55
			cab_h = 0.5
		"limo":
			c = Color(0.06, 0.06, 0.08)
			length = 7.0
			cab_len = 4.6
			cab_x = -0.6
		"whitevan":
			c = Color(0.95, 0.95, 0.95)
			length = 5.2
			cab_len = 4.0
			cab_x = -0.5
			cab_h = 1.1
		"getaway":
			c = Color(0.12, 0.12, 0.14)
			length = 4.4
			cab_len = 2.0
		"wedding":
			c = Color(0.97, 0.97, 1.0)
			length = 5.0
			cab_len = 2.2
		"icecream":
			c = Color(1.0, 0.75, 0.85)
			length = 5.0
			cab_len = 3.6
			cab_h = 1.2
		"sleigh":
			c = Color(0.85, 0.1, 0.1)
			length = 4.4
			cab_len = 1.0
			cab_h = 0.3
		"fan":
			c = [Color(0.85, 0.1, 0.1), Color(0.1, 0.3, 0.9)][rng.randi() % 2]
		"4x4":
			c = [Color(0.2, 0.3, 0.2), Color(0.15, 0.15, 0.18), Color(0.75, 0.75, 0.78), Color(0.5, 0.3, 0.2)][rng.randi() % 4]
			length = 4.6
			cab_len = 3.0
			cab_x = -0.4
			body_h = 1.0
			cab_h = 0.9
			wheel_r = 0.5
			width = 2.0
		"motorbike":
			length = 2.2
			cab_len = 0.6
			cab_x = -0.2
			body_h = 0.45
			cab_h = 0.35
			width = 0.5
			wheel_r = 0.38
		"bus":
			c = Color(0.85, 0.1, 0.1)
			length = 10.0
			cab_len = 9.6
			cab_x = 0.0
			body_h = 1.2
			cab_h = 1.6
			width = 2.3
			wheel_r = 0.5
	var cab_y := 0.65 + body_h / 2.0 + cab_h / 2.0 - 0.01
	var base_y := 0.25 + (wheel_r - 0.36)
	cab_y += base_y - 0.25
	body_mesh.add_child(Util.box(Vector3(length, body_h, width), c, Vector3(0, base_y + body_h / 2.0, 0), true))
	if kind != "motorbike":
		body_mesh.add_child(Util.box(Vector3(cab_len, cab_h, width * 0.9), c.lightened(0.25) if kind not in ["limo", "bus"] else c, Vector3(cab_x, cab_y, 0), true))
	_build_extras(c, length, cab_x, cab_len, cab_y + cab_h / 2.0, width)
	var glass := Color(0.25, 0.4, 0.6) if kind not in ["limo", "getaway"] else Color(0.05, 0.05, 0.08)
	if kind != "motorbike":
		body_mesh.add_child(Util.box(Vector3(0.1, minf(0.5, cab_h * 0.7), width * 0.8), glass, Vector3(cab_x + cab_len / 2.0 + 0.01, cab_y, 0)))
		for wz in [-width * 0.45 - 0.01, width * 0.45 + 0.01]:
			if kind == "bus":
				for i in 6:
					body_mesh.add_child(Util.box(Vector3(1.2, 0.8, 0.05), glass, Vector3(-4.0 + i * 1.6, cab_y + 0.1, wz)))
			else:
				body_mesh.add_child(Util.box(Vector3(cab_len * 0.7, minf(0.45, cab_h * 0.6), 0.05), glass, Vector3(cab_x, cab_y + 0.03, wz)))
	var wheel_xs := [-length * 0.32, length * 0.32]
	var wheel_zs := [-width / 2.0, width / 2.0]
	if kind == "motorbike":
		wheel_xs = [-0.8, 0.8]
		wheel_zs = [0.0]
	for wx in wheel_xs:
		for wz in wheel_zs:
			var wheel := Util.cylinder(wheel_r, 0.28 if kind != "motorbike" else 0.15, Color(0.1, 0.1, 0.1), Vector3(wx, wheel_r, wz), true)
			wheel.rotation_degrees.x = 90.0
			body_mesh.add_child(wheel)
			var hub := Util.cylinder(wheel_r * 0.45, 0.3 if kind != "motorbike" else 0.17, Color(0.8, 0.8, 0.85), Vector3(wx, wheel_r, wz))
			hub.rotation_degrees.x = 90.0
			body_mesh.add_child(hub)
	var lamp_y := base_y + body_h * 0.65
	for lz in ([-width * 0.32, width * 0.32] if kind != "motorbike" else [0.0]):
		body_mesh.add_child(Util.box(Vector3(0.08, 0.22, 0.42), Util.glow(Color(1, 1, 0.75), 1.5), Vector3(length / 2.0, lamp_y, lz)))
		body_mesh.add_child(Util.box(Vector3(0.08, 0.2, 0.4), Util.glow(Color(0.9, 0.1, 0.1), 1.2), Vector3(-length / 2.0, lamp_y, lz)))
	# Driver (UK cars: driver sits on the right, which is local -Z when facing +X)
	driver_head = Node3D.new()
	driver_head.position = Vector3(cab_x + 0.2, cab_y + 0.13, -0.4)
	if kind == "motorbike":
		driver_head.position = Vector3(-0.2, 1.75, 0)
	elif kind == "bus":
		driver_head.position = Vector3(4.2, cab_y, -0.6)
	body_mesh.add_child(driver_head)
	var skin := Color.from_hsv(rng.randf_range(0.04, 0.09), rng.randf_range(0.3, 0.6), rng.randf_range(0.45, 1.0))
	driver_head.add_child(Util.sphere(0.28, skin, Vector3.ZERO, true))
	driver_head.add_child(Util.hemisphere(0.3, Color.from_hsv(rng.randf_range(0.0, 0.12), 0.6, rng.randf_range(0.1, 0.6)), Vector3(0, 0.05, 0)))
	driver_arm = Node3D.new()
	driver_arm.position = Vector3(0.1, -0.15, -0.3)
	driver_arm.visible = false
	driver_head.add_child(driver_arm)
	driver_arm.add_child(Util.capsule(0.09, 0.6, skin, Vector3(0, 0.25, -0.15), true))
	driver_arm.add_child(Util.sphere(0.12, skin, Vector3(0, 0.6, -0.25), true))

	ticket_slip = Util.box(Vector3(0.6, 0.05, 0.8), Color(1, 0.88, 0.1), Vector3(cab_x, cab_y + cab_h / 2.0 + 0.05, 0), true)
	ticket_slip.visible = false
	body_mesh.add_child(ticket_slip)

	if kind == "motorbike":
		# Rider body and helmet, visible while riding
		rider = Node3D.new()
		body_mesh.add_child(rider)
		var jacket := Color.from_hsv(rng.randf(), 0.5, 0.5)
		rider.add_child(Util.capsule(0.28, 0.8, jacket, Vector3(-0.2, 1.25, 0), true))
		rider.add_child(Util.sphere(0.32, c, Vector3(-0.2, 1.8, 0), true))
		rider.add_child(Util.box(Vector3(0.05, 0.15, 0.4), Color(0.1, 0.1, 0.15), Vector3(0.1, 1.8, 0)))
		body_mesh.add_child(Util.box(Vector3(0.1, 0.05, 0.8), Color(0.2, 0.2, 0.22), Vector3(0.55, 1.05, 0)))
		body_mesh.add_child(Util.box(Vector3(0.6, 0.3, 0.4), c.darkened(0.2), Vector3(0.2, 0.9, 0), true))
	if spot != null and spot.type == "disabled" and rng.randf() < 0.5:
		blue_badge = true
	if blue_badge:
		var badge := Util.box(Vector3(0.05, 0.3, 0.3), Color(0.15, 0.4, 0.95), Vector3(cab_x + cab_len / 2.0 - 0.15, cab_y, 0.4))
		body_mesh.add_child(badge)
		badge_label = Util.label3d("BLUE BADGE", 34, Color(0.45, 0.7, 1.0), Vector3(0, 2.7, 0))
		badge_label.visible = false
		add_child(badge_label)

	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(length, 1.8, width)
	col.shape = bs
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
	car_length = length

	warn_label = Util.label3d("!", 110, Color(1, 0.85, 0.1), Vector3(0, 3.4, 0))
	warn_sub = Util.label3d("", 40, Color(1, 0.85, 0.1), Vector3(0, 2.6, 0))
	honk_label = Util.label3d("HONK!", 60, Color(1, 1, 1), Vector3(0, 3.0, 0))
	shout_label = Util.label3d("", 46, Color(1, 0.55, 0.35), Vector3(0, 3.4, 0))
	for l in [warn_label, warn_sub, honk_label, shout_label]:
		l.visible = false
		add_child(l)
	if not boss.is_empty():
		name_label = Util.label3d(boss.name, 44, Color(1, 0.4, 0.9), Vector3(0, 4.3, 0))
		add_child(name_label)
		drive_speed = 13.0 if boss.id != "getaway" else 16.0
	if kind == "bus":
		pass_speed = 9.0
	if kind == "icecream":
		pass_speed = 4.5
		var tune := Util.label3d("~ ding ding ~", 40, Color(1, 0.6, 0.85), Vector3(0, 3.6, 0))
		add_child(tune)
		var tw := create_tween().set_loops()
		tw.tween_property(tune, "position:y", 3.9, 0.4)
		tw.tween_property(tune, "position:y", 3.6, 0.4)


func _build_extras(c: Color, length: float, cab_x: float, cab_len: float, roof_y: float, width: float) -> void:
	match kind:
		"sports":
			body_mesh.add_child(Util.box(Vector3(0.3, 0.06, 1.9), c.darkened(0.3), Vector3(-length / 2.0 + 0.2, 1.25, 0), true))
			for z in [-0.6, 0.6]:
				body_mesh.add_child(Util.box(Vector3(0.08, 0.35, 0.08), c.darkened(0.3), Vector3(-length / 2.0 + 0.2, 1.05, z)))
			body_mesh.add_child(Util.box(Vector3(length * 0.98, 0.04, 0.25), Color.WHITE, Vector3(0, 0.81, 0)))
		"limo":
			for z in [-0.6, 0.6]:
				body_mesh.add_child(Util.cylinder(0.02, 0.5, Color(0.8, 0.8, 0.8), Vector3(length / 2.0 - 0.2, 1.1, z)))
				var flag := Util.box(Vector3(0.35, 0.22, 0.02), Color(0.9, 0.1, 0.15) if z < 0 else Color(0.1, 0.2, 0.8), Vector3(length / 2.0 - 0.02, 1.25, z))
				body_mesh.add_child(flag)
			body_mesh.add_child(Util.label3d("MAYOR 1", 28, Color(1, 0.85, 0.2), Vector3(length / 2.0 + 0.06, 0.6, 0)))
		"whitevan":
			body_mesh.add_child(Util.label3d("BIG DAVE'S\nBUILDING", 34, Color(0.2, 0.3, 0.8), Vector3(-0.5, 1.5, 0.98)))
			body_mesh.add_child(Util.label3d("CLEAN ME", 26, Color(0.4, 0.35, 0.3), Vector3(-length / 2.0 - 0.06, 1.3, 0)))
			for i in 3:
				body_mesh.add_child(Util.cylinder(0.05, 3.0, Color(0.6, 0.6, 0.6), Vector3(-0.5, roof_y + 0.15, -0.5 + i * 0.5)))
				body_mesh.get_child(body_mesh.get_child_count() - 1).rotation.z = PI / 2
		"getaway":
			body_mesh.add_child(Util.box(Vector3(length * 0.98, 0.04, 0.3), Color(0.9, 0.1, 0.1), Vector3(0, 0.81, 0)))
			var bag := Util.sphere(0.35, Color(0.85, 0.75, 0.5), Vector3(-length / 2.0 + 0.6, roof_y + 0.2, 0), true)
			body_mesh.add_child(bag)
			body_mesh.add_child(Util.label3d("$", 40, Color(0.2, 0.6, 0.2), Vector3(-length / 2.0 + 0.6, roof_y + 0.25, 0.37)))
		"wedding":
			for z in [-0.5, 0.5]:
				var ribbon := Util.box(Vector3(length * 0.9, 0.03, 0.12), Color(1, 0.6, 0.75), Vector3(0, 1.06, z))
				ribbon.rotation.y = z * 0.3
				body_mesh.add_child(ribbon)
			body_mesh.add_child(Util.sphere(0.25, Color(1, 0.6, 0.75), Vector3(length / 2.0 - 0.3, 1.1, 0), true))
			body_mesh.add_child(Util.label3d("JUST MARRIED", 30, Color(0.9, 0.3, 0.5), Vector3(-length / 2.0 - 0.06, 0.8, 0)))
			for i in 4:
				var can := Util.cylinder(0.1, 0.25, Color(0.8, 0.8, 0.85), Vector3(-length / 2.0 - 1.2 - i * 0.15, 0.15, -0.5 + i * 0.33))
				can.rotation.z = PI / 2
				body_mesh.add_child(can)
		"icecream":
			var cone := Util.cylinder(0.35, 1.0, Color(0.9, 0.7, 0.4), Vector3(cab_x, roof_y + 0.5, 0), true, 0.05)
			cone.rotation.x = PI
			body_mesh.add_child(cone)
			body_mesh.add_child(Util.sphere(0.45, Color(1, 0.95, 0.9), Vector3(cab_x, roof_y + 1.15, 0), true))
			body_mesh.add_child(Util.box(Vector3(1.8, 0.8, 0.05), Color(0.3, 0.2, 0.15), Vector3(-0.6, 1.4, 0.97)))
			body_mesh.add_child(Util.label3d("99p", 34, Color(1, 0.4, 0.6), Vector3(-0.6, 2.0, 0.99)))
		"sleigh":
			for z in [-0.85, 0.85]:
				body_mesh.add_child(Util.box(Vector3(length + 0.6, 0.08, 0.1), Color(0.95, 0.8, 0.2), Vector3(0.2, 0.1, z)))
			body_mesh.add_child(Util.sphere(0.5, Color(0.5, 0.3, 0.15), Vector3(-length / 2.0 + 0.6, 1.4, 0), true))
			for i in 2:
				var deer := Node3D.new()
				deer.position = Vector3(length / 2.0 + 1.2 + i * 1.6, 0, 0)
				body_mesh.add_child(deer)
				deer.add_child(Util.capsule(0.28, 1.1, Color(0.55, 0.35, 0.2), Vector3(0, 0.9, 0), true))
				deer.get_child(0).rotation.z = PI / 2
				deer.add_child(Util.sphere(0.22, Color(0.55, 0.35, 0.2), Vector3(0.6, 1.3, 0), true))
				deer.add_child(Util.sphere(0.08, Util.glow(Color(1, 0.1, 0.1), 3.0) if i == 1 else Color(0.1, 0.1, 0.1), Vector3(0.82, 1.28, 0)))
				for z in [-0.15, 0.15]:
					for x in [-0.4, 0.4]:
						deer.add_child(Util.cylinder(0.06, 0.6, Color(0.4, 0.25, 0.15), Vector3(x, 0.3, z)))
		"bus":
			body_mesh.add_child(Util.box(Vector3(length * 0.98, 0.25, width + 0.02), Color(1, 0.85, 0.1), Vector3(0, 1.25, 0)))
			body_mesh.add_child(Util.label3d("42  TOWN CENTRE", 40, Color(1, 0.9, 0.3), Vector3(length / 2.0 + 0.06, roof_y - 0.3, 0)))
			body_mesh.add_child(Util.label3d("CITY BUS", 60, Color.WHITE, Vector3(0, roof_y - 0.6, width / 2.0 + 0.05)))
		"4x4":
			body_mesh.add_child(Util.cylinder(0.45, 0.25, Color(0.1, 0.1, 0.1), Vector3(-length / 2.0 - 0.15, 1.2, 0), true))
			body_mesh.get_child(body_mesh.get_child_count() - 1).rotation.z = PI / 2
			for z in [-0.7, 0.7]:
				body_mesh.add_child(Util.box(Vector3(cab_len, 0.08, 0.08), Color(0.2, 0.2, 0.2), Vector3(cab_x, roof_y + 0.08, z)))
			body_mesh.add_child(Util.box(Vector3(0.15, 0.4, 1.8), Color(0.2, 0.2, 0.22), Vector3(length / 2.0 + 0.08, 0.8, 0)))
		"fan":
			var scarf := Util.box(Vector3(0.12, 0.6, 0.35), Color.WHITE, Vector3(cab_x, roof_y - 0.2, 0.9))
			body_mesh.add_child(scarf)
			body_mesh.add_child(Util.cylinder(0.02, 0.8, Color(0.8, 0.8, 0.8), Vector3(cab_x + 0.4, roof_y + 0.4, 0.7)))
			body_mesh.add_child(Util.box(Vector3(0.5, 0.35, 0.02), c.lightened(0.3), Vector3(cab_x + 0.15, roof_y + 0.7, 0.7)))

func _physics_process(delta: float) -> void:
	honk_cooldown = maxf(honk_cooldown - delta, 0.0)
	ghost_time = maxf(ghost_time - delta, 0.0)
	match state:
		"arriving":
			_drive(delta, drive_speed, spot.s)
			if s >= spot.s - 0.01:
				state = "parking"
				park_t = 0.0
				speed = 0.0
		"parking":
			if _bay_blocked():
				_on_blocked(delta, true)
			else:
				park_t = minf(park_t + delta / PARK_DURATION, 1.0)
				var k := smoothstep(0.0, 1.0, park_t)
				position = lane.sample(spot.s).lerp(spot.pos, k)
				visual.rotation.y = sin(k * PI) * 0.3
				if park_t >= 1.0:
					state = "parked"
					visual.rotation.y = 0.0
					_show_driver(false)
					bounce()
		"parked":
			_update_parked(delta)
		"unparking":
			park_t = minf(park_t + delta / PARK_DURATION, 1.0)
			var k := smoothstep(0.0, 1.0, park_t)
			position = spot.pos.lerp(lane.sample(spot.s), k)
			visual.rotation.y = -sin(k * PI) * 0.3
			if park_t >= 1.0:
				state = "leaving"
				visual.rotation.y = 0.0
				if spot.car == self:
					spot.car = null
		"leaving":
			_drive(delta, 9.0 if towed else drive_speed, lane.length)
			if s >= lane.length - 0.1:
				_gone()
		"passing":
			if kind == "bus" and _bus_stop(delta):
				pass
			else:
				_drive(delta, pass_speed, lane.length)
			if heckler:
				_update_heckle()
			if s >= lane.length - 0.1:
				_gone()
	if splasher and not splashed and is_moving():
		_update_splash(delta)
	swerve = lerpf(swerve, swerve_target, 1.0 - exp(-4.0 * delta))
	visual.position.z = swerve
	_update_labels(delta)


func _show_driver(on: bool) -> void:
	driver_head.visible = on
	if rider:
		rider.visible = on


func _gone() -> void:
	if main.has_method("on_car_gone"):
		main.on_car_gone(self)
	queue_free()


func _bus_stop(delta: float) -> bool:
	## Buses pull in at each bus stop on their lane for a few seconds. Returns true while waiting.
	if bus_wait > 0.0:
		bus_wait -= delta
		speed = 0.0
		return true
	for sp in main.world.spots:
		if sp.type != "busstop" or sp.lane != lane:
			continue
		var gap: float = sp.s - s
		if gap > 0.0 and gap < 0.6 and absf(sp.s - bus_stopped_at) > 1.0:
			bus_stopped_at = sp.s
			bus_wait = 3.0
			if sp.car != null and is_instance_valid(sp.car):
				shout("MOVE YOUR CAR!")
				honk()
				main.on_bus_blocked(sp.car)
			return true
	return false


func _update_splash(_delta: float) -> void:
	## Cheeky drivers swerve through roadside puddles when a warden is standing next to one
	swerve_target = 0.0
	var fwd := _forward()
	var side := Vector3(sin(yaw), 0, cos(yaw))  # local +Z
	for p in main.world.road_puddles:
		var rel: Vector3 = p - position
		rel.y = 0.0
		var ahead := rel.dot(fwd)
		var lateral := rel.dot(side)
		if ahead < -1.0 or ahead > 14.0 or absf(lateral) > 3.6:
			continue
		var target = null
		for w in main.all_wardens():
			if w.global_position.distance_to(p) < 4.5:
				target = w
		if target == null:
			continue
		swerve_target = clampf(lateral, -2.4, 2.4)
		if ahead < 1.0:
			splashed = true
			swerve_target = 0.0
			main.on_splash(self, p)
		return


func _drive(delta: float, top: float, target_s: float) -> void:
	var target := top
	if _path_blocked():
		_on_blocked(delta, false)
		target = 0.0
	else:
		blocked_time = 0.0
	# Slow down near the parking spot
	var to_go := target_s - s
	if target_s < lane.length:
		target = minf(target, maxf(to_go * 2.5, 2.0))
	speed = move_toward(speed, target, 25.0 * delta)
	s = minf(s + speed * delta, target_s)
	position = lane.sample(s)
	var want := World.yaw_of(lane.tangent(s + 1.0))
	yaw = lerp_angle(yaw, want, 1.0 - exp(-8.0 * delta))
	rotation.y = yaw


func _forward() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))


func _in_cone(from: Vector3, fwd: Vector3, p: Vector3, reach: float, width: float) -> bool:
	var rel := p - from
	rel.y = 0.0
	var ahead := rel.dot(fwd)
	if ahead <= 0.0 or ahead > reach:
		return false
	return (rel - fwd * ahead).length() < width


func _path_blocked() -> bool:
	var fwd := _forward()
	for w in main.all_wardens():
		if _in_cone(position, fwd, w.global_position, 4.4, 1.6):
			return true
	if ghost_time > 0.0:
		return false
	for c in get_tree().get_nodes_in_group("cars"):
		if c == self or c.state == "parked":
			continue
		if _in_cone(position, fwd, c.position, 5.5, 1.4):
			# Two cars blocking each other at a junction: the older one goes first
			if c.is_moving() and _in_cone(c.position, c._forward(), position, 5.5, 1.4):
				if get_instance_id() < c.get_instance_id():
					continue
			return true
	for d in get_tree().get_nodes_in_group("drivers"):
		if _in_cone(position, fwd, d.global_position, 3.5, 1.4):
			return true
	return false


func is_moving() -> bool:
	return state in ["arriving", "leaving", "passing"]


func _bay_blocked() -> bool:
	for wd in main.all_wardens():
		var rel: Vector3 = wd.global_position - spot.pos
		if absf(rel.dot(spot.dir)) < 2.6 and absf(rel.dot(spot.normal)) < 1.6:
			return true
	return false


func _unpark_blocked() -> bool:
	var lp: Vector3 = lane.sample(spot.s)
	for wd in main.all_wardens():
		var rel: Vector3 = wd.global_position - spot.pos
		if absf(rel.dot(spot.dir)) < 2.6 and rel.dot(spot.normal) > -2.6 and rel.dot(spot.normal) < 1.2:
			return true
	for c in get_tree().get_nodes_in_group("cars"):
		if c == self or not c.is_moving():
			continue
		if c.lane == lane:
			var gap: float = spot.s - c.s
			if gap > -4.5 and gap < 11.0:
				return true
		elif c.position.distance_to(lp) < 5.0:
			return true
	return false


func _update_parked(delta: float) -> void:
	if spot.type == "meter" and meter_time > 0.0:
		meter_time = maxf(meter_time - delta, 0.0)
	if clamped:
		clamp_left -= delta
		if clamp_left > 0.0:
			return
		clamped = false
		if clamp_mesh:
			clamp_mesh.queue_free()
		wants_to_leave = true
	if waiting_for_driver:
		return
	if leave_timer > 0.0:
		leave_timer -= delta
		if leave_timer <= 0.0:
			wants_to_leave = true
	else:
		stay_time -= delta
		if stay_time <= 0.0:
			wants_to_leave = true
	if wants_to_leave and not _unpark_blocked():
		state = "unparking"
		park_t = 0.0
		_show_driver(true)
		speed = 0.0


func _update_labels(delta: float) -> void:
	pulse += delta
	if name_label:
		name_label.scale = Vector3.ONE * (1.0 + sin(pulse * 5.0) * 0.08)
	var w = main.nearest_warden(global_position)
	if w == null:
		return
	var near: bool = w.global_position.distance_to(global_position) < 8.0
	var show_warn := near and is_illegal() and not ticketed
	if badge_label:
		badge_label.visible = near and is_parked() and not is_illegal()
	warn_label.visible = show_warn
	warn_sub.visible = show_warn
	if show_warn:
		warn_sub.text = offence_name()
		warn_label.scale = Vector3.ONE * (1.0 + sin(pulse * 8.0) * 0.15)


func _update_heckle() -> void:
	var w = main.nearest_warden(global_position)
	if heckled or w == null or main.state != "playing":
		return
	var d: float = w.global_position.distance_to(global_position)
	if d < HECKLE_RANGE:
		heckled = true
		var i: int = main.rng.randi() % heckle_lines.size()
		shout(heckle_lines[i])
		driver_arm.visible = true
		var tw := create_tween().set_loops(5)
		tw.tween_property(driver_arm, "rotation:x", 0.6, 0.12)
		tw.tween_property(driver_arm, "rotation:x", -0.6, 0.12)
		Audio.voice("heckle_%d" % i if heckle_lines == HECKLE_TEXT else "heckle", main.rng.randf_range(0.92, 1.1))
		main.on_heckled(self, w)


func shout(text: String) -> void:
	shout_label.text = text
	shout_label.visible = true
	shout_label.scale = Vector3.ONE * 1.5
	var tw := create_tween()
	tw.tween_property(shout_label, "scale", Vector3.ONE, 0.15)
	tw.tween_interval(1.8)
	tw.tween_callback(func() -> void: shout_label.visible = false)


func _on_blocked(delta: float, _parking: bool) -> void:
	blocked_time += delta
	var w = main.nearest_warden(global_position)
	var near: bool = w != null and w.global_position.distance_to(global_position) < 6.0
	if near and blocked_time > 0.5 and honk_cooldown <= 0.0:
		honk()
	# Stuck behind other cars for ages (a junction jam): drive through them for a moment
	if blocked_time > 4.0 and not near:
		ghost_time = 1.5
		blocked_time = 0.0


func honk() -> void:
	honk_cooldown = 2.5
	honk_label.visible = true
	honk_label.scale = Vector3.ONE * 1.5
	var tw := create_tween()
	tw.tween_property(honk_label, "scale", Vector3.ONE, 0.15)
	tw.tween_interval(0.6)
	tw.tween_callback(func() -> void: honk_label.visible = false)
	bounce()
	if main.nearest_warden(global_position) != null:
		Audio.sfx("honk", main.rng.randf_range(0.85, 1.2), 0.7)


func bounce() -> void:
	var tw := create_tween()
	tw.tween_property(body_mesh, "scale", Vector3(1.1, 0.8, 1.1), 0.08)
	tw.tween_property(body_mesh, "scale", Vector3(0.95, 1.12, 0.95), 0.1)
	tw.tween_property(body_mesh, "scale", Vector3.ONE, 0.15)


func punched(from: Vector3) -> void:
	## A punch to the bodywork: a wobble, a honk and a dented ego
	var away := global_position - from
	away.y = 0.0
	var tw := create_tween()
	tw.tween_property(body_mesh, "rotation:x", 0.25 * signf(away.dot(global_transform.basis.z)), 0.08)
	tw.tween_property(body_mesh, "rotation:x", -0.12, 0.12)
	tw.tween_property(body_mesh, "rotation:x", 0.0, 0.15)
	honk_cooldown = 0.0
	honk()


func give_ticket() -> void:
	ticketed = true
	ticket_slip.visible = true
	bounce()


func clamp_wheel(seconds: float) -> void:
	clamped = true
	clamp_left = seconds
	ticketed = true
	clamp_mesh = Node3D.new()
	add_child(clamp_mesh)
	var yellow := Util.mat(Color(1, 0.85, 0.05), true)
	for z in [-1.02, 1.02]:
		var ring := Util.torus(0.25, 0.42, yellow, Vector3(car_length * 0.32, 0.36, z))
		ring.rotation.x = PI / 2
		clamp_mesh.add_child(ring)
		clamp_mesh.add_child(Util.box(Vector3(0.5, 0.2, 0.12), yellow, Vector3(car_length * 0.32, 0.36, z * 1.06)))
	var tw := create_tween()
	clamp_mesh.scale = Vector3.ONE * 1.5
	tw.tween_property(clamp_mesh, "scale", Vector3.ONE, 0.2)
	bounce()


## A tow truck backs up, lifts the car's nose and drags it off down the road.
func tow_away() -> void:
	towed = true
	ticketed = true
	waiting_for_driver = false
	clamped = false
	if clamp_mesh:
		clamp_mesh.queue_free()
	ghost_time = 999.0
	tow_truck = Node3D.new()
	tow_truck.position = Vector3(car_length / 2.0 + 2.8, 0, 0)
	add_child(tow_truck)
	var orange := Util.mat(Color(1, 0.55, 0.1), true)
	tow_truck.add_child(Util.box(Vector3(4.2, 0.9, 2.0), orange, Vector3(0.4, 0.75, 0)))
	tow_truck.add_child(Util.box(Vector3(1.7, 0.9, 1.9), orange, Vector3(1.3, 1.6, 0)))
	tow_truck.add_child(Util.box(Vector3(0.1, 0.5, 1.6), Color(0.25, 0.4, 0.6), Vector3(2.16, 1.65, 0)))
	tow_truck.add_child(Util.box(Vector3(0.4, 0.2, 1.2), Util.glow(Color(1, 0.6, 0.0), 3.0), Vector3(1.3, 2.15, 0)))
	var boom := Util.box(Vector3(2.4, 0.15, 0.15), Color(0.3, 0.3, 0.3), Vector3(-1.4, 1.3, 0), true)
	boom.rotation.z = -0.35
	tow_truck.add_child(boom)
	for wx in [-1.2, 1.4]:
		for wz in [-1.0, 1.0]:
			var wheel := Util.cylinder(0.42, 0.3, Color(0.1, 0.1, 0.1), Vector3(wx, 0.42, wz), true)
			wheel.rotation_degrees.x = 90.0
			tow_truck.add_child(wheel)
	tow_truck.add_child(Util.label3d("TOWED!", 56, Color(1, 0.6, 0.1), Vector3(0, 3.4, 0)))
	tow_truck.scale = Vector3(1, 0.01, 1)
	var tw := create_tween()
	tw.tween_property(tow_truck, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK)
	tw.tween_property(body_mesh, "rotation:z", 0.22, 0.5)
	tw.parallel().tween_property(body_mesh, "position:y", 0.45, 0.5)
	tw.tween_callback(func() -> void:
		if state == "parked":
			state = "unparking"
			park_t = 0.0
			speed = 0.0)


## Boss drivers drive off and come back somewhere else
func relocate() -> void:
	wants_to_leave = true
	leave_timer = -1.0
	stay_time = 0.0


func leave_after(seconds: float) -> void:
	leave_timer = seconds


func driver_returned() -> void:
	waiting_for_driver = false
	leave_after(0.8)
	bounce()


func is_parked() -> bool:
	return state == "parked"


func is_illegal() -> bool:
	if spot == null or not is_parked():
		return false
	if not boss.is_empty() or kind in ["wedding", "sleigh"]:
		return true
	match spot.type:
		"yellow", "busstop":
			return true
		"disabled":
			return not blue_badge
	return meter_time <= 0.0


func offence_name() -> String:
	if not boss.is_empty():
		return "BOSS: %d TICKET%s LEFT" % [int(boss.hp), "S" if int(boss.hp) > 1 else ""]
	if kind == "wedding":
		return "WEDDING CAR +BONUS"
	if kind == "sleigh":
		return "SLEIGH ON THE PAVEMENT"
	if spot.type == "busstop":
		return "PARKED AT A BUS STOP"
	if spot.type == "disabled":
		return "NO BLUE BADGE"
	return "DOUBLE YELLOWS" if spot.type == "yellow" else "METER EXPIRED"
