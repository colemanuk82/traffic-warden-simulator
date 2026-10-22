extends Control
## Player name entry: type on the keyboard, or pick letters from the on-screen keys with a controller.
## Used for the player profiles (asked once, then used on every score board).

signal submitted(name: String)

const MAX_LEN := 12
const ROWS := ["ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ0123", "456789-!.'"]

var title_text := "WHO'S ON DUTY?"
var hint_text := "Type your name, or pick letters with the controller."
var value := ""
var name_label: Label
var title_label: Label
var keys: Array[Button] = []
var done_button: Button
var blink := 0.0


func _ready() -> void:
	size = Vector2(760, 470)
	var panel := PanelContainer.new()
	panel.size = size
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var title := Label.new()
	title_label = title
	title.text = title_text
	title.add_theme_font_override("font", Game.font_title)
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", Color(1, 0.86, 0.15))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var hint := Label.new()
	hint.text = hint_text
	hint.add_theme_font_size_override("font_size", 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	name_label = Label.new()
	name_label.add_theme_font_override("font", Game.font_title)
	name_label.add_theme_font_size_override("font_size", 52)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.custom_minimum_size = Vector2(700, 64)
	v.add_child(name_label)
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	var centre := CenterContainer.new()
	centre.add_child(grid)
	v.add_child(centre)
	for row in ROWS:
		for ch in row:
			var b := _key(ch, Vector2(62, 44))
			b.pressed.connect(_type.bind(ch))
			grid.add_child(b)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_theme_constant_override("separation", 10)
	v.add_child(bottom)
	var space := _key("SPACE", Vector2(200, 48))
	space.pressed.connect(_type.bind(" "))
	bottom.add_child(space)
	var del := _key("DELETE", Vector2(200, 48))
	del.pressed.connect(_delete)
	bottom.add_child(del)
	done_button = _key("DONE", Vector2(200, 48))
	done_button.pressed.connect(_done)
	bottom.add_child(done_button)
	_refresh()


func _key(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 24)
	b.focus_entered.connect(func() -> void: Audio.sfx("ui_move", 1.0, 0.5))
	b.mouse_entered.connect(func() -> void: b.grab_focus())
	keys.append(b)
	return b


func set_title(text: String) -> void:
	title_text = text
	if title_label:
		title_label.text = text


func open(start: String) -> void:
	value = start.substr(0, MAX_LEN)
	_refresh()
	await get_tree().process_frame
	(done_button if value != "" else keys[0]).grab_focus()


func _process(delta: float) -> void:
	blink += delta
	_refresh()


func _refresh() -> void:
	if name_label:
		name_label.text = value + ("_" if fmod(blink, 1.0) < 0.6 and value.length() < MAX_LEN else " ")


func _type(ch: String) -> void:
	if value.length() >= MAX_LEN or (ch == " " and (value == "" or value.ends_with(" "))):
		Audio.sfx("wrong", 1.0, 0.5)
		return
	value += ch
	Audio.sfx("tick")


func _delete() -> void:
	if value.length() > 0:
		value = value.substr(0, value.length() - 1)
		Audio.sfx("ui_back", 1.0, 0.6)


func _done() -> void:
	var n := value.strip_edges()
	if n == "":
		Audio.sfx("wrong", 1.0, 0.6)
		return
	Audio.sfx("ui_select")
	submitted.emit(n)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed:
		return
	var k: InputEventKey = event
	if k.keycode == KEY_BACKSPACE:
		_delete()
	elif k.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		_done()
	elif k.unicode > 0 and k.keycode != KEY_ESCAPE:
		var ch := String.chr(k.unicode).to_upper()
		var allowed := ch == " "
		for row in ROWS:
			if row.contains(ch):
				allowed = true
		if not allowed:
			return
		_type(ch)
	else:
		return
	get_viewport().set_input_as_handled()
