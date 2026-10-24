extends CanvasLayer
## On-screen touch controls for phones and tablets: a floating joystick on the left half of the
## screen, action buttons on the right and a pause button at the top. Only made when Game.touch_ui
## is on, and hidden while a controller or keyboard is in use. Laid out for the 1280x720 base
## resolution and pulled in from the edges by the phone's safe area (notches, rounded corners).

const Prompt := preload("res://scripts/prompt.gd")
const STICK_RADIUS := 105.0
const KNOB_RADIUS := 46.0
const STICK_HOME := Vector2(200, 540)
const DEAD_ZONE := 0.18
const RUN_PAST := 1.12  # pushing the stick this far past its ring also sprints
const PAUSE_POS := Vector2(884, 40)
const PAUSE_RADIUS := 32.0

## id, action, label, centre, radius (colours come from Prompt.TOUCH_COLORS)
const BUTTONS := [
	["ticket", "ticket", "TICKET", Vector2(1150, 596), 74.0],
	["punch", "punch", "PUNCH", Vector2(1004, 636), 52.0],
	["whistle", "whistle", "WHISTLE", Vector2(1024, 492), 50.0],
	["dive", "dive", "DIVE", Vector2(1166, 436), 50.0],
	["sprint", "sprint", "RUN", Vector2(870, 654), 46.0],
	["gadget", "gadget", "GADGET", Vector2(1070, 360), 42.0],
	["gadget_next", "gadget_next", "SWAP", Vector2(1182, 316), 34.0],
]

var main
var root: Control
var buttons := {}  # id -> {"action", "label", "centre", "radius", "finger", "visible"}
var stick_finger := -1
var stick_base := STICK_HOME
var stick_vec := Vector2.ZERO
var pause_finger := -1
var running := false  # sprint currently held, by the button or the stick
var inset := {"left": 0.0, "right": 0.0, "top": 0.0, "bottom": 0.0}
var _font: Font


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = Game.font_body
	root = Control.new()
	root.size = Vector2(1280, 720)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.draw.connect(_draw_controls)
	add_child(root)
	for b in BUTTONS:
		buttons[b[0]] = {"action": b[1], "label": b[2], "centre": b[3], "radius": b[4], "finger": -1, "visible": true}
	var gadgets: Array = main.players[0].gadgets if main and not main.players.is_empty() else []
	buttons.gadget.visible = not gadgets.is_empty()
	buttons.gadget_next.visible = gadgets.size() > 1
	_update_safe_area()
	get_viewport().size_changed.connect(_update_safe_area)
	Game.device_changed.connect(func(_p: bool) -> void: _sync_visible())
	_sync_visible()


func _active() -> bool:
	return main != null and main.state == "playing" and not get_tree().paused and Game.using_touch


func _sync_visible() -> void:
	var show: bool = Game.using_touch and main != null and main.state != "results" and not get_tree().paused
	if root.visible != show:
		root.visible = show
		if not show:
			_release_all()
	root.queue_redraw()


func _process(_delta: float) -> void:
	_sync_visible()
	if not _active() and (stick_finger >= 0 or running):
		_release_all()


## The safe area (away from notches and rounded corners) mapped into the 1280x720 canvas.
func _update_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	inset = {"left": 0.0, "right": 0.0, "top": 0.0, "bottom": 0.0}
	if safe.size.x <= 0 or screen.x <= 0:
		return
	var xf := get_viewport().get_final_transform().affine_inverse()
	var win_pos := Vector2(DisplayServer.window_get_position())
	var tl: Vector2 = xf * (Vector2(safe.position) - win_pos)
	var br: Vector2 = xf * (Vector2(safe.end) - win_pos)
	inset.left = clampf(tl.x, 0.0, 120.0)
	inset.top = clampf(tl.y, 0.0, 80.0)
	inset.right = clampf(1280.0 - br.x, 0.0, 120.0)
	inset.bottom = clampf(720.0 - br.y, 0.0, 80.0)
	root.queue_redraw()


func _shift(p: Vector2) -> Vector2:
	# Buttons on the right move in by the right inset, the stick by the left one
	if p == PAUSE_POS:
		return p + Vector2(0, inset.top)
	if p.x > 640.0:
		p.x -= inset.right
	else:
		p.x += inset.left
	return p + Vector2(0, -inset.bottom if p.y > 360.0 else inset.top)


func _pause_centre() -> Vector2:
	return _shift(PAUSE_POS)


# ---------------------------------------------------------------- input

func _input(event: InputEvent) -> void:
	if not root.visible:
		return
	if event is InputEventScreenTouch:
		var pos: Vector2 = event.position
		if event.pressed:
			if _touch_down(event.index, pos):
				get_viewport().set_input_as_handled()
		elif _touch_up(event.index):
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == stick_finger:
			_move_stick(event.position)
			get_viewport().set_input_as_handled()
		else:
			# Sliding a thumb off one button onto another (say ticket to dive) works too
			for id in buttons:
				var b: Dictionary = buttons[id]
				if b.finger == event.index and not _hit(b, event.position, 1.35):
					_set_button(id, -1)
			for id in buttons:
				var b: Dictionary = buttons[id]
				if b.finger < 0 and b.visible and _hit(b, event.position) and not _finger_on_button(event.index):
					_set_button(id, event.index)


func _touch_down(finger: int, pos: Vector2) -> bool:
	if pos.distance_to(_pause_centre()) < PAUSE_RADIUS * 1.5:
		if main.state == "playing":
			pause_finger = finger
			Game.send_action("pause")
			_buzz()
		return true
	if not _active():
		return false
	for id in buttons:
		var b: Dictionary = buttons[id]
		if b.visible and _hit(b, pos):
			_set_button(id, finger)
			return true
	# Anywhere else on the left of the screen (below the timer and stamina) starts the stick under the thumb
	if stick_finger < 0 and pos.x < 620.0 and pos.y > 210.0:
		stick_finger = finger
		stick_base = pos
		_move_stick(pos)
		return true
	return false


func _touch_up(finger: int) -> bool:
	if finger == pause_finger:
		pause_finger = -1
		return true
	if finger == stick_finger:
		stick_finger = -1
		stick_base = _shift(STICK_HOME)
		stick_vec = Vector2.ZERO
		_apply_stick()
		return true
	for id in buttons:
		if buttons[id].finger == finger:
			_set_button(id, -1)
			return true
	return false


func _finger_on_button(finger: int) -> bool:
	for id in buttons:
		if buttons[id].finger == finger:
			return true
	return false


func _hit(b: Dictionary, pos: Vector2, scale := 1.15) -> bool:
	return pos.distance_to(_shift(b.centre)) < float(b.radius) * scale


func _set_button(id: String, finger: int) -> void:
	var b: Dictionary = buttons[id]
	var was := int(b.finger) >= 0
	b.finger = finger
	var now := finger >= 0
	if was == now:
		return
	if id == "sprint":
		_update_run()
	elif now:
		_press(b.action)
		_buzz()
	else:
		_release(b.action)
	root.queue_redraw()


func _move_stick(pos: Vector2) -> void:
	var d := pos - stick_base
	# The base follows a thumb that wanders too far, so the stick never runs out of travel
	var limit := STICK_RADIUS * 1.4
	if d.length() > limit:
		stick_base = pos - d.normalized() * limit
		d = pos - stick_base
	stick_vec = d / STICK_RADIUS
	_apply_stick()


func _apply_stick() -> void:
	var v := stick_vec.limit_length(1.0)
	if v.length() < DEAD_ZONE:
		v = Vector2.ZERO
	else:
		v = v.normalized() * inverse_lerp(DEAD_ZONE, 1.0, v.length())
	_axis("move_left", maxf(-v.x, 0.0))
	_axis("move_right", maxf(v.x, 0.0))
	_axis("move_up", maxf(-v.y, 0.0))
	_axis("move_down", maxf(v.y, 0.0))
	_update_run()
	root.queue_redraw()


func _update_run() -> void:
	var want: bool = buttons.sprint.finger >= 0 or (stick_finger >= 0 and stick_vec.length() > RUN_PAST)
	if want != running:
		running = want
		if want:
			_press("sprint")
		else:
			_release("sprint")


func _release_all() -> void:
	stick_finger = -1
	pause_finger = -1
	stick_vec = Vector2.ZERO
	stick_base = _shift(STICK_HOME)
	for act in ["move_left", "move_right", "move_up", "move_down"]:
		_axis(act, 0.0)
	for id in buttons:
		if buttons[id].finger >= 0:
			buttons[id].finger = -1
			if id != "sprint":
				_release(buttons[id].action)
	if running:
		running = false
		_release("sprint")
	root.queue_redraw()


## In two player games the touch screen drives player 1, whose actions are called p1_*
func _names(action: String) -> Array:
	var out := [action]
	if InputMap.has_action("p1_" + action):
		out.append("p1_" + action)
	return out


func _press(action: String) -> void:
	for a in _names(action):
		Input.action_press(a)


func _release(action: String) -> void:
	for a in _names(action):
		Input.action_release(a)


func _axis(action: String, strength: float) -> void:
	for a in _names(action):
		if strength > 0.0:
			Input.action_press(a, strength)
		else:
			Input.action_release(a)


func _buzz() -> void:
	if Game.is_mobile:
		Input.vibrate_handheld(18)


# ---------------------------------------------------------------- drawing

func _draw_controls() -> void:
	# Joystick: a ring where the thumb is (or its resting place) and a knob
	var base := stick_base if stick_finger >= 0 else _shift(STICK_HOME)
	var alpha := 0.55 if stick_finger >= 0 else 0.3
	root.draw_circle(base, STICK_RADIUS, Color(0.05, 0.05, 0.1, alpha * 0.6))
	root.draw_arc(base, STICK_RADIUS, 0, TAU, 48, Color(1, 1, 1, alpha), 4.0, true)
	var knob := base + stick_vec.limit_length(1.0) * STICK_RADIUS
	var knob_col := Color(0.55, 0.3, 0.85, 0.85) if running else Color(1, 0.86, 0.15, 0.8 if stick_finger >= 0 else 0.45)
	root.draw_circle(knob, KNOB_RADIUS, knob_col)
	root.draw_arc(knob, KNOB_RADIUS, 0, TAU, 32, Color(0.1, 0.08, 0.12, 0.8), 3.0, true)

	for id in buttons:
		var b: Dictionary = buttons[id]
		if not b.visible:
			continue
		var c := _shift(b.centre)
		var r: float = b.radius
		var down: bool = b.finger >= 0 or (id == "sprint" and running)
		var col: Color = Prompt.TOUCH_COLORS.get(id, Color(0.3, 0.3, 0.35))
		root.draw_circle(c + Vector2(0, 4), r, Color(0, 0, 0, 0.3))
		root.draw_circle(c, r * (0.92 if down else 1.0), Color(col.r, col.g, col.b, 0.92 if down else 0.62))
		root.draw_arc(c, r * (0.92 if down else 1.0), 0, TAU, 40, Color(1, 1, 1, 0.85), 3.0, true)
		_text(b.label, c, int(clampf(r * 0.38, 15, 28)))

	if main and main.state == "playing":
		var pc := _pause_centre()
		root.draw_circle(pc, PAUSE_RADIUS, Color(0.05, 0.05, 0.1, 0.6))
		root.draw_arc(pc, PAUSE_RADIUS, 0, TAU, 32, Color(1, 1, 1, 0.8), 3.0, true)
		for x in [-7.0, 7.0]:
			root.draw_rect(Rect2(pc.x + x - 4, pc.y - 12, 8, 24), Color.WHITE)


func _text(t: String, centre: Vector2, fs: int) -> void:
	var ts := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var p := Vector2(centre.x - ts.x / 2.0, centre.y + fs * 0.36)
	root.draw_string_outline(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.06, 0.05, 0.12, 0.9))
	root.draw_string(_font, p, t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
