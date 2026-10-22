extends Control
## Arcade-style initials entry for the high score boards. Up / down changes the letter,
## left / right moves between letters, accept saves.

signal done(place: int)

const LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 "

var main
var board_id := ""
var initials := "AAA"
var pos := 0
var finished := false
var label: Label
var help: Label


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(640, 92)
	while initials.length() < 3:
		initials += "A"
	initials = initials.substr(0, 3)
	var title := Label.new()
	title.text = "NEW HIGH SCORE! Enter your initials"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(640, 30)
	add_child(title)
	label = Label.new()
	label.add_theme_font_override("font", Game.font_title)
	label.add_theme_font_size_override("font_size", 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, 28)
	label.size = Vector2(640, 46)
	add_child(label)
	help = Label.new()
	help.add_theme_font_size_override("font_size", 16)
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.position = Vector2(0, 72)
	help.size = Vector2(640, 22)
	help.text = "Up / down: letter     Left / right: move     Select: save"
	add_child(help)
	_refresh()


func _refresh() -> void:
	var t := ""
	for i in 3:
		var ch := initials[i] if initials[i] != " " else "_"
		t += ("[%s]" % ch) if i == pos and not finished else (" %s " % ch)
	label.text = t


func _gui_input(event: InputEvent) -> void:
	if finished:
		return
	var changed := true
	if event.is_action_pressed("ui_up"):
		_shift(1)
	elif event.is_action_pressed("ui_down"):
		_shift(-1)
	elif event.is_action_pressed("ui_left"):
		pos = maxi(pos - 1, 0)
	elif event.is_action_pressed("ui_right"):
		pos = mini(pos + 1, 2)
	elif event.is_action_pressed("ui_accept"):
		_save()
	elif event is InputEventKey and event.pressed and event.unicode > 0:
		var ch := String.chr(event.unicode).to_upper()
		if LETTERS.contains(ch):
			initials = initials.substr(0, pos) + ch + initials.substr(pos + 1)
			pos = mini(pos + 1, 2)
		else:
			changed = false
	else:
		changed = false
	if changed:
		accept_event()
		Audio.sfx("ui_move")
		_refresh()


func _shift(dir: int) -> void:
	var i := LETTERS.find(initials[pos])
	i = (i + dir + LETTERS.length()) % LETTERS.length()
	initials = initials.substr(0, pos) + LETTERS[i] + initials.substr(pos + 1)


func _save() -> void:
	finished = true
	var place: int = main.submit_score(board_id, initials)
	help.text = "Saved! You're number %d on the board." % (place + 1) if place >= 0 else "Saved!"
	Audio.sfx("ui_select")
	Audio.sting("unlock")
	focus_mode = Control.FOCUS_NONE
	done.emit(place)
