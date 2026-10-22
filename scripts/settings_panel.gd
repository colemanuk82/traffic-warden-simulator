extends Control
## The settings screen, shared by the main menu and the pause menu.
## Sound on the left, display and gameplay on the right. Every change saves straight away.

signal closed

const YELLOW := Color(1.0, 0.86, 0.15)

var allow_reset := false  # only the main menu offers Reset Progress
var first: Control
var reset_button: Button
var reset_armed := false


func _ready() -> void:
	size = Vector2(1200, 520)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	add_child(cols)
	var left := _column(cols, "SOUND")
	for row in [["Master volume", "master"], ["Music", "music"], ["Effects", "sfx"], ["Voices", "voice"], ["Car stereos", "stereo"]]:
		_slider(left, row[0], row[1])
	_choice(left, "Soundtrack", "soundtrack", ["classic", "rock", "mix"], ["Classic", "Rock & Metal", "Shuffle all"])
	var right := _column(cols, "DISPLAY & GAMEPLAY")
	_toggle(right, "Fullscreen", "fullscreen")
	_toggle(right, "V-Sync", "vsync")
	_choice(right, "Frame rate limit", "fps_cap", [0, 30, 60, 120, 144], ["Unlimited", "30", "60", "120", "144"])
	_choice(right, "Graphics", "quality", [0, 1, 2], Game.QUALITY_NAMES)
	_toggle(right, "Show FPS", "show_fps")
	_toggle(right, "Screen shake", "shake")
	_choice(right, "Camera", "camera", ["close", "normal", "far"], ["Close", "Normal", "Far"])
	var bottom := HBoxContainer.new()
	bottom.position = Vector2(0, 458)
	bottom.add_theme_constant_override("separation", 16)
	add_child(bottom)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(220, 52)
	done.pressed.connect(func() -> void:
		Audio.sfx("ui_back")
		closed.emit())
	bottom.add_child(done)
	if allow_reset:
		reset_button = Button.new()
		reset_button.text = "Reset Progress"
		reset_button.custom_minimum_size = Vector2(300, 52)
		reset_button.pressed.connect(_on_reset)
		reset_button.focus_exited.connect(func() -> void:
			reset_armed = false
			reset_button.text = "Reset Progress")
		bottom.add_child(reset_button)


func open() -> void:
	reset_armed = false
	if reset_button:
		reset_button.text = "Reset Progress"
	await get_tree().process_frame
	if first:
		first.grab_focus()


func _on_reset() -> void:
	if not reset_armed:
		reset_armed = true
		reset_button.text = "Really? Press again"
		Audio.sfx("wrong", 1.0, 0.6)
		return
	reset_armed = false
	Game.reset_progress()
	reset_button.text = "Progress wiped"
	Audio.sfx("whoosh")


func _column(parent: Control, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(588, 440)
	parent.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var l := Label.new()
	l.text = title
	l.add_theme_font_override("font", Game.font_title)
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", YELLOW)
	v.add_child(l)
	return v


func _row(parent: Control, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	parent.add_child(h)
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(230, 44)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 24)
	h.add_child(l)
	return h


func _save() -> void:
	Game.apply_settings()
	Game.save_game()


func _slider(parent: Control, text: String, key: String) -> void:
	var h := _row(parent, text)
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = float(Game.settings.get(key, 1.0))
	s.custom_minimum_size = Vector2(240, 40)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pct := Label.new()
	pct.custom_minimum_size = Vector2(60, 40)
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pct.add_theme_font_size_override("font_size", 20)
	pct.text = "%d%%" % int(round(s.value * 100))
	s.value_changed.connect(func(val: float) -> void:
		Game.settings[key] = val
		pct.text = "%d%%" % int(round(val * 100))
		_save()
		Audio.sfx("tick", 1.0, 0.8))
	s.focus_entered.connect(func() -> void: Audio.sfx("ui_move", 1.0, 0.5))
	h.add_child(s)
	h.add_child(pct)
	if first == null:
		first = s


func _toggle(parent: Control, text: String, key: String) -> void:
	var h := _row(parent, text)
	var b := Button.new()
	b.custom_minimum_size = Vector2(200, 40)
	b.add_theme_font_size_override("font_size", 22)
	var show := func() -> void: b.text = "ON" if Game.settings.get(key, false) else "OFF"
	show.call()
	b.pressed.connect(func() -> void:
		Game.settings[key] = not Game.settings.get(key, false)
		show.call()
		_save()
		Audio.sfx("ui_select"))
	b.focus_entered.connect(func() -> void: Audio.sfx("ui_move", 1.0, 0.5))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	h.add_child(b)
	if first == null:
		first = b


## A setting with a few named options: left / right (or select) steps through them.
func _choice(parent: Control, text: String, key: String, values: Array, names: Array) -> void:
	var h := _row(parent, text)
	var b := Button.new()
	b.custom_minimum_size = Vector2(300, 40)
	b.add_theme_font_size_override("font_size", 22)
	var idx := func() -> int: return maxi(values.find(Game.settings.get(key, values[0])), 0)
	var show := func() -> void: b.text = "<  %s  >" % names[idx.call()]
	var step := func(dir: int) -> void:
		var i: int = (idx.call() + dir + values.size()) % values.size()
		Game.settings[key] = values[i]
		show.call()
		_save()
		Audio.sfx("ui_move", 1.0 + dir * 0.1)
	show.call()
	b.pressed.connect(func() -> void: step.call(1))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		if ev.is_action_pressed("ui_left"):
			step.call(-1)
			b.accept_event()
		elif ev.is_action_pressed("ui_right"):
			step.call(1)
			b.accept_event()
		elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			step.call(-1)
			b.accept_event())
	b.focus_entered.connect(func() -> void: Audio.sfx("ui_move", 1.0, 0.5))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	h.add_child(b)
	if first == null:
		first = b
