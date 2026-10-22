extends CharacterBody3D
## Street characters who wander the pavements and heckle the warden: a staggering drunk who wants
## to give you a hug, a dodgy geezer flogging knock-off watches, and a lad on a stag do.
## Whistle to shoo them away. Punching them knocks them over, but earns nothing.
## Halloween brings trick-or-treaters (kids in costumes: a sweet gets you a treat, no sweet gets you
## tricked) and Christmas Eve brings carol singers and a cheeky elf. Kids and elves are too quick to punch.

const Util := preload("res://scripts/util.gd")

const KINDS := {
	"drunk": {"name": "Tipsy Terry", "speed": 1.6, "voice": "ped_drunk",
		"lines": ["Oi! Shiny jacket!", "I LOVE YOU, MATE! *hic*", "Ticket ME! Go on!", "Where's me car? *hic*",
			"You're me best mate, you!", "Get a proper job! *hic*", "Is it Tuesday?"]},
	"geezer": {"name": "Dodgy Dave", "speed": 2.4, "voice": "ped_geezer",
		"lines": ["Wanna buy a watch?", "Psst! Genuine Rolex, a tenner!", "Fell off the back of a lorry!",
			"Jobsworth!", "I know your mum!", "Nice hat. Shame about the face."]},
	"stag": {"name": "Stag Do Steve", "speed": 2.0, "voice": "ped_stag",
		"lines": ["WAHEY!", "It's my stag do!", "Give us a ticket for the album!", "LADS LADS LADS!",
			"Get a proper job! WAHEY!", "Dance with me, warden!"]},
	"caroller": {"name": "Carol Singer", "speed": 1.8, "voice": "ped_caroller",
		"lines": ["Fa la la la la!", "Deck the halls!", "Sing with us, warden!", "Merry Christmas!", "Jingle bells!"]},
	"elf": {"name": "Cheeky Elf", "speed": 3.0, "voice": "ped_elf",
		"lines": ["You're on the naughty list!", "Jingle jingle!", "Santa's watching!", "Ho ho... no!"]},
	"ghost": {"name": "Ghost", "speed": 2.6, "voice": "kid_tot", "kid": true, "lines": ["Trick or treat!", "WOOOOO!"]},
	"witch": {"name": "Little Witch", "speed": 2.6, "voice": "kid_tot", "kid": true, "lines": ["Trick or treat!", "Hee hee hee!"]},
	"pumpkin": {"name": "Pumpkin Head", "speed": 2.4, "voice": "kid_tot", "kid": true, "lines": ["Trick or treat!", "Sweets please!"]},
	"skeleton": {"name": "Skeleton", "speed": 2.8, "voice": "kid_tot", "kid": true, "lines": ["Trick or treat!", "Rattle rattle!"]},
	"vampire": {"name": "Vampire", "speed": 2.6, "voice": "kid_tot", "kid": true, "lines": ["Trick or treat!", "I vant your sweets!"]},
}
const KID_THANKS := ["THANK YOU!", "HAPPY HALLOWEEN!", "YAY, SWEETS!"]
const KID_TRICK := ["NO SWEETS? TRICK!", "GOTCHA!", "TRICKED YA!"]

var main
var kind := "drunk"
var info: Dictionary
var target := Vector3.ZERO
var state := "wander"  # wander, pester, knocked, flee
var heckle_cd := 2.0
var pester_left := 0.0
var knock_left := 0.0
var flee_left := 0.0
var walk_t := 0.0
var sway_t := 0.0
var visual: Node3D
var shout_label: Label3D
var stars_label: Label3D
var kid := false


func _ready() -> void:
	add_to_group("pedestrians")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = 8
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.6
	shape.shape = cap
	shape.position = Vector3(0, 0.8, 0)
	add_child(shape)
	info = KINDS[kind]
	kid = info.get("kid", false)
	sway_t = randf() * TAU
	if kid:
		heckle_cd = randf_range(1.0, 6.0)
	_build()
	target = main.world.random_walk_point(main.rng, global_position, 6.0, true)


func _build() -> void:
	visual = Node3D.new()
	add_child(visual)
	var skin := Color.from_hsv(randf_range(0.04, 0.09), randf_range(0.3, 0.55), randf_range(0.5, 1.0))
	var top := Color.from_hsv(randf(), 0.5, 0.7)
	var legs := Color(0.2, 0.25, 0.4)
	match kind:
		"drunk":
			top = Color(0.55, 0.4, 0.3)
		"geezer":
			top = Color(0.25, 0.25, 0.28)
			legs = Color(0.3, 0.3, 0.35)
		"stag":
			top = Color(1.0, 0.45, 0.75)
		"caroller":
			top = Color(0.75, 0.1, 0.15)
		"elf":
			top = Color(0.15, 0.6, 0.25)
			legs = Color(0.9, 0.15, 0.15)
		"ghost":
			_build_ghost()
			return
		"witch", "vampire":
			top = Color(0.12, 0.08, 0.16)
			legs = Color(0.1, 0.1, 0.12)
		"pumpkin":
			top = Color(0.15, 0.45, 0.15)
		"skeleton":
			top = Color(0.08, 0.08, 0.08)
			legs = Color(0.08, 0.08, 0.08)
	if kid or kind == "elf":
		visual.scale = Vector3.ONE * 0.72
	for x in [-0.14, 0.14]:
		visual.add_child(Util.box(Vector3(0.18, 0.5, 0.18), Util.mat(legs, true), Vector3(x, 0.25, 0)))
	visual.add_child(Util.capsule(0.34, 0.9, Util.mat(top, true), Vector3(0, 0.86, 0)))
	var head := Util.sphere(0.38, Util.mat(skin, true), Vector3(0, 1.55, 0))
	visual.add_child(head)
	for x in [-0.13, 0.13]:
		visual.add_child(Util.sphere(0.05, Util.mat(Color(0.05, 0.05, 0.05)), Vector3(x, 1.62, 0.34)))
	match kind:
		"drunk":
			visual.add_child(Util.sphere(0.11, Util.mat(Color(0.95, 0.2, 0.2), true), Vector3(0, 1.52, 0.38)))
			visual.add_child(Util.box(Vector3(0.6, 0.1, 0.06), Util.mat(Color(0.15, 0.4, 0.15)), Vector3(0, 1.8, 0)))
			visual.add_child(Util.label3d("*hic*", 30, Color(0.8, 0.9, 1.0), Vector3(0.5, 2.2, 0)))
			# Kebab in hand
			visual.add_child(Util.cylinder(0.08, 0.35, Util.mat(Color(0.85, 0.65, 0.35), true), Vector3(0.45, 1.0, 0.15)))
		"geezer":
			var hood := Util.hemisphere(0.43, Util.mat(top.darkened(0.2), true), Vector3(0, 1.6, -0.05))
			visual.add_child(hood)
			# A coat lined with knock-off watches
			for i in 4:
				visual.add_child(Util.torus(0.04, 0.07, Util.metal(Color(1, 0.8, 0.2), false), Vector3(-0.15 + i * 0.1, 0.9, 0.35)))
			visual.add_child(Util.box(Vector3(0.5, 0.08, 0.06), Util.mat(Color(0.05, 0.05, 0.05)), Vector3(0, 1.66, 0.36)))
		"stag":
			visual.add_child(Util.label3d("STAG", 30, Color.WHITE, Vector3(0, 1.0, 0.36)))
			for x in [-0.25, 0.25]:
				var antler := Util.cylinder(0.04, 0.5, Util.mat(Color(0.5, 0.35, 0.2)), Vector3(x, 2.05, 0))
				antler.rotation.z = -x * 2.0
				visual.add_child(antler)
			var tutu := Util.cylinder(0.55, 0.15, Util.mat(Color(1, 0.7, 0.9), true), Vector3(0, 0.55, 0), false, 0.35)
			visual.add_child(tutu)
		"caroller":
			# Bobble hat, scarf and a song book
			visual.add_child(Util.hemisphere(0.4, Util.mat(Color(0.95, 0.95, 0.95), true), Vector3(0, 1.66, -0.02)))
			visual.add_child(Util.sphere(0.12, Util.mat(Color(0.9, 0.15, 0.15)), Vector3(0, 2.08, 0)))
			visual.add_child(Util.box(Vector3(0.6, 0.14, 0.5), Util.mat(Color(0.15, 0.55, 0.2)), Vector3(0, 1.25, 0)))
			visual.add_child(Util.box(Vector3(0.4, 0.3, 0.06), Util.mat(Color(0.95, 0.9, 0.7), true), Vector3(0, 1.1, 0.4)))
			visual.add_child(Util.label3d("~ fa la la ~", 30, Color(1, 0.9, 0.5), Vector3(0.5, 2.3, 0)))
		"elf":
			var hat := Util.cylinder(0.35, 0.8, Util.mat(Color(0.15, 0.6, 0.25), true), Vector3(0, 2.05, 0), false, 0.02)
			visual.add_child(hat)
			visual.add_child(Util.sphere(0.1, Util.glow(Color(1, 0.9, 0.3), 2.0), Vector3(0, 2.48, 0)))
			for x in [-0.42, 0.42]:
				var ear := Util.cylinder(0.08, 0.3, Util.mat(skin), Vector3(x, 1.62, 0), false, 0.0)
				ear.rotation.z = -signf(x) * 1.2
				visual.add_child(ear)
			visual.add_child(Util.box(Vector3(0.7, 0.1, 0.4), Util.mat(Color(0.1, 0.1, 0.1)), Vector3(0, 0.75, 0)))
		"witch":
			visual.add_child(Util.cylinder(0.6, 0.06, Util.mat(Color(0.1, 0.05, 0.15), true), Vector3(0, 1.85, 0)))
			visual.add_child(Util.cylinder(0.32, 0.9, Util.mat(Color(0.1, 0.05, 0.15), true), Vector3(0, 2.3, 0), false, 0.02))
			visual.add_child(Util.box(Vector3(0.66, 0.08, 0.66), Util.mat(Color(0.5, 0.2, 0.7)), Vector3(0, 1.92, 0)))
			var broom := Util.cylinder(0.04, 1.4, Util.mat(Color(0.55, 0.4, 0.2)), Vector3(0.42, 0.9, 0.1))
			broom.rotation.z = 0.3
			visual.add_child(broom)
			visual.add_child(Util.cylinder(0.16, 0.35, Util.mat(Color(0.85, 0.7, 0.3)), Vector3(0.6, 0.25, 0.1), false, 0.04))
		"vampire":
			var cape := Util.box(Vector3(0.8, 1.1, 0.08), Util.mat(Color(0.05, 0.05, 0.07), true), Vector3(0, 0.95, -0.35))
			visual.add_child(cape)
			visual.add_child(Util.box(Vector3(0.8, 0.35, 0.08), Util.mat(Color(0.75, 0.05, 0.1)), Vector3(0, 1.4, -0.3)))
			visual.add_child(Util.hemisphere(0.4, Util.mat(Color(0.05, 0.05, 0.07), true), Vector3(0, 1.66, -0.04)))
			for x in [-0.07, 0.07]:
				visual.add_child(Util.box(Vector3(0.04, 0.09, 0.04), Util.mat(Color.WHITE), Vector3(x, 1.43, 0.36)))
		"pumpkin":
			head.material_override = Util.mat(Color(1, 0.5, 0.05), true)
			head.scale = Vector3(1.25, 1.05, 1.25)
			visual.add_child(Util.cylinder(0.06, 0.2, Util.mat(Color(0.2, 0.5, 0.15)), Vector3(0, 2.0, 0)))
			for x in [-0.15, 0.15]:
				visual.add_child(Util.box(Vector3(0.12, 0.12, 0.05), Util.glow(Color(1, 0.85, 0.2), 2.5), Vector3(x, 1.62, 0.46)))
			visual.add_child(Util.box(Vector3(0.36, 0.08, 0.05), Util.glow(Color(1, 0.85, 0.2), 2.5), Vector3(0, 1.42, 0.45)))
		"skeleton":
			for i in 4:
				visual.add_child(Util.box(Vector3(0.55, 0.06, 0.05), Util.mat(Color(0.95, 0.95, 0.9)), Vector3(0, 0.7 + i * 0.16, 0.34)))
			visual.add_child(Util.box(Vector3(0.06, 0.6, 0.05), Util.mat(Color(0.95, 0.95, 0.9)), Vector3(0, 0.9, 0.35)))
			head.material_override = Util.mat(Color(0.95, 0.95, 0.9), true)
			for x in [-0.14, 0.14]:
				visual.add_child(Util.sphere(0.09, Util.mat(Color(0.05, 0.05, 0.05)), Vector3(x, 1.6, 0.33)))
	if kid:
		_add_bucket()
	shout_label = Util.label3d("", 40, Color(0.75, 1.0, 0.6), Vector3(0, 2.7, 0))
	add_child(shout_label)
	stars_label = Util.label3d("@ * @", 56, Color(1, 0.9, 0.2), Vector3(0, 2.2, 0))
	stars_label.visible = false
	add_child(stars_label)


func _build_ghost() -> void:
	## A kid under a white sheet with eye holes
	visual.scale = Vector3.ONE * 0.72
	var sheet := Util.capsule(0.45, 1.9, Util.mat(Color(0.97, 0.97, 1.0), true), Vector3(0, 0.95, 0))
	visual.add_child(sheet)
	visual.add_child(Util.cylinder(0.52, 0.2, Util.mat(Color(0.97, 0.97, 1.0)), Vector3(0, 0.1, 0), false, 0.45))
	for x in [-0.14, 0.14]:
		visual.add_child(Util.sphere(0.08, Util.mat(Color(0.05, 0.05, 0.05)), Vector3(x, 1.45, 0.4)))
	_add_bucket()
	shout_label = Util.label3d("", 40, Color(1, 0.7, 0.2), Vector3(0, 2.4, 0))
	add_child(shout_label)
	stars_label = Util.label3d("@ * @", 56, Color(1, 0.9, 0.2), Vector3(0, 2.0, 0))
	stars_label.visible = false
	add_child(stars_label)


func _add_bucket() -> void:
	var bucket := Util.sphere(0.24, Util.mat(Color(1, 0.5, 0.05), true), Vector3(0.45, 0.75, 0.15))
	visual.add_child(bucket)
	visual.add_child(Util.torus(0.2, 0.24, Util.mat(Color(0.1, 0.1, 0.1)), Vector3(0.45, 1.0, 0.15)))


func _physics_process(delta: float) -> void:
	if main.state != "playing":
		return
	heckle_cd -= delta
	sway_t += delta
	var w = main.nearest_warden(global_position)
	var speed: float = info.speed
	match state:
		"knocked":
			knock_left -= delta
			visual.rotation.x = lerpf(visual.rotation.x, -PI / 2.0, 1.0 - exp(-10.0 * delta))
			stars_label.rotation.y += delta * 5.0
			if knock_left <= 0.0:
				visual.rotation.x = 0.0
				stars_label.visible = false
				state = "flee"
				flee_left = 4.0
				_say("Alright, alright!")
			return
		"flee":
			flee_left -= delta
			speed *= 2.2
			if w:
				var away: Vector3 = global_position - w.global_position
				away.y = 0.0
				target = global_position + away.normalized() * 6.0
			if flee_left <= 0.0:
				state = "wander"
				target = main.world.random_walk_point(main.rng, global_position, 8.0, true)
		"knock":
			pester_left -= delta
			speed *= 1.3
			if w:
				target = w.global_position
				if global_position.distance_to(w.global_position) < 1.2:
					main.on_trick_or_treat(self, w)
			if pester_left <= 0.0:
				state = "wander"
				heckle_cd = randf_range(6.0, 10.0)
				_say("Aww!")
				target = main.world.random_walk_point(main.rng, global_position, 8.0, true)
		"pester":
			pester_left -= delta
			if w:
				target = w.global_position
				var d: float = global_position.distance_to(w.global_position)
				if d < 1.1 and w.can_be_hit():
					_bump(w)
			if pester_left <= 0.0:
				state = "wander"
				target = main.world.random_walk_point(main.rng, global_position, 8.0, true)
		"wander":
			if global_position.distance_to(target) < 1.0:
				target = main.world.random_walk_point(main.rng, global_position, 6.0, true)
			if kid:
				if w and global_position.distance_to(w.global_position) < 10.0 and heckle_cd <= 0.0:
					state = "knock"
					pester_left = 7.0
					_say("TRICK OR TREAT!")
					Audio.voice("kid_tot", randf_range(1.0, 1.15), 1.0, false)
			elif w and global_position.distance_to(w.global_position) < 7.0 and heckle_cd <= 0.0:
				heckle_cd = randf_range(6.0, 10.0)
				_heckle(w)
	var to := target - global_position
	to.y = 0.0
	var dir := to.normalized() if to.length() > 0.2 else Vector3.ZERO
	if kid and state == "wander":
		speed *= 0.6
	if kind == "drunk":
		# Staggers about all over the place
		dir = dir.rotated(Vector3.UP, sin(sway_t * 2.3) * 0.9)
		visual.rotation.z = sin(sway_t * 2.3) * 0.25
	velocity = dir * speed
	var before := global_position
	move_and_slide()
	position.y = 0.0
	global_position = main.world.clamp_move(before, global_position)
	if velocity.length() > 0.1:
		visual.rotation.y = atan2(velocity.x, velocity.z)
		walk_t += delta * 10.0
		visual.position.y = absf(sin(walk_t)) * 0.1


func _heckle(w) -> void:
	var lines: Array = info.lines
	_say(lines[randi() % lines.size()])
	Audio.voice(info.voice, randf_range(0.9, 1.1), 1.0, false)
	main.on_heckled(self, w)
	if randf() < 0.45:
		state = "pester"
		pester_left = 5.0


func _bump(w) -> void:
	## The drunk hugs you, the geezer shoves a watch in your face, the stag drags you into a dance
	state = "wander"
	heckle_cd = 6.0
	target = main.world.random_walk_point(main.rng, global_position, 8.0, true)
	var text: String = {"drunk": "I LOVE YOU, MATE!", "geezer": "TEN QUID! BARGAIN!", "stag": "DANCE WITH ME!",
		"caroller": "SING ALONG! FA LA LA!", "elf": "NAUGHTY LIST!"}[kind]
	_say(text)
	main.on_pestered(self, w)


func _say(text: String) -> void:
	shout_label.text = text
	shout_label.visible = true
	shout_label.scale = Vector3.ONE * 1.4
	var tw := create_tween()
	tw.tween_property(shout_label, "scale", Vector3.ONE, 0.15)
	tw.tween_interval(2.0)
	tw.tween_callback(func() -> void: shout_label.visible = false)


## The warden handed over a sweet (or didn't): skip off happy, or cackle and run.
func got_sweet(sweet: bool) -> void:
	state = "flee"
	flee_left = 2.5
	heckle_cd = randf_range(18.0, 28.0)
	if sweet:
		_say(KID_THANKS[randi() % KID_THANKS.size()])
		Audio.voice("kid_thanks", randf_range(1.0, 1.15))
	else:
		_say(KID_TRICK[randi() % KID_TRICK.size()])
		Audio.voice("kid_trick", randf_range(1.0, 1.15))


func shoo() -> void:
	if state == "knocked":
		return
	state = "flee"
	flee_left = 3.0
	if kid:
		heckle_cd = randf_range(8.0, 14.0)
		_say(["Aww, no sweets?", "Spoilsport!", "Meanie!"][randi() % 3])
		return
	_say(["Alright, keep your hat on!", "I'm going, I'm going!", "Ooh, scary!"][randi() % 3])


func punched(from: Vector3) -> void:
	state = "knocked"
	knock_left = 2.5
	stars_label.visible = true
	var away := global_position - from
	away.y = 0.0
	var tw := create_tween()
	tw.tween_property(self, "global_position", main.world.clamp_move(global_position, global_position + away.normalized() * 2.5), 0.25)
	_say("OOF!")
	Audio.voice("punched", randf_range(1.0, 1.2))


func can_be_punched() -> bool:
	# Trick-or-treaters and elves are far too quick (and you don't punch kids)
	return state != "knocked" and not kid and kind != "elf"
