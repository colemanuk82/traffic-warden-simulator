extends Node3D
## Main menu: a live 3D street behind a themed menu, plus level select, wardrobe,
## unlockables, settings and controls. Fully playable with a controller.

const Levels := preload("res://scripts/levels.gd")
const Catalogue := preload("res://scripts/catalogue.gd")
const WorldScript := preload("res://scripts/world.gd")
const CarScript := preload("res://scripts/car.gd")
const CharacterScript := preload("res://scripts/character.gd")
const Prompt := preload("res://scripts/prompt.gd")
const Hud := preload("res://scripts/hud.gd")
const Career := preload("res://scripts/career.gd")
const WeatherInfo := preload("res://scripts/weather.gd")
const SettingsPanel := preload("res://scripts/settings_panel.gd")
const PAYPAL_URL := "https://paypal.me/colemanuk82"
const NameEntry := preload("res://scripts/name_entry.gd")

const YELLOW := Color(1.0, 0.86, 0.15)
const INK := Color(0.06, 0.05, 0.12)

var rng := RandomNumberGenerator.new()
var state := "playing"  # cars check this
var warden = null  # cars check this; there is no player in the menu
var world
var camera: Camera3D
var figure
var figure_root: Node3D
var cars_root: Node3D
var pass_timer := 0.5
var cam_t := 0.0
var screen := "main"
var ui: Control
var screens := {}
var prompt_bar: HBoxContainer
var title_root: Control
var level_info: Label
var wardrobe_rows := []
var wardrobe_status: Label
var preview_outfit := {}
var stats_label: Label
var main_first: Button
var level_mode := "career"  # which mode the level select is picking for
var wardrobe_player := 1
var record_tab := 0
var depot_rows := []
var depot_info: Label
var profile_card: Label
var profile_bar: Control
var name_entry
var profile_for := 1  # whose name the profile screen is asking for
var profile_next := "main"  # where to go after it
var now_playing: Label
var credits_text: Label
var credits_scroll := 0.0
var quit_box: Control


func _ready() -> void:
	rng.randomize()
	get_tree().paused = false
	world = WorldScript.new()
	add_child(world)
	world.build(Levels.get_level(0), rng, false)
	cars_root = Node3D.new()
	add_child(cars_root)

	figure_root = Node3D.new()
	figure_root.position = Vector3(4.5, 0, -6.0)
	add_child(figure_root)
	preview_outfit = Game.outfit.duplicate()
	_rebuild_figure()

	camera = Camera3D.new()
	camera.fov = 45.0
	add_child(camera)
	_place_camera(1.0)

	_build_ui()
	if not Game.title_seen:
		_show("title")
	elif Game.profile_name == "":
		_ask_profile(1, "main")
	else:
		_show("main")
	if Audio.current_music() == "" or Audio.current_music() in ["street", "seaside", "snow", "night", "posh"]:
		Audio.play_music("menu")
	Audio.play_ambience("birds")


func _rebuild_figure() -> void:
	if figure:
		figure.queue_free()
	figure = CharacterScript.new()
	figure_root.add_child(figure)
	figure.build(preview_outfit)
	figure.set_weapon(Game.weapon if wardrobe_player == 1 or screen != "wardrobe" else Game.weapon2)
	figure.idle_pose()


# Cars ask the scene for wardens; there are none in the menu
func all_wardens() -> Array:
	return []


func nearest_warden(_pos: Vector3):
	return null


func _outfit_target() -> Dictionary:
	return Game.outfit if wardrobe_player == 1 else Game.outfit2


func _process(delta: float) -> void:
	pass_timer -= delta
	if pass_timer <= 0.0:
		pass_timer = rng.randf_range(1.5, 3.5)
		var car = CarScript.new()
		car.main = self
		car.lane = world.lanes[rng.randi() % world.lanes.size()]
		cars_root.add_child(car)
	cam_t += delta
	_place_camera(delta)
	if figure:
		figure.animate(delta, 0.0)
		if screen == "wardrobe":
			figure_root.rotation.y += delta * 0.9
		else:
			figure_root.rotation.y = lerp_angle(figure_root.rotation.y, -0.3 + sin(cam_t * 0.7) * 0.25, 1.0 - exp(-3.0 * delta))
	if screen == "title":
		var logo: Control = screens.title.get_meta("logo")
		logo.rotation = sin(cam_t * 1.3) * 0.02
		logo.scale = Vector2.ONE * (1.0 + sin(cam_t * 2.1) * 0.02)
		screens.title.get_meta("start").modulate.a = 0.55 + 0.45 * sin(cam_t * 4.0)
	if title_root and title_root.is_visible_in_tree():
		title_root.rotation = sin(cam_t * 1.3) * 0.015
		title_root.scale = Vector2.ONE * (1.0 + sin(cam_t * 2.1) * 0.012)
	if screen == "credits" and credits_text:
		credits_scroll += delta * 42.0
		var top := 30.0 - credits_scroll
		if top < -credits_text.size.y:
			credits_scroll = -510.0  # come back in from the bottom
		credits_text.position.y = top


func _place_camera(delta: float) -> void:
	var target_pos: Vector3
	var look: Vector3
	if screen == "wardrobe":
		target_pos = figure_root.position + Vector3(-2.4, 2.0, 6.2)
		look = figure_root.position + Vector3(-1.8, 1.2, 0)
	else:
		target_pos = Vector3(sin(cam_t * 0.15) * 1.5 + 1.5, 3.2, 1.5)
		look = Vector3(sin(cam_t * 0.15) * 0.8 + 1.0, 2.2, -6.0)
	var k := 1.0 - exp(-3.0 * delta)
	camera.position = camera.position.lerp(target_pos, k)
	var cur := -camera.global_transform.basis.z
	var want := (look - camera.position).normalized()
	camera.look_at(camera.position + cur.lerp(want, k).normalized(), Vector3.UP)


# ---------------------------------------------------------------- UI building

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = Control.new()
	ui.size = Vector2(1280, 720)
	ui.theme = Game.theme
	layer.add_child(ui)

	var stripes_top := Control.new()
	stripes_top.position = Vector2(0, 0)
	stripes_top.size = Vector2(1280, 18)
	stripes_top.draw.connect(_draw_stripes.bind(stripes_top))
	ui.add_child(stripes_top)
	var stripes_bot := Control.new()
	stripes_bot.position = Vector2(0, 702)
	stripes_bot.size = Vector2(1280, 18)
	stripes_bot.draw.connect(_draw_stripes.bind(stripes_bot))
	ui.add_child(stripes_bot)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.05, 0.05, 0.1, 0.75)
	bar_bg.position = Vector2(0, 652)
	bar_bg.size = Vector2(1280, 50)
	ui.add_child(bar_bg)
	prompt_bar = HBoxContainer.new()
	prompt_bar.position = Vector2(30, 660)
	prompt_bar.add_theme_constant_override("separation", 28)
	ui.add_child(prompt_bar)

	screens.main = _build_main()
	screens.levels = _build_levels()
	screens.events = _build_events()
	screens.twoplayer = _build_twoplayer()
	screens.challenges = _build_challenges()
	screens.career = _build_career()
	screens.depot = _build_depot()
	screens.records = _build_records()
	screens.wardrobe = _build_wardrobe()
	screens.unlocks = _build_unlocks()
	screens.settings = _build_settings()
	screens.controls = _build_controls()
	screens.jukebox = _build_jukebox()
	screens.credits = _build_credits()
	screens.profile = _build_profile()
	screens.title = _build_title()
	_build_quit_box()


func _draw_stripes(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), YELLOW)
	var x := -20.0
	while x < c.size.x + 20.0:
		c.draw_colored_polygon(PackedVector2Array([
			Vector2(x, c.size.y), Vector2(x + 14, c.size.y), Vector2(x + 14 + c.size.y, 0), Vector2(x + c.size.y, 0)]), INK)
		x += 32.0


func _title_label(text: String, size: int, color := YELLOW) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Game.font_title)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(size / 5, 8))
	return l


func _button(text: String, parent: Control, cb: Callable, width := 340.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 50)
	b.pressed.connect(func() -> void:
		Audio.sfx("ui_select")
		cb.call())
	b.focus_entered.connect(func() -> void: Audio.sfx("ui_move", 1.0, 0.6))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	parent.add_child(b)
	return b


func _screen_root() -> Control:
	var c := Control.new()
	c.size = Vector2(1280, 720)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(c)
	c.visible = false
	return c


func _header(parent: Control, text: String) -> void:
	var h := _title_label(text, 54)
	h.position = Vector2(40, 30)
	parent.add_child(h)


func _build_main() -> Control:
	var root := _screen_root()
	title_root = Control.new()
	title_root.position = Vector2(60, 28)
	title_root.size = Vector2(620, 220)
	title_root.pivot_offset = Vector2(280, 100)
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_root)
	var t1 := _title_label("TRAFFIC", 84)
	title_root.add_child(t1)
	var t2 := _title_label("WARDEN", 98)
	t2.position = Vector2(0, 74)
	title_root.add_child(t2)
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.9, 0.15, 0.15)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(5)
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	badge.add_theme_stylebox_override("panel", sb)
	badge.position = Vector2(420, 96)
	badge.rotation = -0.12
	badge.add_child(_title_label("SIM", 56, Color.WHITE))
	title_root.add_child(badge)
	var tag := _title_label("Ticket. Dodge. Punch. Repeat.", 26, Color.WHITE)
	tag.position = Vector2(6, 180)
	title_root.add_child(tag)

	# Three columns: play, your warden, extras
	var cols := HBoxContainer.new()
	cols.position = Vector2(60, 262)
	cols.add_theme_constant_override("separation", 18)
	root.add_child(cols)
	var w := 252.0
	var play := _menu_column(cols, "PLAY", Color(0.45, 1.0, 0.5))
	main_first = _button("Start Shift", play, func() -> void: _pick_levels("career"), w)
	_button("Training Day", play, _start_training, w)
	_button("Special Events", play, func() -> void: _show("events"), w)
	_button("Endless Mode", play, func() -> void: _pick_levels("endless"), w)
	_button("Two Player", play, func() -> void: _show("twoplayer"), w)
	_button("Challenges", play, func() -> void: _show("challenges"), w)
	var you := _menu_column(cols, "YOUR WARDEN", YELLOW)
	_button("Career", you, func() -> void: _show("career"), w)
	_button("The Depot (Shop)", you, func() -> void: _show("depot"), w)
	_button("Wardrobe", you, _open_wardrobe.bind(1), w)
	_button("Unlockables", you, func() -> void: _show("unlocks"), w)
	_button("High Scores", you, func() -> void: _show("records"), w)
	var extra := _menu_column(cols, "EXTRAS", Color(0.55, 0.8, 1.0))
	var settings_btn := _button("Settings", extra, func() -> void: _show("settings"), w)
	_button("Controls", extra, func() -> void: _show("controls"), w)
	_button("Jukebox", extra, func() -> void: _show("jukebox"), w)
	_button("Change Name", extra, func() -> void: _ask_profile(1, "main"), w)
	_button("Credits", extra, func() -> void: _show("credits"), w)
	_button("Clock Off (Quit)", extra, _ask_quit, w)
	for col in [play, you, extra]:
		for b in col.get_children():
			if b is Button:
				b.custom_minimum_size.y = 46
				b.add_theme_font_size_override("font_size", 23)

	# Support button, top right. Up from the Extras column reaches it on a controller
	var support := _button("Support me on PayPal", root, func() -> void: OS.shell_open(PAYPAL_URL), 350)
	support.position = Vector2(892, 22)
	support.custom_minimum_size.y = 46
	support.add_theme_font_size_override("font_size", 22)
	support.add_theme_color_override("font_color", Color.WHITE)
	support.add_theme_color_override("font_hover_color", Color.WHITE)
	support.add_theme_color_override("font_focus_color", Color.WHITE)
	for state in ["normal", "hover", "focus", "pressed"]:
		var pb := StyleBoxFlat.new()
		pb.bg_color = Color(0.0, 0.19, 0.53) if state == "normal" else Color(0.0, 0.44, 0.73)
		pb.border_color = YELLOW if state in ["focus", "hover"] else Color(0.0, 0.6, 0.87)
		pb.set_border_width_all(4)
		pb.set_corner_radius_all(12)
		support.add_theme_stylebox_override(state, pb)
	support.focus_neighbor_bottom = support.get_path_to(settings_btn)
	support.focus_neighbor_left = support.get_path_to(settings_btn)
	settings_btn.focus_neighbor_top = settings_btn.get_path_to(support)

	# The warden's ID card, top right
	var card := PanelContainer.new()
	card.position = Vector2(892, 84)
	card.custom_minimum_size = Vector2(350, 196)
	root.add_child(card)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 4)
	card.add_child(cv)
	profile_card = Label.new()
	profile_card.add_theme_font_size_override("font_size", 21)
	cv.add_child(profile_card)
	profile_bar = Control.new()
	profile_bar.custom_minimum_size = Vector2(310, 16)
	profile_bar.draw.connect(func() -> void:
		var r := Game.rank()
		var base: int = int(Career.RANKS[r].xp)
		var next_xp: int = int(Career.RANKS[r + 1].xp) if r + 1 < Career.RANKS.size() else base
		var frac := 1.0 if next_xp <= base else clampf(float(Game.xp - base) / float(next_xp - base), 0.0, 1.0)
		profile_bar.draw_rect(Rect2(0, 2, 310, 12), Color(0.05, 0.05, 0.1))
		profile_bar.draw_rect(Rect2(1, 3, 308 * frac, 10), YELLOW))
	cv.add_child(profile_bar)
	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 19)
	cv.add_child(stats_label)
	return root


func _menu_column(parent: Control, title: String, color: Color) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	parent.add_child(v)
	var l := _title_label(title, 26, color)
	v.add_child(l)
	return v


func _open_wardrobe(player: int) -> void:
	wardrobe_player = player
	_show("wardrobe")


func _pick_levels(mode: String) -> void:
	level_mode = mode
	if mode in ["coop", "race"] and Game.profile2_name == "":
		_ask_profile(2, "levels")
		return
	_show("levels")


func _start(mode: String, level := -1, event := "", training := false) -> void:
	Audio.sfx("ui_select")
	Audio.sfx("whistle")
	Game.training = training
	Game.mode = mode
	Game.current_event = event
	if level >= 0:
		Game.current_level = level
	Game.change_scene("res://main.tscn")


func _build_levels() -> Control:
	var root := _screen_root()
	_header(root, "PICK YOUR BEAT")
	root.set_meta("header", root.get_child(0))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(40, 104)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)
	for i in Levels.count():
		var lv := Levels.get_level(i)
		var b := Button.new()
		b.custom_minimum_size = Vector2(289, 140)
		b.set_meta("level", i)
		grid.add_child(b)
		var map := Control.new()
		map.position = Vector2(8, 8)
		map.size = Vector2(72, 72)
		map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map.draw.connect(_draw_level_map.bind(map, lv))
		b.add_child(map)
		var name := _title_label(lv.name, 23)
		name.position = Vector2(88, 6)
		name.size = Vector2(194, 74)
		name.autowrap_mode = TextServer.AUTOWRAP_WORD
		name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(name)
		var stars := Control.new()
		stars.position = Vector2(8, 82)
		stars.size = Vector2(274, 30)
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stars.draw.connect(func() -> void:
			var n := Game.level_stars(i)
			for s in 3:
				Hud.draw_star(stars, Vector2(14 + s * 30, 15), 12.0, s < n)
			var medal := Game.best_time_medal(lv.id, float(lv.time))
			if medal > 0:
				var mc: Color = [Color.WHITE, Color(0.8, 0.5, 0.25), Color(0.8, 0.82, 0.88), Color(1, 0.8, 0.2)][medal]
				stars.draw_circle(Vector2(112, 15), 11.0, INK)
				stars.draw_circle(Vector2(112, 15), 9.0, mc)
			var found: int = (Game.collectibles.get(lv.id, []) as Array).size()
			stars.draw_string(Game.font_body, Vector2(132, 22), "%d/3" % found, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.8, 0.2) if found == 3 else INK))
		b.add_child(stars)
		var lock := Label.new()
		lock.position = Vector2(8, 110)
		lock.size = Vector2(274, 26)
		lock.add_theme_font_size_override("font_size", 16)
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lock.set_meta("is_lock", true)
		b.add_child(lock)
		b.pressed.connect(func() -> void:
			if Game.level_unlocked(i):
				_start(level_mode, i)
			else:
				Audio.sfx("wrong", 1.0, 0.6))
		b.focus_entered.connect(func() -> void:
			Audio.sfx("ui_move", 1.0, 0.6)
			_update_level_info(i))
		b.mouse_entered.connect(func() -> void: b.grab_focus())
	level_info = Label.new()
	level_info.position = Vector2(40, 556)
	level_info.size = Vector2(1200, 92)
	level_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	level_info.add_theme_font_size_override("font_size", 22)
	root.add_child(level_info)
	root.set_meta("grid", grid)
	return root


func _draw_level_map(c: Control, lv: Dictionary) -> void:
	var b: Rect2 = lv.bounds
	var sc := minf(c.size.x / b.size.x, c.size.y / b.size.y)
	var off := (c.size - b.size * sc) / 2.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = lv.ground.darkened(0.2)
	bg.set_corner_radius_all(10)
	bg.border_color = INK
	bg.set_border_width_all(3)
	c.draw_style_box(bg, Rect2(Vector2.ZERO, c.size))
	for road in lv.roads:
		for i in range(road.size() - 1):
			var r := Rect2(road[i], Vector2.ZERO).expand(road[i + 1]).grow(8.0).intersection(b)
			c.draw_rect(Rect2(off + (r.position - b.position) * sc, r.size * sc), Color(0.78, 0.78, 0.75))
	for road in lv.roads:
		for i in range(road.size() - 1):
			var r := Rect2(road[i], Vector2.ZERO).expand(road[i + 1]).grow(4.0).intersection(b)
			c.draw_rect(Rect2(off + (r.position - b.position) * sc, r.size * sc), Color(0.25, 0.25, 0.3))


func _update_level_info(i: int) -> void:
	var lv := Levels.get_level(i)
	if not Game.level_unlocked(i):
		level_info.text = "%s is locked. Earn %d stars to open it (you have %d)." % [lv.name, lv.stars_needed, Game.total_stars()]
		return
	var best: Dictionary = Game.best.get(lv.id, {})
	var best_text := ("Best score %d" % best.score) if best.has("score") else "Not played yet"
	var weathers: Array = []
	for w in lv.get("weathers", ["clear"]):
		var n: String = preload("res://scripts/weather.gd").INFO[w].name
		if not n in weathers:
			weathers.append(n)
	if Game.best_times.has(lv.id):
		best_text += ".  Fastest quota %s" % Hud._clock(float(Game.best_times[lv.id]))
	var goal := "Quota %d tickets in %d:%02d" % [lv.quota, int(lv.time) / 60, int(lv.time) % 60]
	match level_mode:
		"endless":
			goal = "Endless: waves of one minute, each needs more tickets"
			best_text = "Best wave %d" % int(Game.endless_best.get(lv.id, 0))
		"coop":
			goal = "Co-op: %d tickets between you" % int(ceil(lv.quota * 1.6))
		"race":
			goal = "Ticket race: most tickets in %d:%02d wins" % [int(lv.time) / 60, int(lv.time) % 60]
	level_info.text = "%s  %s\n%s.  %s.  Weather: %s" % [
		lv.name.to_upper(), lv.blurb, goal, best_text, ", ".join(weathers)]


func _refresh_levels() -> void:
	var grid: GridContainer = screens.levels.get_meta("grid")
	for b in grid.get_children():
		var i: int = b.get_meta("level")
		var open := Game.level_unlocked(i)
		b.modulate = Color.WHITE if open else Color(0.6, 0.6, 0.65)
		for c in b.get_children():
			c.queue_redraw()
			if c.has_meta("is_lock"):
				c.text = "" if open else "LOCKED: %d stars" % Levels.get_level(i).stars_needed
				c.add_theme_color_override("font_color", INK)
				c.remove_theme_constant_override("outline_size")
				c.add_theme_constant_override("outline_size", 0)


# ---------------------------------------------------------------- wardrobe

func _build_wardrobe() -> Control:
	var root := _screen_root()
	_header(root, "WARDROBE")
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 110)
	panel.custom_minimum_size = Vector2(560, 470)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	panel.add_child(v)
	var who := _title_label("PLAYER 1", 26, Color.WHITE)
	v.add_child(who)
	root.set_meta("who", who)
	for slot in Catalogue.SLOTS:
		var row := Button.new()
		row.custom_minimum_size = Vector2(520, 46)
		row.add_theme_font_size_override("font_size", 24)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.set_meta("slot", slot)
		row.gui_input.connect(_on_row_input.bind(row))
		row.pressed.connect(func() -> void: _cycle(slot, 1))
		row.focus_entered.connect(func() -> void:
			Audio.sfx("ui_move", 1.0, 0.6)
			_update_wardrobe_status(slot))
		row.mouse_entered.connect(func() -> void: row.grab_focus())
		v.add_child(row)
		wardrobe_rows.append(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	_button("Randomise", h, _randomise, 255)
	_button("Done", h, func() -> void: _show("main"), 255)
	wardrobe_status = Label.new()
	wardrobe_status.position = Vector2(620, 560)
	wardrobe_status.size = Vector2(600, 60)
	wardrobe_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	wardrobe_status.add_theme_font_size_override("font_size", 24)
	root.add_child(wardrobe_status)
	return root


func _on_row_input(event: InputEvent, row: Button) -> void:
	var slot: String = row.get_meta("slot")
	if event.is_action_pressed("ui_left"):
		_cycle(slot, -1)
		row.accept_event()
	elif event.is_action_pressed("ui_right"):
		_cycle(slot, 1)
		row.accept_event()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_cycle(slot, -1)
		row.accept_event()


func _cycle(slot: String, dir: int) -> void:
	var items := Catalogue.items(slot)
	var idx := 0
	for i in items.size():
		if items[i].id == preview_outfit[slot]:
			idx = i
	idx = (idx + dir + items.size()) % items.size()
	preview_outfit[slot] = items[idx].id
	if Game.item_unlocked(items[idx]):
		_outfit_target()[slot] = items[idx].id
		Game.save_game()
	Audio.sfx("ui_move", 1.0 + dir * 0.1)
	_rebuild_figure()
	_refresh_wardrobe()
	_update_wardrobe_status(slot)


func _randomise() -> void:
	for slot in Catalogue.SLOTS:
		var open := []
		for it in Catalogue.items(slot):
			if Game.item_unlocked(it):
				open.append(it.id)
		var pick: String = open[rng.randi() % open.size()]
		preview_outfit[slot] = pick
		_outfit_target()[slot] = pick
	Game.save_game()
	Audio.sfx("boing")
	_rebuild_figure()
	_refresh_wardrobe()


func _refresh_wardrobe() -> void:
	for row in wardrobe_rows:
		var slot: String = row.get_meta("slot")
		var it := Catalogue.find(slot, preview_outfit[slot])
		var locked := not Game.item_unlocked(it)
		row.text = "%s:   <  %s  >%s" % [Catalogue.SLOT_NAMES[slot], it.name, "   (LOCKED)" if locked else ""]


func _update_wardrobe_status(slot: String) -> void:
	var it := Catalogue.find(slot, preview_outfit[slot])
	if Game.item_unlocked(it):
		var n := 0
		for x in Catalogue.items(slot):
			if Game.item_unlocked(x):
				n += 1
		wardrobe_status.text = "%s: %d of %d unlocked. Left / right to change." % [Catalogue.SLOT_NAMES[slot], n, Catalogue.items(slot).size()]
		wardrobe_status.add_theme_color_override("font_color", Color.WHITE)
	else:
		var prog := Game.item_progress(it)
		wardrobe_status.text = "LOCKED: %s%s. You can try it on, but it won't be saved." % [
			Catalogue.req_text(it, Levels.names()), (" (%s)" % prog) if prog != "" else ""]
		wardrobe_status.add_theme_color_override("font_color", Color(1, 0.6, 0.5))


func _leave_wardrobe() -> void:
	## Drop any locked items that were only being tried on
	preview_outfit = Game.outfit.duplicate()
	wardrobe_player = 1
	_rebuild_figure()


# ---------------------------------------------------------------- unlockables

func _build_unlocks() -> Control:
	var root := _screen_root()
	_header(root, "UNLOCKABLES")
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 110)
	scroll.size = Vector2(760, 530)
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.custom_minimum_size = Vector2(740, 0)
	scroll.add_child(v)
	root.set_meta("list", v)
	var side := PanelContainer.new()
	side.position = Vector2(830, 110)
	side.custom_minimum_size = Vector2(410, 530)
	root.add_child(side)
	var sl := Label.new()
	sl.add_theme_font_size_override("font_size", 24)
	sl.autowrap_mode = TextServer.AUTOWRAP_WORD
	sl.custom_minimum_size = Vector2(370, 0)
	side.add_child(sl)
	root.set_meta("side", sl)
	return root


func _refresh_unlocks() -> void:
	var v: VBoxContainer = screens.unlocks.get_meta("list")
	for c in v.get_children():
		c.queue_free()
	var total := 0
	var have := 0
	var names := Levels.names()
	for i in Levels.count():
		var lv := Levels.get_level(i)
		total += 1
		var open := Game.level_unlocked(i)
		if open:
			have += 1
		_unlock_row(v, "Level", lv.name, open, "Earn %d stars" % lv.stars_needed, "%d / %d" % [mini(Game.total_stars(), lv.stars_needed), lv.stars_needed])
	for e in Career.EVENTS:
		total += 1
		var open := Game.event_unlocked(e)
		if open:
			have += 1
		_unlock_row(v, "Event", e.name, open, "Earn %d stars" % e.stars_needed, "%d / %d" % [mini(Game.total_stars(), e.stars_needed), e.stars_needed])
	for slot in Catalogue.SLOTS:
		for it in Catalogue.items(slot):
			if not it.has("req"):
				continue
			total += 1
			var open := Game.item_unlocked(it)
			if open:
				have += 1
			_unlock_row(v, Catalogue.SLOT_NAMES[slot], it.name, open, Catalogue.req_text(it, names), Game.item_progress(it))
	var sl: Label = screens.unlocks.get_meta("side")
	sl.text = "UNLOCKED %d / %d\n\nStars  %d / %d\nShifts worked  %d\nTickets written  %d\nPERFECT writes  %d\nDrivers punched  %d\nTimes heckled  %d\nClose calls  %d\n\nFinish shifts, earn stars and cause chaos to unlock more." % [
		have, total, Game.total_stars(), Levels.count() * 3, Game.stat_value("shifts"), Game.stat_value("tickets"),
		Game.stat_value("perfects"), Game.stat_value("punches"), Game.stat_value("heckles"), Game.stat_value("close_calls")]
	await get_tree().process_frame
	if v.get_child_count() > 0 and screen == "unlocks":
		v.get_child(0).grab_focus()


func _unlock_row(v: VBoxContainer, kind: String, name: String, open: bool, req: String, prog: String) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(720, 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	if open:
		b.text = "OK   %s: %s" % [kind, name]
	else:
		b.text = "LOCKED   %s: %s  -  %s%s" % [kind, name, req, ("  (%s)" % prog) if prog != "" else ""]
		b.modulate = Color(0.75, 0.75, 0.8)
	b.focus_entered.connect(func() -> void: Audio.sfx("ui_move", 1.0, 0.4))
	v.add_child(b)


# ---------------------------------------------------------------- settings and controls

func _build_settings() -> Control:
	var root := _screen_root()
	_header(root, "SETTINGS")
	var panel = SettingsPanel.new()
	panel.allow_reset = true
	panel.position = Vector2(40, 112)
	panel.closed.connect(func() -> void: _show("main"))
	root.add_child(panel)
	root.set_meta("panel", panel)
	return root


func _build_controls() -> Control:
	var root := _screen_root()
	_header(root, "CONTROLS")
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 110)
	panel.custom_minimum_size = Vector2(800, 440)
	root.add_child(panel)
	var g := GridContainer.new()
	g.columns = 3
	g.add_theme_constant_override("h_separation", 40)
	g.add_theme_constant_override("v_separation", 6)
	panel.add_child(g)
	for h in ["", "Keyboard & mouse", "Xbox controller"]:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", YELLOW)
		g.add_child(l)
	var rows := [["Move", "move"], ["Sprint", "sprint"], ["Write ticket / stop needle", "ticket"], ["Punch", "punch"],
		["Whistle (freezes drivers)", "whistle"], ["Dive (dodge)", "dive"], ["Use gadget", "gadget"],
		["Switch gadget", "gadget_next"], ["Pause", "pause"]]
	for r in rows:
		var l := Label.new()
		l.text = r[0]
		g.add_child(l)
		for pad in [0, 1]:
			var p := Prompt.make(r[1], "", 36)
			p.get_child(0).force_pad = pad
			p.get_child(0).call_deferred("_refresh")
			g.add_child(p)
	var notes := Label.new()
	notes.text = ("Mouse: left click tickets, right click punches.  Pad: right trigger also punches, left trigger also sprints.\n"
		+ "Two players: with two pads, one each. With one pad, player 1 uses the keyboard.\n"
		+ "No pads: player 2 uses the arrow keys and numpad (1 ticket, 2 punch, 3 whistle, 0 sprint, . dive, 4 / 5 gadget).")
	notes.add_theme_font_size_override("font_size", 18)
	notes.position = Vector2(40, 566)
	root.add_child(notes)
	var back := Button.new()
	back.text = "Done"
	back.position = Vector2(880, 560)
	back.custom_minimum_size = Vector2(200, 56)
	back.pressed.connect(func() -> void: _show("main"))
	root.add_child(back)
	root.set_meta("first", back)
	return root


# ---------------------------------------------------------------- special events

func _build_events() -> Control:
	var root := _screen_root()
	_header(root, "SPECIAL EVENTS")
	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(40, 110)
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 16)
	root.add_child(grid)
	for e in Career.EVENTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(590, 200)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.set_meta("event", e.id)
		grid.add_child(b)
		var name := _title_label(e.name, 34)
		name.position = Vector2(18, 10)
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(name)
		var info := Label.new()
		info.position = Vector2(18, 58)
		info.size = Vector2(556, 136)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD
		info.add_theme_font_size_override("font_size", 20)
		info.add_theme_color_override("font_color", INK)
		info.add_theme_constant_override("outline_size", 0)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(info)
		b.set_meta("info", info)
		b.pressed.connect(func() -> void:
			if Game.event_unlocked(e):
				_start("event", Levels.index_of(e.base), e.id)
			else:
				Audio.sfx("wrong", 1.0, 0.6))
		b.focus_entered.connect(func() -> void: Audio.sfx("ui_move", 1.0, 0.6))
		b.mouse_entered.connect(func() -> void: b.grab_focus())
	root.set_meta("grid", grid)
	return root


func _refresh_events() -> void:
	var grid: GridContainer = screens.events.get_meta("grid")
	for b in grid.get_children():
		var e := Career.event(b.get_meta("event"))
		var info: Label = b.get_meta("info")
		var open := Game.event_unlocked(e)
		b.modulate = Color.WHITE if open else Color(0.6, 0.6, 0.65)
		var best: Dictionary = Game.best.get(e.id, {})
		var stars := "%d / 3" % int(best.get("stars", 0))
		info.text = "%s\n%s" % [e.blurb, ("Best %d   Stars %s   Base: %s" % [int(best.get("score", 0)), stars, Levels.names()[e.base]]) if open else "LOCKED: earn %d stars" % e.stars_needed]
	grid.get_child(0).grab_focus()


# ---------------------------------------------------------------- two player

func _build_twoplayer() -> Control:
	var root := _screen_root()
	_header(root, "TWO PLAYER")
	var v := VBoxContainer.new()
	v.position = Vector2(60, 120)
	v.add_theme_constant_override("separation", 10)
	root.add_child(v)
	root.set_meta("first", _button("Co-op Shift", v, _pick_levels.bind("coop"), 380))
	_button("Ticket Race", v, _pick_levels.bind("race"), 380)
	_button("Player 2 Wardrobe", v, _open_wardrobe.bind(2), 380)
	_button("Player 2 Name", v, func() -> void: _ask_profile(2, "twoplayer"), 380)
	_button("Back", v, func() -> void: _show("main"), 380)
	var info_panel := PanelContainer.new()
	info_panel.position = Vector2(480, 120)
	info_panel.custom_minimum_size = Vector2(740, 0)
	root.add_child(info_panel)
	var info := Label.new()
	info.custom_minimum_size = Vector2(700, 0)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_theme_font_size_override("font_size", 22)
	info.text = "Split-screen for two wardens.\nCO-OP: one shared quota and a team score.\nTICKET RACE: whoever writes the most tickets wins.\n\nWith two controllers, each player gets one. With one controller, player 1 uses the keyboard and player 2 the pad. With none, player 2 uses the arrow keys and the number pad (1 ticket, 2 punch, 3 whistle, 0 sprint, . dive, 4 gadget)."
	info_panel.add_child(info)
	return root


# ---------------------------------------------------------------- challenges

func _build_challenges() -> Control:
	var root := _screen_root()
	_header(root, "CHALLENGES")
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 110)
	panel.custom_minimum_size = Vector2(800, 520)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	root.set_meta("list", v)
	return root


func _refresh_challenges() -> void:
	var v: VBoxContainer = screens.challenges.get_meta("list")
	for c in v.get_children():
		c.queue_free()
	var first: Button = null
	v.add_child(_title_label("TODAY  (+%d quid and %d XP each)" % [Game.Challenges.DAILY_REWARD.wages, Game.Challenges.DAILY_REWARD.xp], 28))
	for c in Game.daily_challenges():
		var b := _challenge_row(v, c.text, c.done, "")
		if first == null:
			first = b
	v.add_child(_title_label("THIS WEEK  (+%d quid and %d XP each)" % [Game.Challenges.WEEKLY_REWARD.wages, Game.Challenges.WEEKLY_REWARD.xp], 28))
	for c in Game.weekly_challenges():
		_challenge_row(v, c.text, c.done, "%d / %d" % [mini(c.progress, c.n), c.n])
	var note := Label.new()
	note.text = "New daily challenges every day, and new weekly ones every Monday."
	note.add_theme_font_size_override("font_size", 20)
	v.add_child(note)
	Game.save_game()
	await get_tree().process_frame
	if first and screen == "challenges":
		first.grab_focus()


func _challenge_row(v: VBoxContainer, text: String, done: bool, prog: String) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(760, 46)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	b.text = "%s   %s%s" % ["DONE" if done else "[  ]", text, ("    (%s)" % prog) if prog != "" and not done else ""]
	if done:
		b.modulate = Color(0.6, 1.0, 0.6)
	b.focus_entered.connect(func() -> void: Audio.sfx("ui_move", 1.0, 0.4))
	v.add_child(b)
	return b


# ---------------------------------------------------------------- career

func _build_career() -> Control:
	var root := _screen_root()
	_header(root, "CAREER")
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 110)
	panel.custom_minimum_size = Vector2(760, 520)
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	root.set_meta("list", v)
	return root


func _refresh_career() -> void:
	var v: VBoxContainer = screens.career.get_meta("list")
	for c in v.get_children():
		c.queue_free()
	var r := Game.rank()
	v.add_child(_title_label(Career.RANKS[r].name.to_upper(), 40, Color.WHITE))
	var next_xp: int = int(Career.RANKS[r + 1].xp) if r + 1 < Career.RANKS.size() else Game.xp
	var bar := Control.new()
	bar.custom_minimum_size = Vector2(700, 30)
	bar.draw.connect(func() -> void:
		var base: int = int(Career.RANKS[r].xp)
		var frac := 1.0 if next_xp <= base else clampf(float(Game.xp - base) / float(next_xp - base), 0.0, 1.0)
		bar.draw_rect(Rect2(0, 4, 700, 22), Color(0.1, 0.1, 0.15))
		bar.draw_rect(Rect2(2, 6, 696 * frac, 18), YELLOW))
	v.add_child(bar)
	var l := Label.new()
	l.text = "XP %d%s     Wages £%d     Shifts worked %d" % [Game.xp, (" / %d to the next rank" % next_xp) if r + 1 < Career.RANKS.size() else "  (top rank!)", Game.wages, Game.stat_value("shifts")]
	l.add_theme_font_size_override("font_size", 22)
	v.add_child(l)
	var first: Button = null
	for i in Career.RANKS.size():
		var rk: Dictionary = Career.RANKS[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(720, 52)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 21)
		b.text = "%s  %s  (%d XP):  %s" % ["OK" if i <= r else "--", rk.name, rk.xp, rk.perk]
		if i > r:
			b.modulate = Color(0.7, 0.7, 0.75)
		b.focus_entered.connect(func() -> void: Audio.sfx("ui_move", 1.0, 0.4))
		v.add_child(b)
		if first == null:
			first = b
	var g := Label.new()
	g.text = "Gadgets: press G or RB to use, Tab or View to switch. Every point you score is XP; wages are your score / 10."
	g.autowrap_mode = TextServer.AUTOWRAP_WORD
	g.custom_minimum_size = Vector2(720, 0)
	g.add_theme_font_size_override("font_size", 19)
	v.add_child(g)
	await get_tree().process_frame
	if first and screen == "career":
		first.grab_focus()


# ---------------------------------------------------------------- the depot (shop)

func _build_depot() -> Control:
	var root := _screen_root()
	_header(root, "THE DEPOT")
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 110)
	scroll.size = Vector2(800, 530)
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	v.custom_minimum_size = Vector2(780, 0)
	scroll.add_child(v)
	root.set_meta("list", v)
	depot_info = Label.new()
	depot_info.position = Vector2(860, 420)
	depot_info.size = Vector2(390, 220)
	depot_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	depot_info.add_theme_font_size_override("font_size", 22)
	root.add_child(depot_info)
	return root


func _refresh_depot(keep_focus := -1) -> void:
	var v: VBoxContainer = screens.depot.get_meta("list")
	for c in v.get_children():
		v.remove_child(c)
		c.queue_free()
	depot_rows = []
	v.add_child(_title_label("WAGES: %d QUID" % Game.wages, 32, Color(0.5, 1, 0.6)))
	v.add_child(_title_label("UPGRADES", 26))
	for u in Career.UPGRADES:
		var lvl := Game.upgrade_level(u.id)
		var cost := Game.upgrade_cost(u.id)
		var text := "%s" % u.name
		var row := _depot_row(v, text, u.desc, func() -> void:
			if Game.buy_upgrade(u.id):
				Audio.sfx("cash")
				_refresh_depot(_depot_focus())
			else:
				Audio.sfx("wrong", 1.0, 0.6), cost >= 0 and Game.wages >= cost)
		_level_bar(row, lvl, u.costs.size(), ("£%d" % cost) if cost >= 0 else "MAXED")
	if Game.upgrade_level("bike") > 0:
		_depot_row(v, "Ride the bike when sprinting:  %s" % ("ON" if Game.settings.get("bike", true) else "OFF"), "Turn the Council Bike on or off.", func() -> void:
			Game.settings.bike = not Game.settings.get("bike", true)
			Game.save_game()
			Audio.sfx("ui_select")
			_refresh_depot(_depot_focus()), true)
	v.add_child(_title_label("WEAPONS  (A / Enter: buy or equip for player 1, X / Space: equip for player 2)", 20))
	for w in Career.WEAPONS:
		var owned: bool = w.id in Game.weapons_owned
		var holders := []
		if Game.weapon == w.id:
			holders.append("P1")
		if Game.weapon2 == w.id:
			holders.append("P2")
		var tags := ("   EQUIPPED: " + " & ".join(holders)) if not holders.is_empty() else ""
		var text := "%s   %s%s" % [w.name, "OWNED" if owned else "£%d" % w.cost, tags]
		var row := _depot_row(v, text, w.desc, func() -> void:
			if w.id in Game.weapons_owned:
				Game.weapon = w.id
				Game.save_game()
				Audio.sfx("ui_select")
			elif Game.buy_weapon(w.id):
				Audio.sfx("cash")
			else:
				Audio.sfx("wrong", 1.0, 0.6)
				return
			_rebuild_figure()
			_refresh_depot(_depot_focus()), owned or Game.wages >= int(w.cost))
		row.gui_input.connect(func(ev: InputEvent) -> void:
			if ev.is_action_pressed("whistle") and w.id in Game.weapons_owned:
				Game.weapon2 = w.id
				Game.save_game()
				Audio.sfx("ui_select")
				row.accept_event()
				_refresh_depot(_depot_focus()))
	if keep_focus >= 0:
		await get_tree().process_frame
		depot_rows[mini(keep_focus, depot_rows.size() - 1)].grab_focus()


func _depot_focus() -> int:
	var f := get_viewport().gui_get_focus_owner()
	return depot_rows.find(f)


## Upgrade level as a row of filled and empty blocks, with the price beside it.
func _level_bar(row: Button, lvl: int, max_lvl: int, price: String) -> void:
	var bar := HBoxContainer.new()
	bar.position = Vector2(400, 9)
	bar.add_theme_constant_override("separation", 5)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)
	for k in max_lvl:
		var pip := Panel.new()
		pip.custom_minimum_size = Vector2(30, 24)
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(5)
		sb.bg_color = Color(1, 0.82, 0.15) if k < lvl else Color(0.15, 0.15, 0.22)
		sb.border_color = Color(0.05, 0.05, 0.1)
		sb.set_border_width_all(2)
		pip.add_theme_stylebox_override("panel", sb)
		bar.add_child(pip)
	var cost := Label.new()
	cost.text = "   " + price
	cost.add_theme_font_size_override("font_size", 21)
	cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(cost)


func _depot_row(v: VBoxContainer, text: String, desc: String, cb: Callable, affordable: bool) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(760, 44)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 21)
	b.text = text
	if not affordable:
		b.modulate = Color(0.75, 0.75, 0.8)
	b.pressed.connect(cb)
	b.focus_entered.connect(func() -> void:
		Audio.sfx("ui_move", 1.0, 0.4)
		depot_info.text = desc)
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	v.add_child(b)
	depot_rows.append(b)
	return b


# ---------------------------------------------------------------- high scores

func _record_boards() -> Array:
	var out := []
	for i in Levels.count():
		var lv := Levels.get_level(i)
		out.append({"id": lv.id, "name": lv.name, "level": lv})
	for e in Career.EVENTS:
		out.append({"id": e.id, "name": e.name, "level": Levels.get_level(Levels.index_of(e.base))})
	out.append({"id": "endless", "name": "Endless Mode"})
	out.append({"id": "coop", "name": "Two Player Co-op"})
	return out


func _build_records() -> Control:
	var root := _screen_root()
	_header(root, "HIGH SCORES")
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 110)
	panel.custom_minimum_size = Vector2(760, 520)
	root.add_child(panel)
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 24)
	l.custom_minimum_size = Vector2(720, 0)
	panel.add_child(l)
	root.set_meta("text", l)
	var back := Button.new()
	back.text = "Done"
	back.position = Vector2(880, 560)
	back.custom_minimum_size = Vector2(200, 56)
	back.pressed.connect(func() -> void: _show("main"))
	root.add_child(back)
	root.set_meta("back", back)
	return root


func _refresh_records() -> void:
	var boards := _record_boards()
	record_tab = (record_tab + boards.size()) % boards.size()
	var b: Dictionary = boards[record_tab]
	var lines := PackedStringArray()
	lines.append("<  %s  >      (%d of %d)" % [b.name.to_upper(), record_tab + 1, boards.size()])
	lines.append("")
	var entries := Game.board(b.id)
	if entries.is_empty():
		lines.append("No scores yet. Go and ticket someone!")
	for i in entries.size():
		var e: Dictionary = entries[i]
		var extra := ""
		if b.id == "endless":
			extra = "   wave %d, %s" % [int(e.get("wave", 0)), e.get("level", "")]
		lines.append("%d.   %s   %7d%s      %s" % [i + 1, e.name, int(e.score), extra, e.get("date", "")])
	lines.append("")
	if b.has("level"):
		var best: Dictionary = Game.best.get(b.id, {})
		lines.append("Best stars: %d / 3" % int(best.get("stars", 0)))
		if Game.best_times.has(b.id):
			var medal: int = Game.best_time_medal(b.id, float(b.level.time))
			lines.append("Fastest quota: %s   %s" % [Hud._clock(float(Game.best_times[b.id])), ["", "BRONZE medal", "SILVER medal", "GOLD medal"][medal]])
			lines.append("(Gold: quota in under 45%% of the shift, silver 65%%, bronze 85%%)")
		if Levels.index_of(b.id) >= 0 and Levels.get_level(Levels.index_of(b.id)).id == b.id:
			lines.append("Golden Tickets found: %d / 3" % (Game.collectibles.get(b.id, []) as Array).size())
			lines.append("Best endless wave: %d" % int(Game.endless_best.get(b.id, 0)))
	var l: Label = screens.records.get_meta("text")
	l.text = "\n".join(lines)
	screens.records.get_meta("back").grab_focus()


# ---------------------------------------------------------------- jukebox

func _build_jukebox() -> Control:
	var root := _screen_root()
	_header(root, "JUKEBOX")
	now_playing = _title_label("", 26, Color.WHITE)
	now_playing.position = Vector2(44, 96)
	root.add_child(now_playing)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.position = Vector2(40, 146)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	root.add_child(grid)
	var style_names := {"theme": "Theme", "classic": "Classic", "event": "Special event", "rock": "Rock & Metal"}
	for t in Audio.TRACKS:
		var file: String = t[0]
		var b := _button("", grid, func() -> void:
			Audio.play_music(file, 0.6, true)
			_refresh_jukebox(), 390)
		b.custom_minimum_size.y = 50
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "  %s" % t[1]
		b.tooltip_text = style_names.get(t[2], "")
		b.set_meta("file", file)
		b.add_theme_font_size_override("font_size", 22)
	var back := _button("Done", root, func() -> void: _show("main"), 220)
	back.position = Vector2(40, 588)
	root.set_meta("grid", grid)
	return root


func _refresh_jukebox() -> void:
	var cur := Audio.current_music()
	var title := "nothing"
	for b in screens.jukebox.get_meta("grid").get_children():
		var on: bool = b.get_meta("file") == cur
		b.modulate = Color(1, 0.95, 0.5) if on else Color.WHITE
		if on:
			title = b.text.strip_edges()
	now_playing.text = "NOW PLAYING:  " + title.to_upper()


# ---------------------------------------------------------------- credits

func _build_credits() -> Control:
	var root := _screen_root()
	_header(root, "CREDITS")
	var clip := Control.new()
	clip.position = Vector2(300, 100)
	clip.size = Vector2(680, 540)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(clip)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.08, 0.7)
	bg.size = clip.size
	clip.add_child(bg)
	credits_text = Label.new()
	credits_text.size = Vector2(680, 0)
	credits_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credits_text.autowrap_mode = TextServer.AUTOWRAP_WORD
	credits_text.add_theme_font_size_override("font_size", 22)
	var tracks := []
	for t in Audio.TRACKS:
		tracks.append(t[1])
	var godot_copyright := ""
	for part in Engine.get_copyright_info():
		if part.name in ["Godot Engine", "Godot"]:
			for p in part.parts:
				godot_copyright = ", ".join(p.copyright)
	var lines := [
		"TRAFFIC WARDEN SIM", "", "",
		"CREATED BY", "Craig", "", "",
		"GAME DESIGN", "Craig", "",
		"PROGRAMMING, ART, MUSIC AND SOUND", "Built in code with Claude (Anthropic)", "", "",
		"SOUNDTRACK", "\n".join(tracks), "",
		"\"Here Comes the Bride\" from the Bridal Chorus, Richard Wagner (1850), public domain",
		"\"Jingle Bells\", James Lord Pierpont (1857), public domain", "", "",
		"VOICES", "Kokoro-82M text-to-speech by hexgrad (Apache License 2.0)", "Generated offline for this game", "", "",
		"FONTS", "Luckiest Guy by Astigmatic (Apache License 2.0)", "Lilita One by Juan Montoreano (SIL Open Font License 1.1)", "", "",
		"ENGINE", "Made with Godot Engine", "Copyright " + godot_copyright if godot_copyright != "" else "",
		"Released under the MIT licence:", "", Engine.get_license_text(), "", "",
		"THANKS FOR PLAYING", "", "Now get back out there. Those yellow lines won't enforce themselves.",
	]
	credits_text.text = "\n".join(lines)
	clip.add_child(credits_text)
	var back := _button("Done", root, func() -> void: _show("main"), 220)
	back.position = Vector2(40, 588)
	root.set_meta("first", back)
	return root


# ---------------------------------------------------------------- title screen

## The front door: the logo over the live street, then on to the name and a first training shift.
func _build_title() -> Control:
	var root := _screen_root()
	var logo := Control.new()
	logo.position = Vector2(330, 120)
	logo.size = Vector2(620, 260)
	logo.pivot_offset = Vector2(310, 130)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(logo)
	root.set_meta("logo", logo)
	var t1 := _title_label("TRAFFIC", 110)
	t1.position = Vector2(40, 0)
	logo.add_child(t1)
	var t2 := _title_label("WARDEN", 128)
	t2.position = Vector2(0, 96)
	logo.add_child(t2)
	var badge := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.9, 0.15, 0.15)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(6)
	sb.set_corner_radius_all(16)
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	badge.add_theme_stylebox_override("panel", sb)
	badge.position = Vector2(470, 140)
	badge.rotation = -0.14
	badge.add_child(_title_label("SIM", 72, Color.WHITE))
	logo.add_child(badge)
	var tag := _title_label("Rules is rules.", 34, Color.WHITE)
	tag.position = Vector2(0, 410)
	tag.size = Vector2(1280, 50)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(tag)
	var start := Prompt.make("ui_accept", "Press to start", 40, 30)
	start.position = Vector2(500, 500)
	root.add_child(start)
	root.set_meta("start", start)
	# An invisible button takes the focus, so A, Enter, Space or a click all start the game
	var go := Button.new()
	go.flat = true
	go.size = Vector2(1280, 640)
	go.modulate.a = 0.0
	go.pressed.connect(_leave_title)
	root.add_child(go)
	root.set_meta("first", go)
	return root


func _leave_title() -> void:
	if screen != "title":
		return
	Game.title_seen = true
	Audio.sfx("whistle")
	if Game.profile_name == "":
		_ask_profile(1, "training")
	else:
		_show("main")


## A short, calm first shift that teaches spotting, ticketing and running away.
func _start_training() -> void:
	_start("career", 0, "", true)


# ---------------------------------------------------------------- player profile

func _build_profile() -> Control:
	var root := _screen_root()
	name_entry = NameEntry.new()
	name_entry.position = Vector2(260, 110)
	root.add_child(name_entry)
	name_entry.submitted.connect(func(n: String) -> void:
		if profile_for == 2:
			Game.profile2_name = n
		else:
			Game.profile_name = n
		Game.save_game()
		Audio.sfx("cash")
		if profile_next == "training":
			_start_training()
		else:
			_show(profile_next))
	return root


## Asks for a player's name, then goes on to the screen called next.
func _ask_profile(player: int, next: String) -> void:
	profile_for = player
	profile_next = next
	_show("profile")


# ---------------------------------------------------------------- quit

func _build_quit_box() -> void:
	quit_box = ColorRect.new()
	quit_box.color = Color(0, 0, 0, 0.6)
	quit_box.size = Vector2(1280, 720)
	quit_box.visible = false
	ui.add_child(quit_box)
	var panel := PanelContainer.new()
	panel.position = Vector2(390, 250)
	panel.custom_minimum_size = Vector2(500, 200)
	quit_box.add_child(panel)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	var q := _title_label("Clock off for the day?", 38)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(q)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	var yes := _button("Yes, home time", h, func() -> void:
		Game.save_game()
		get_tree().quit(), 210)
	var no := _button("No, keep going", h, _close_quit, 210)
	quit_box.set_meta("no", no)
	quit_box.set_meta("yes", yes)


func _ask_quit() -> void:
	quit_box.visible = true
	quit_box.modulate.a = 0.0
	create_tween().tween_property(quit_box, "modulate:a", 1.0, 0.15)
	(quit_box.get_meta("no") as Button).grab_focus()


func _close_quit() -> void:
	quit_box.visible = false
	main_first.grab_focus()


# ---------------------------------------------------------------- navigation

func _show(name: String) -> void:
	if screen == "wardrobe" and name != "wardrobe":
		_leave_wardrobe()
	screen = name
	for k in screens:
		screens[k].visible = k == name
	# Slide the new screen in
	var cur: Control = screens[name]
	cur.modulate.a = 0.0
	cur.position.x = 40.0
	var tw := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(cur, "modulate:a", 1.0, 0.18)
	tw.tween_property(cur, "position:x", 0.0, 0.22)
	for c in prompt_bar.get_children():
		c.queue_free()
	if name != "title":
		prompt_bar.add_child(Prompt.make("ui_accept", "Select", 32, 22))
	if name != "main" and name != "title" and not (name == "profile" and Game.profile_name == ""):
		prompt_bar.add_child(Prompt.make("ui_cancel", "Back", 32, 22))
	if name == "wardrobe":
		prompt_bar.add_child(Prompt.make("ui_lr", "Change", 32, 22))
		prompt_bar.add_child(Prompt.make("tab_next", "Player 1 / 2", 32, 22))
	if name == "records":
		prompt_bar.add_child(Prompt.make("tab_prev", "", 32, 22))
		prompt_bar.add_child(Prompt.make("tab_next", "Change board", 32, 22))
	match name:
		"main":
			var rk: Dictionary = Career.RANKS[Game.rank()]
			profile_card.text = "WARDEN ID\n%s\nRank: %s" % [Game.profile_name.to_upper(), rk.name]
			stats_label.text = "Stars  %d / %d     Wages  £%d\nGolden Tickets  %d / %d" % [Game.total_stars(),
				Levels.count() * 3, Game.wages, Game.collectible_count(), Levels.count() * 3]
			profile_bar.queue_redraw()
			main_first.grab_focus()
		"levels":
			var header: Label = screens.levels.get_meta("header")
			header.text = {"career": "PICK YOUR BEAT", "endless": "ENDLESS MODE", "coop": "CO-OP: PICK A BEAT", "race": "TICKET RACE: PICK A BEAT"}[level_mode]
			_refresh_levels()
			var grid: GridContainer = screens.levels.get_meta("grid")
			var i := clampi(Game.current_level, 0, grid.get_child_count() - 1)
			grid.get_child(i).grab_focus()
			_update_level_info(i)
		"wardrobe":
			preview_outfit = _outfit_target().duplicate()
			var who: Label = screens.wardrobe.get_meta("who")
			who.text = "PLAYER %d   (Q / R or LB / RB to switch)" % wardrobe_player
			_rebuild_figure()
			_refresh_wardrobe()
			wardrobe_rows[0].grab_focus()
			_update_wardrobe_status(wardrobe_rows[0].get_meta("slot"))
		"unlocks":
			_refresh_unlocks()
		"events":
			_refresh_events()
		"challenges":
			_refresh_challenges()
		"career":
			_refresh_career()
		"depot":
			_refresh_depot()
			depot_rows[0].grab_focus()
		"records":
			_refresh_records()
		"settings":
			screens.settings.get_meta("panel").open()
		"jukebox":
			_refresh_jukebox()
			var grid: GridContainer = screens.jukebox.get_meta("grid")
			var pick: Control = grid.get_child(0)
			for b in grid.get_children():
				if b.get_meta("file") == Audio.current_music():
					pick = b
			pick.grab_focus()
		"credits":
			credits_scroll = 0.0
			screens.credits.get_meta("first").grab_focus()
		"profile":
			var start := Game.profile2_name if profile_for == 2 else Game.profile_name
			name_entry.set_title("PLAYER 2: WHO'S ON DUTY?" if profile_for == 2 else "WHO'S ON DUTY?")
			name_entry.open(start)
		"controls", "twoplayer", "title":
			screens[name].get_meta("first").grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if quit_box and quit_box.visible:
		if event.is_action_pressed("ui_cancel"):
			Audio.sfx("ui_back")
			_close_quit()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and screen in ["main", "title"]:
		Audio.sfx("ui_back")
		_ask_quit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if screen == "profile" and Game.profile_name == "":
			return  # a name is needed before the first shift
		Audio.sfx("ui_back")
		var back := "main"
		if screen == "levels" and level_mode in ["coop", "race"]:
			back = "twoplayer"
		elif screen == "profile":
			back = "twoplayer" if profile_for == 2 else "main"
		_show(back)
		get_viewport().set_input_as_handled()
	elif screen == "wardrobe" and (event.is_action_pressed("tab_next") or event.is_action_pressed("tab_prev")):
		wardrobe_player = 2 if wardrobe_player == 1 else 1
		Audio.sfx("ui_select")
		var focused := get_viewport().gui_get_focus_owner()
		_show("wardrobe")
		if focused and focused in wardrobe_rows:
			focused.grab_focus()
		get_viewport().set_input_as_handled()
	elif screen == "records" and (event.is_action_pressed("tab_next") or event.is_action_pressed("tab_prev")):
		record_tab += 1 if event.is_action_pressed("tab_next") else -1
		Audio.sfx("ui_move")
		_refresh_records()
		get_viewport().set_input_as_handled()
