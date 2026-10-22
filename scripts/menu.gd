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
	_show("main")
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
	if title_root and title_root.visible:
		title_root.rotation = sin(cam_t * 1.3) * 0.015
		title_root.scale = Vector2.ONE * (1.0 + sin(cam_t * 2.1) * 0.012)


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
	title_root.position = Vector2(60, 40)
	title_root.size = Vector2(700, 230)
	title_root.pivot_offset = Vector2(300, 110)
	title_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title_root)
	var t1 := _title_label("TRAFFIC", 96)
	title_root.add_child(t1)
	var t2 := _title_label("WARDEN", 110)
	t2.position = Vector2(0, 84)
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
	badge.position = Vector2(470, 108)
	badge.rotation = -0.12
	badge.add_child(_title_label("SIM", 64, Color.WHITE))
	title_root.add_child(badge)
	var tag := _title_label("Ticket. Dodge. Punch. Repeat.", 30, Color.WHITE)
	tag.position = Vector2(6, 200)
	title_root.add_child(tag)

	var v := GridContainer.new()
	v.columns = 2
	v.position = Vector2(60, 282)
	v.add_theme_constant_override("h_separation", 10)
	v.add_theme_constant_override("v_separation", 5)
	root.add_child(v)
	var w := 270.0
	main_first = _button("Start Shift", v, func() -> void: _pick_levels("career"), w)
	_button("Special Events", v, func() -> void: _show("events"), w)
	_button("Endless Mode", v, func() -> void: _pick_levels("endless"), w)
	_button("Two Player", v, func() -> void: _show("twoplayer"), w)
	_button("Challenges", v, func() -> void: _show("challenges"), w)
	_button("Career", v, func() -> void: _show("career"), w)
	_button("The Depot (Shop)", v, func() -> void: _show("depot"), w)
	_button("High Scores", v, func() -> void: _show("records"), w)
	_button("Wardrobe", v, _open_wardrobe.bind(1), w)
	_button("Unlockables", v, func() -> void: _show("unlocks"), w)
	_button("Settings", v, func() -> void: _show("settings"), w)
	_button("Controls", v, func() -> void: _show("controls"), w)
	_button("Clock Off (Quit)", v, func() -> void: get_tree().quit(), w)
	for b in v.get_children():
		b.custom_minimum_size.y = 44
		b.add_theme_font_size_override("font_size", 24)

	stats_label = Label.new()
	stats_label.position = Vector2(760, 520)
	stats_label.size = Vector2(500, 120)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_label.add_theme_font_size_override("font_size", 26)
	root.add_child(stats_label)
	return root


func _open_wardrobe(player: int) -> void:
	wardrobe_player = player
	_show("wardrobe")


func _pick_levels(mode: String) -> void:
	level_mode = mode
	_show("levels")


func _start(mode: String, level := -1, event := "") -> void:
	Audio.sfx("ui_select")
	Audio.sfx("whistle")
	Game.mode = mode
	Game.current_event = event
	if level >= 0:
		Game.current_level = level
	get_tree().change_scene_to_file("res://main.tscn")


func _build_levels() -> Control:
	var root := _screen_root()
	_header(root, "PICK YOUR BEAT")
	root.set_meta("header", root.get_child(0))
	var grid := GridContainer.new()
	grid.columns = 5
	grid.position = Vector2(40, 106)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	root.add_child(grid)
	for i in Levels.count():
		var lv := Levels.get_level(i)
		var b := Button.new()
		b.custom_minimum_size = Vector2(228, 212)
		b.set_meta("level", i)
		grid.add_child(b)
		var map := Control.new()
		map.position = Vector2(10, 10)
		map.size = Vector2(90, 90)
		map.mouse_filter = Control.MOUSE_FILTER_IGNORE
		map.draw.connect(_draw_level_map.bind(map, lv))
		b.add_child(map)
		var name := _title_label(lv.name, 20)
		name.position = Vector2(106, 8)
		name.size = Vector2(116, 104)
		name.autowrap_mode = TextServer.AUTOWRAP_WORD
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(name)
		var stars := Control.new()
		stars.position = Vector2(4, 120)
		stars.size = Vector2(220, 44)
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stars.draw.connect(func() -> void:
			var n := Game.level_stars(i)
			for s in 3:
				Hud.draw_star(stars, Vector2(20 + s * 36, 20), 15.0, s < n)
			var medal := Game.best_time_medal(lv.id, float(lv.time))
			if medal > 0:
				var mc: Color = [Color.WHITE, Color(0.8, 0.5, 0.25), Color(0.8, 0.82, 0.88), Color(1, 0.8, 0.2)][medal]
				stars.draw_circle(Vector2(140, 20), 13.0, INK)
				stars.draw_circle(Vector2(140, 20), 10.0, mc)
			var found: int = (Game.collectibles.get(lv.id, []) as Array).size()
			stars.draw_string(Game.font_body, Vector2(160, 28), "%d/3" % found, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 0.8, 0.2) if found == 3 else INK))
		b.add_child(stars)
		var lock := Label.new()
		lock.position = Vector2(8, 170)
		lock.size = Vector2(214, 34)
		lock.add_theme_font_size_override("font_size", 19)
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
	level_info.position = Vector2(40, 562)
	level_info.size = Vector2(1200, 86)
	level_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	level_info.add_theme_font_size_override("font_size", 24)
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
	var panel := PanelContainer.new()
	panel.position = Vector2(40, 110)
	panel.custom_minimum_size = Vector2(620, 380)
	root.add_child(panel)
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 30)
	g.add_theme_constant_override("v_separation", 22)
	panel.add_child(g)
	for pair in [["Music volume", "music"], ["Effects & voices", "sfx"]]:
		var l := Label.new()
		l.text = pair[0]
		g.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = Game.settings[pair[1]]
		s.custom_minimum_size = Vector2(280, 36)
		var key: String = pair[1]
		s.value_changed.connect(func(val: float) -> void:
			Game.settings[key] = val
			Game.apply_settings()
			Audio.sfx("tick")
			Game.save_game())
		g.add_child(s)
		if key == "music":
			root.set_meta("first", s)
	for pair in [["Fullscreen", "fullscreen"], ["Screen shake", "shake"]]:
		var l := Label.new()
		l.text = pair[0]
		g.add_child(l)
		var c := CheckButton.new()
		c.button_pressed = Game.settings[pair[1]]
		var key: String = pair[1]
		c.toggled.connect(func(on: bool) -> void:
			Game.settings[key] = on
			Game.apply_settings()
			Audio.sfx("ui_select")
			Game.save_game())
		g.add_child(c)
	var spacer := Control.new()
	g.add_child(spacer)
	var back := Button.new()
	back.text = "Done"
	back.pressed.connect(func() -> void: _show("main"))
	g.add_child(back)
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
		var stars := "*".repeat(int(best.get("stars", 0))) + "-".repeat(3 - int(best.get("stars", 0)))
		info.text = "%s\n%s" % [e.blurb, ("Best %d   Stars [%s]   Base: %s" % [int(best.get("score", 0)), stars, Levels.names()[e.base]]) if open else "LOCKED: earn %d stars" % e.stars_needed]
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
	_button("Back", v, func() -> void: _show("main"), 380)
	var info := Label.new()
	info.position = Vector2(60, 400)
	info.size = Vector2(700, 240)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD
	info.add_theme_font_size_override("font_size", 22)
	info.text = "Split-screen for two wardens.\nCO-OP: one shared quota and a team score.\nTICKET RACE: whoever writes the most tickets wins.\n\nWith two controllers, each player gets one. With one controller, player 1 uses the keyboard and player 2 the pad. With none, player 2 uses the arrow keys and the number pad (1 ticket, 2 punch, 3 whistle, 0 sprint, . dive, 4 gadget)."
	root.add_child(info)
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
		var text := "%s  [%s]   %s" % [u.name, "#".repeat(lvl) + "-".repeat(u.costs.size() - lvl), ("£%d" % cost) if cost >= 0 else "MAXED"]
		_depot_row(v, text, u.desc, func() -> void:
			if Game.buy_upgrade(u.id):
				Audio.sfx("cash")
				_refresh_depot(_depot_focus())
			else:
				Audio.sfx("wrong", 1.0, 0.6), cost >= 0 and Game.wages >= cost)
	if Game.upgrade_level("bike") > 0:
		_depot_row(v, "Ride the bike when sprinting:  %s" % ("ON" if Game.settings.get("bike", true) else "OFF"), "Turn the Council Bike on or off.", func() -> void:
			Game.settings.bike = not Game.settings.get("bike", true)
			Game.save_game()
			Audio.sfx("ui_select")
			_refresh_depot(_depot_focus()), true)
	v.add_child(_title_label("WEAPONS  (A / Enter: buy or equip for player 1, X / Space: equip for player 2)", 20))
	for w in Career.WEAPONS:
		var owned: bool = w.id in Game.weapons_owned
		var tags := ""
		if Game.weapon == w.id:
			tags += "  [P1]"
		if Game.weapon2 == w.id:
			tags += "  [P2]"
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
		lines.append("Best stars: %s" % ("*".repeat(int(best.get("stars", 0))) + "-".repeat(3 - int(best.get("stars", 0)))))
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


# ---------------------------------------------------------------- navigation

func _show(name: String) -> void:
	if screen == "wardrobe" and name != "wardrobe":
		_leave_wardrobe()
	screen = name
	for k in screens:
		screens[k].visible = k == name
	for c in prompt_bar.get_children():
		c.queue_free()
	prompt_bar.add_child(Prompt.make("ui_accept", "Select", 32, 22))
	if name != "main":
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
			stats_label.text = "%s\nStars  %d / %d     Wages  £%d\nGolden Tickets  %d / %d" % [rk.name.to_upper(), Game.total_stars(),
				Levels.count() * 3, Game.wages, Game.collectible_count(), Levels.count() * 3]
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
		"settings", "controls", "twoplayer":
			screens[name].get_meta("first").grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and screen != "main":
		Audio.sfx("ui_back")
		_show("twoplayer" if screen == "levels" and level_mode in ["coop", "race"] else "main")
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
