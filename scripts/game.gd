extends Node
## Autoload "Game": input map, save data, unlocks, outfit, settings, fonts and the UI theme.

signal device_changed(using_pad: bool)

const Levels := preload("res://scripts/levels.gd")
const Catalogue := preload("res://scripts/catalogue.gd")
const Career := preload("res://scripts/career.gd")
const Challenges := preload("res://scripts/challenges.gd")
const SAVE_PATH := "user://save.cfg"
const STAT_KEYS := ["tickets", "punches", "perfects", "heckles", "shifts", "close_calls", "bosses", "clamps", "tows",
	"cameras", "street_events", "pickups", "splashes", "zaps", "waves"]
const BOARD_SIZE := 5

var using_pad := false
var font_title: FontFile
var font_body: FontFile
var theme: Theme
var current_level := 0
var mode := "career"  # career, event, endless, coop, race
var current_event := ""
var stats := {}
var best := {}  # level/event id -> {"stars": int, "score": int}
var outfit := {
	"type": "classic", "skin": "s2", "hair": "short", "hair_color": "brown",
	"uniform": "hivis", "vest": "none", "hat": "cap", "accessory": "none",
}
var outfit2 := {
	"type": "classic", "skin": "s4", "hair": "spiky", "hair_color": "black",
	"uniform": "orange", "vest": "utility", "hat": "baseball", "accessory": "none",
}
var settings := {
	"master": 1.0, "music": 0.7, "sfx": 0.9, "voice": 0.9, "stereo": 0.8, "soundtrack": "classic",
	"fullscreen": false, "vsync": true, "fps_cap": 0, "quality": 2, "show_fps": false,
	"shake": true, "camera": "normal", "bike": true,
}
const QUALITY_NAMES := ["Low", "Medium", "High"]
const CAMERA_ZOOM := {"close": 0.82, "normal": 1.0, "far": 1.22}
var announced := []  # unlock keys already shown to the player
var xp := 0
var wages := 0
var upgrades := {}  # upgrade id -> level bought
var weapons_owned := ["fists"]
var weapon := "fists"
var weapon2 := "fists"
var boards := {}  # board id -> [{"name", "score", ...}] best first
var best_times := {}  # level/event id -> seconds taken to meet the quota
var collectibles := {}  # level id -> [index, ...]
var challenge_state := {}
var initials := "AAA"
var profile_name := ""  # player 1's name, asked for once on the first start
var profile2_name := ""  # player 2's name, asked for the first time two player is picked
var _fade: ColorRect
var _fps_label: Label
var endless_best := {}  # level id -> best wave


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in STAT_KEYS:
		stats[k] = 0
	_setup_inputs()
	_load_fonts()
	theme = _build_theme()
	load_game()
	# Everything that is already unlocked on a fresh save does not need announcing
	if announced.is_empty():
		announced = unlocked_keys()
	# Free items added in later versions don't need announcing either
	for slot in Catalogue.SLOTS:
		for it in Catalogue.items(slot):
			var key := "%s:%s" % [slot, it.id]
			if not it.has("req") and not key in announced:
				announced.append(key)
	if not "rank:0" in announced:
		announced.append("rank:0")
	using_pad = not Input.get_connected_joypads().is_empty()
	Input.joy_connection_changed.connect(_on_joy_changed)
	_build_overlay()
	get_viewport().gui_focus_changed.connect(_on_focus_changed)
	apply_settings()


# ---------------------------------------------------------------- input

func _setup_inputs() -> void:
	_add_action("move_left", [_key(KEY_A), _key(KEY_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0), _button(JOY_BUTTON_DPAD_LEFT)])
	_add_action("move_right", [_key(KEY_D), _key(KEY_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0), _button(JOY_BUTTON_DPAD_RIGHT)])
	_add_action("move_up", [_key(KEY_W), _key(KEY_UP), _axis(JOY_AXIS_LEFT_Y, -1.0), _button(JOY_BUTTON_DPAD_UP)])
	_add_action("move_down", [_key(KEY_S), _key(KEY_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0), _button(JOY_BUTTON_DPAD_DOWN)])
	_add_action("sprint", [_key(KEY_SHIFT), _axis(JOY_AXIS_TRIGGER_LEFT, 1.0), _button(JOY_BUTTON_LEFT_SHOULDER)])
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	_add_action("ticket", [_key(KEY_E), click, _button(JOY_BUTTON_A)])
	var rclick := InputEventMouseButton.new()
	rclick.button_index = MOUSE_BUTTON_RIGHT
	_add_action("punch", [_key(KEY_F), rclick, _button(JOY_BUTTON_Y), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_add_action("whistle", [_key(KEY_SPACE), _button(JOY_BUTTON_X)])
	_add_action("dive", [_key(KEY_CTRL), _button(JOY_BUTTON_B)])
	_add_action("pause", [_key(KEY_ESCAPE), _key(KEY_P), _button(JOY_BUTTON_START)])
	_add_action("gadget", [_key(KEY_G), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	_add_action("gadget_next", [_key(KEY_TAB), _button(JOY_BUTTON_BACK)])
	_add_action("tab_prev", [_key(KEY_Q), _button(JOY_BUTTON_LEFT_SHOULDER)])
	_add_action("tab_next", [_key(KEY_R), _button(JOY_BUTTON_RIGHT_SHOULDER)])
	# Menus: the built-in ui_* actions, plus WASD and the left stick
	_extend_action("ui_left", [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0), _button(JOY_BUTTON_DPAD_LEFT)])
	_extend_action("ui_right", [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0), _button(JOY_BUTTON_DPAD_RIGHT)])
	_extend_action("ui_up", [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0), _button(JOY_BUTTON_DPAD_UP)])
	_extend_action("ui_down", [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0), _button(JOY_BUTTON_DPAD_DOWN)])
	_extend_action("ui_accept", [_button(JOY_BUTTON_A)])
	_extend_action("ui_cancel", [_button(JOY_BUTTON_B)])


func _add_action(action: String, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.35)
	_extend_action(action, events)


## Two players: per-player actions "p1_move_left" and so on. With two pads each player gets one;
## with one pad player 1 uses the keyboard and player 2 the pad; with none they share the keyboard.
func setup_two_player_inputs() -> Dictionary:
	var pads := Input.get_connected_joypads()
	var p1_pad := -1
	var p2_pad := -1
	if pads.size() >= 2:
		p1_pad = pads[0]
		p2_pad = pads[1]
	elif pads.size() == 1:
		p2_pad = pads[0]
	var keys1 := {"move_left": [KEY_A], "move_right": [KEY_D], "move_up": [KEY_W], "move_down": [KEY_S],
		"sprint": [KEY_SHIFT], "ticket": [KEY_E], "punch": [KEY_F], "whistle": [KEY_SPACE], "dive": [KEY_CTRL],
		"gadget": [KEY_G], "gadget_next": [KEY_TAB]}
	var keys2 := {"move_left": [KEY_LEFT], "move_right": [KEY_RIGHT], "move_up": [KEY_UP], "move_down": [KEY_DOWN],
		"sprint": [KEY_KP_0], "ticket": [KEY_KP_1, KEY_ENTER], "punch": [KEY_KP_2], "whistle": [KEY_KP_3],
		"dive": [KEY_KP_PERIOD], "gadget": [KEY_KP_4], "gadget_next": [KEY_KP_5]}
	for p in [1, 2]:
		var pad: int = p1_pad if p == 1 else p2_pad
		var use_keys: bool = p == 1 and pad < 0 or p == 2 and pads.is_empty()
		var keys: Dictionary = keys1 if p == 1 else keys2
		for act in keys:
			var name := "p%d_%s" % [p, act]
			if InputMap.has_action(name):
				InputMap.erase_action(name)
			InputMap.add_action(name, 0.35)
			if use_keys:
				for k in keys[act]:
					InputMap.action_add_event(name, _key(k))
			if pad >= 0:
				for ev in _pad_events(act):
					ev.device = pad
					InputMap.action_add_event(name, ev)
	return {"p1_pad": p1_pad >= 0, "p2_pad": p2_pad >= 0}


func _pad_events(act: String) -> Array:
	match act:
		"move_left": return [_axis(JOY_AXIS_LEFT_X, -1.0), _button(JOY_BUTTON_DPAD_LEFT)]
		"move_right": return [_axis(JOY_AXIS_LEFT_X, 1.0), _button(JOY_BUTTON_DPAD_RIGHT)]
		"move_up": return [_axis(JOY_AXIS_LEFT_Y, -1.0), _button(JOY_BUTTON_DPAD_UP)]
		"move_down": return [_axis(JOY_AXIS_LEFT_Y, 1.0), _button(JOY_BUTTON_DPAD_DOWN)]
		"sprint": return [_axis(JOY_AXIS_TRIGGER_LEFT, 1.0), _button(JOY_BUTTON_LEFT_SHOULDER)]
		"ticket": return [_button(JOY_BUTTON_A)]
		"punch": return [_button(JOY_BUTTON_Y), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)]
		"whistle": return [_button(JOY_BUTTON_X)]
		"dive": return [_button(JOY_BUTTON_B)]
		"gadget": return [_button(JOY_BUTTON_RIGHT_SHOULDER)]
		"gadget_next": return [_button(JOY_BUTTON_BACK)]
	return []


func _extend_action(action: String, events: Array) -> void:
	for ev in events:
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	return ev


func _button(button: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	ev.device = -1
	return ev


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	ev.device = -1
	return ev


func _input(event: InputEvent) -> void:
	var pad := using_pad
	if event is InputEventJoypadButton:
		pad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	if pad != using_pad:
		using_pad = pad
		device_changed.emit(using_pad)


func _on_joy_changed(_device: int, connected: bool) -> void:
	if connected and not using_pad:
		using_pad = true
		device_changed.emit(true)


# ---------------------------------------------------------------- fonts and theme

func _load_fonts() -> void:
	font_title = FontFile.new()
	font_title.load_dynamic_font("res://fonts/LuckiestGuy-Regular.ttf")
	font_body = FontFile.new()
	font_body.load_dynamic_font("res://fonts/LilitaOne-Regular.ttf")


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 26
	t.set_color("font_color", "Label", Color.WHITE)
	t.set_color("font_outline_color", "Label", Color(0.06, 0.05, 0.12))
	t.set_constant("outline_size", "Label", 8)

	var normal := _style(Color(1.0, 0.86, 0.15), Color(0.1, 0.08, 0.12), 4)
	var hover := _style(Color(1.0, 0.93, 0.45), Color(0.1, 0.08, 0.12), 4)
	var focus := _style(Color(1.0, 0.95, 0.55), Color(0.95, 0.25, 0.2), 6)
	var pressed := _style(Color(0.95, 0.7, 0.1), Color(0.1, 0.08, 0.12), 4)
	var disabled := _style(Color(0.55, 0.55, 0.6), Color(0.2, 0.2, 0.25), 4)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", focus)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("hover_pressed", "Button", pressed)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(c, "Button", Color(0.1, 0.08, 0.12))
	t.set_color("font_disabled_color", "Button", Color(0.25, 0.25, 0.3))
	t.set_font_size("font_size", "Button", 28)

	var panel := _style(Color(0.1, 0.1, 0.18, 0.92), Color(1.0, 0.86, 0.15), 4)
	panel.corner_radius_top_left = 18
	panel.corner_radius_top_right = 18
	panel.corner_radius_bottom_left = 18
	panel.corner_radius_bottom_right = 18
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.1, 0.1, 0.15)
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.86, 0.15)
	fill.set_corner_radius_all(6)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	return t


func _style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(12)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 4)
	return s


# ---------------------------------------------------------------- settings

func apply_settings() -> void:
	var headless := DisplayServer.get_name() == "headless"
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode and not headless:
		DisplayServer.window_set_mode(mode)
	if not headless:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings.fps_cap)
	var q := int(settings.quality)
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_2X if q >= 2 else Viewport.MSAA_DISABLED
	vp.scaling_3d_scale = 0.75 if q == 0 else 1.0
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if q == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	RenderingServer.directional_shadow_atlas_set_size(4096 if q >= 2 else 2048, true)
	if _fps_label:
		_fps_label.visible = settings.show_fps
	var audio := get_node_or_null("/root/Audio")
	if audio:
		audio.apply_volumes(settings)


## True when the graphics setting allows sun shadows (the world asks when it builds a level).
func shadows_on() -> bool:
	return int(settings.get("quality", 2)) > 0


func camera_zoom() -> float:
	return float(CAMERA_ZOOM.get(settings.get("camera", "normal"), 1.0))


# ---------------------------------------------------------------- screen fades, FPS counter and button bounce

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(0.04, 0.03, 0.08, 0.0)
	_fade.size = Vector2(1280, 720)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)
	_fps_label = Label.new()
	_fps_label.position = Vector2(1170, 2)
	_fps_label.size = Vector2(106, 24)
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_font_override("font", font_body)
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 6)
	_fps_label.visible = false
	layer.add_child(_fps_label)


func _process(_delta: float) -> void:
	if _fps_label and _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()


## Fades to black, swaps scene, and fades back in.
func change_scene(path: String) -> void:
	if _fade and _fade.mouse_filter == Control.MOUSE_FILTER_STOP:
		return  # already on its way
	if _fade == null:
		get_tree().change_scene_to_file(path)
		return
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.22)
	tw.tween_callback(func() -> void:
		get_tree().paused = false
		get_tree().change_scene_to_file(path))
	tw.tween_interval(0.08)
	tw.tween_property(_fade, "color:a", 0.0, 0.3)
	tw.tween_callback(func() -> void: _fade.mouse_filter = Control.MOUSE_FILTER_IGNORE)


func reload_scene() -> void:
	change_scene(get_tree().current_scene.scene_file_path)


func _on_focus_changed(c: Control) -> void:
	## A little bounce on whatever button the player moves to
	if not c is Button or not c.is_visible_in_tree():
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2.ONE * 1.06, 0.07)
	tw.tween_property(c, "scale", Vector2.ONE, 0.12)


# ---------------------------------------------------------------- progress and unlocks

func total_stars() -> int:
	## Stars from the levels only (events and other modes have their own records)
	var n := 0
	for i in Levels.count():
		n += int(best.get(Levels.get_level(i).id, {}).get("stars", 0))
	return n


func level_unlocked(i: int) -> bool:
	return total_stars() >= int(Levels.get_level(i).stars_needed)


func level_stars(i: int) -> int:
	var id: String = Levels.get_level(i).id
	return int(best.get(id, {}).get("stars", 0))


func stat_value(key: String) -> int:
	if key == "stars":
		return total_stars()
	if key == "rank":
		return rank()
	if key == "collectibles":
		return collectible_count()
	return int(stats.get(key, 0))


# ---------------------------------------------------------------- career, depot and modes

func rank() -> int:
	return Career.rank_for(xp)


func gadget_uses(id: String) -> int:
	for g in Career.GADGETS:
		if g.id == id:
			if rank() < int(g.rank):
				return 0
			return int(g.uses) + upgrade_level("belt") + (1 if rank() >= 4 else 0)
	return 0


func upgrade_level(id: String) -> int:
	return int(upgrades.get(id, 0))


func upgrade_cost(id: String) -> int:
	var u := Career.upgrade(id)
	var lvl := upgrade_level(id)
	if u.is_empty() or lvl >= u.costs.size():
		return -1
	return int(u.costs[lvl])


func buy_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0 or wages < cost:
		return false
	wages -= cost
	upgrades[id] = upgrade_level(id) + 1
	save_game()
	return true


func buy_weapon(id: String) -> bool:
	var w := Career.weapon(id)
	if id in weapons_owned or wages < int(w.cost):
		return false
	wages -= int(w.cost)
	weapons_owned.append(id)
	weapon = id
	save_game()
	return true


func collectible_count() -> int:
	var n := 0
	for k in collectibles:
		n += (collectibles[k] as Array).size()
	return n


func event_unlocked(e: Dictionary) -> bool:
	return total_stars() >= int(e.stars_needed)


## The level definition for the shift about to be played: a level, or an event built on one.
func play_level() -> Dictionary:
	if mode == "event" and current_event != "":
		var e := Career.event(current_event)
		var lv: Dictionary = Levels.get_level(Levels.index_of(e.base)).duplicate(true)
		for k in e.overrides:
			lv[k] = e.overrides[k]
		lv.id = e.id
		lv.name = e.name
		lv.blurb = e.blurb
		lv.event = e.id
		return lv
	return Levels.get_level(current_level)


func best_time_medal(level_id: String, shift_time: float) -> int:
	## 0 none, 1 bronze, 2 silver, 3 gold: how quickly the quota was met
	if not best_times.has(level_id):
		return 0
	var frac := float(best_times[level_id]) / shift_time
	if frac <= 0.45:
		return 3
	if frac <= 0.65:
		return 2
	if frac <= 0.85:
		return 1
	return 0


func board(id: String) -> Array:
	return boards.get(id, [])


func board_qualifies(id: String, score: int) -> bool:
	if score <= 0:
		return false
	var b := board(id)
	return b.size() < BOARD_SIZE or score > int(b[-1].score)


func board_add(id: String, entry: Dictionary) -> int:
	var b: Array = board(id).duplicate()
	var pos := b.size()
	for i in b.size():
		if int(entry.score) > int(b[i].score):
			pos = i
			break
	b.insert(pos, entry)
	if b.size() > BOARD_SIZE:
		b.resize(BOARD_SIZE)
	boards[id] = b
	save_game()
	return pos if pos < BOARD_SIZE else -1


# ---------------------------------------------------------------- challenges

func _refresh_challenges() -> void:
	if challenge_state.get("day", "") != Challenges.day_key():
		challenge_state.day = Challenges.day_key()
		challenge_state.daily_done = []
	if challenge_state.get("week", "") != Challenges.week_key():
		challenge_state.week = Challenges.week_key()
		challenge_state.weekly_prog = {}
		challenge_state.weekly_done = []


func daily_challenges() -> Array:
	_refresh_challenges()
	var out := []
	for c in Challenges.daily(rank()):
		c.done = c.id in challenge_state.daily_done
		out.append(c)
	return out


func weekly_challenges() -> Array:
	_refresh_challenges()
	var out := []
	for c in Challenges.weekly():
		c.done = c.id in challenge_state.weekly_done
		c.progress = int(challenge_state.weekly_prog.get(c.id, 0))
		out.append(c)
	return out


## Checks a finished shift against today's and this week's challenges. Returns the ones just completed.
func check_challenges(r: Dictionary) -> Array:
	var done := []
	for c in daily_challenges():
		if not c.done and Challenges.shift_value(c, r) >= int(c.n):
			challenge_state.daily_done.append(c.id)
			done.append({"text": c.text, "wages": Challenges.DAILY_REWARD.wages, "xp": Challenges.DAILY_REWARD.xp})
	for c in weekly_challenges():
		if c.done:
			continue
		var v := Challenges.shift_value(c, r)
		var prog: int = maxi(c.progress, v) if c.max else c.progress + v
		challenge_state.weekly_prog[c.id] = prog
		if prog >= int(c.n):
			challenge_state.weekly_done.append(c.id)
			done.append({"text": c.text, "wages": Challenges.WEEKLY_REWARD.wages, "xp": Challenges.WEEKLY_REWARD.xp, "weekly": true})
	return done


func item_unlocked(item: Dictionary) -> bool:
	if not item.has("req"):
		return true
	var r: Array = item.req
	if r[0] == "level":
		return int(best.get(r[1], {}).get("stars", 0)) >= 1
	return stat_value(r[0]) >= int(r[1])


func item_progress(item: Dictionary) -> String:
	if not item.has("req") or item_unlocked(item):
		return ""
	var r: Array = item.req
	if r[0] == "level":
		return ""
	return "%d / %d" % [mini(stat_value(r[0]), int(r[1])), int(r[1])]


func unlocked_keys() -> Array:
	var keys := []
	for slot in Catalogue.SLOTS:
		for it in Catalogue.items(slot):
			if item_unlocked(it):
				keys.append("%s:%s" % [slot, it.id])
	for i in Levels.count():
		if level_unlocked(i):
			keys.append("level:%s" % Levels.get_level(i).id)
	for e in Career.EVENTS:
		if event_unlocked(e):
			keys.append("event:%s" % e.id)
	for r in rank() + 1:
		keys.append("rank:%d" % r)
	return keys


## Returns display names of things unlocked since the last call, and marks them as announced.
func take_new_unlocks() -> Array:
	var fresh := []
	var names := Levels.names()
	for key in unlocked_keys():
		if key in announced:
			continue
		announced.append(key)
		var parts: PackedStringArray = key.split(":")
		if parts[0] == "level":
			fresh.append("New level: %s" % names.get(parts[1], parts[1]))
		elif parts[0] == "event":
			fresh.append("Special event: %s" % Career.event(parts[1]).name)
		elif parts[0] == "rank":
			var rk: Dictionary = Career.RANKS[int(parts[1])]
			fresh.append("PROMOTED to %s! %s" % [rk.name, rk.perk])
		else:
			var it := Catalogue.find(parts[0], parts[1])
			fresh.append("%s: %s" % [Catalogue.SLOT_NAMES[parts[0]], it.name])
	return fresh


func record_shift(level_id: String, score: int, stars: int, shift_stats: Dictionary, keep_best := true) -> void:
	for k in shift_stats:
		if k in STAT_KEYS:
			stats[k] = int(stats.get(k, 0)) + int(shift_stats[k])
	stats.shifts = int(stats.get("shifts", 0)) + 1
	if keep_best:
		var prev: Dictionary = best.get(level_id, {"stars": 0, "score": -999999})
		best[level_id] = {"stars": maxi(int(prev.stars), stars), "score": maxi(int(prev.score), score)}
	save_game()


## Pays the warden for a shift. Returns {"wages", "xp", "rank_before", "rank_after"}.
func pay(score: int, bonus_wages := 0, bonus_xp := 0) -> Dictionary:
	var before := rank()
	var w := maxi(score, 0) / 10 + bonus_wages
	var x := maxi(score, 0) + bonus_xp
	wages += w
	xp += x
	save_game()
	return {"wages": w, "xp": x, "rank_before": before, "rank_after": rank()}


func outfit_item(slot: String) -> Dictionary:
	return Catalogue.find(slot, outfit.get(slot, ""))


# ---------------------------------------------------------------- save / load

func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "stats", stats)
	cfg.set_value("progress", "best", best)
	cfg.set_value("progress", "announced", announced)
	cfg.set_value("player", "outfit", outfit)
	cfg.set_value("player", "outfit2", outfit2)
	cfg.set_value("player", "settings", settings)
	cfg.set_value("career", "xp", xp)
	cfg.set_value("career", "wages", wages)
	cfg.set_value("career", "upgrades", upgrades)
	cfg.set_value("career", "weapons_owned", weapons_owned)
	cfg.set_value("career", "weapon", weapon)
	cfg.set_value("career", "weapon2", weapon2)
	cfg.set_value("records", "boards", boards)
	cfg.set_value("records", "best_times", best_times)
	cfg.set_value("records", "collectibles", collectibles)
	cfg.set_value("records", "challenges", challenge_state)
	cfg.set_value("records", "initials", initials)
	cfg.set_value("player", "profile_name", profile_name)
	cfg.set_value("player", "profile2_name", profile2_name)
	cfg.set_value("records", "endless_best", endless_best)
	cfg.save(SAVE_PATH)


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var s: Dictionary = cfg.get_value("progress", "stats", {})
	for k in s:
		stats[k] = s[k]
	best = cfg.get_value("progress", "best", {})
	announced = cfg.get_value("progress", "announced", [])
	var o: Dictionary = cfg.get_value("player", "outfit", {})
	for k in o:
		outfit[k] = o[k]
	var o2: Dictionary = cfg.get_value("player", "outfit2", {})
	for k in o2:
		outfit2[k] = o2[k]
	var st: Dictionary = cfg.get_value("player", "settings", {})
	for k in st:
		settings[k] = st[k]
	xp = int(cfg.get_value("career", "xp", 0))
	wages = int(cfg.get_value("career", "wages", 0))
	upgrades = cfg.get_value("career", "upgrades", {})
	weapons_owned = cfg.get_value("career", "weapons_owned", ["fists"])
	weapon = cfg.get_value("career", "weapon", "fists")
	weapon2 = cfg.get_value("career", "weapon2", "fists")
	boards = cfg.get_value("records", "boards", {})
	best_times = cfg.get_value("records", "best_times", {})
	collectibles = cfg.get_value("records", "collectibles", {})
	challenge_state = cfg.get_value("records", "challenges", {})
	initials = cfg.get_value("records", "initials", "AAA")
	profile_name = cfg.get_value("player", "profile_name", "")
	profile2_name = cfg.get_value("player", "profile2_name", "")
	endless_best = cfg.get_value("records", "endless_best", {})


## Wipes all progress (the Reset Progress setting). Settings and profile names are kept.
func reset_progress() -> void:
	var keep := settings.duplicate()
	var n1 := profile_name
	var n2 := profile2_name
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	for k in STAT_KEYS:
		stats[k] = 0
	best = {}
	announced = []
	xp = 0
	wages = 0
	upgrades = {}
	weapons_owned = ["fists"]
	weapon = "fists"
	weapon2 = "fists"
	boards = {}
	best_times = {}
	collectibles = {}
	challenge_state = {}
	endless_best = {}
	settings = keep
	profile_name = n1
	profile2_name = n2
	announced = unlocked_keys()
	save_game()
