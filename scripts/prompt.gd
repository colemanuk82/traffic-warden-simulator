extends Control
## An on-screen button prompt. Shows Xbox controller glyphs when a pad is in use, key caps otherwise.

const PAD := {
	"ticket": "A", "whistle": "X", "dive": "B", "punch": "Y", "sprint": "LB", "pause": "MENU", "move": "LS", "gadget": "RB", "gadget_next": "VIEW",
	"ui_accept": "A", "ui_cancel": "B", "tab_prev": "LB", "tab_next": "RB", "ui_lr": "DPAD", "ui_ud": "DPAD",
}
const KEYS := {
	"ticket": "E", "whistle": "Space", "dive": "Ctrl", "punch": "F", "sprint": "Shift", "pause": "Esc", "move": "WASD", "gadget": "G", "gadget_next": "Tab",
	"ui_accept": "Enter", "ui_cancel": "Esc", "tab_prev": "Q", "tab_next": "R", "ui_lr": "< >", "ui_ud": "W / S",
}
const FACE_COLORS := {
	"A": Color(0.38, 0.78, 0.2), "B": Color(0.92, 0.25, 0.2), "X": Color(0.2, 0.5, 1.0), "Y": Color(1.0, 0.78, 0.1),
}

var action := "ticket"
var glyph_size := 34.0
var force_pad := -1  # -1 follow the last device, 0 keyboard, 1 pad


static func make(act: String, text: String, size := 34.0, font_size := 24) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g = load("res://scripts/prompt.gd").new()
	g.action = act
	g.glyph_size = size
	box.add_child(g)
	if text != "":
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", font_size)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(l)
	return box


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Game.device_changed.connect(func(_p: bool) -> void: _refresh())
	_refresh()


func _pad() -> bool:
	return Game.using_pad if force_pad < 0 else force_pad == 1


func _refresh() -> void:
	var w := glyph_size
	if not _pad():
		var label: String = KEYS.get(action, action)
		w = maxf(glyph_size, Game.font_body.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(glyph_size * 0.5)).x + 16.0)
	elif PAD.get(action, "") in ["LB", "RB"]:
		w = glyph_size * 1.6
	custom_minimum_size = Vector2(w, glyph_size)
	size = custom_minimum_size
	queue_redraw()


func _draw() -> void:
	var s := glyph_size
	var font: Font = Game.font_body
	var dark := Color(0.12, 0.12, 0.16)
	if not _pad():
		var label: String = KEYS.get(action, action)
		var r := Rect2(Vector2.ZERO, size)
		_round_rect(Rect2(r.position + Vector2(0, 3), r.size), Color(0.35, 0.35, 0.42))
		_round_rect(Rect2(r.position, r.size - Vector2(0, 3)), Color(0.96, 0.96, 0.98))
		_text(label, r.size / 2.0 - Vector2(0, 1.5), int(s * 0.5), dark, font)
		return
	var g: String = PAD.get(action, "A")
	var c := Vector2(size.x / 2.0, s / 2.0)
	match g:
		"A", "B", "X", "Y":
			draw_circle(c + Vector2(0, 2), s / 2.0, Color(0, 0, 0, 0.35))
			draw_circle(c, s / 2.0, dark)
			draw_arc(c, s / 2.0 - 1.5, 0, TAU, 32, FACE_COLORS[g].darkened(0.2), 2.0, true)
			_text(g, c, int(s * 0.6), FACE_COLORS[g], font)
		"LB", "RB":
			_round_rect(Rect2(Vector2(0, s * 0.15), Vector2(size.x, s * 0.7)), dark)
			_text(g, c, int(s * 0.45), Color.WHITE, font)
		"MENU":
			draw_circle(c, s / 2.0, dark)
			for i in 3:
				var y := c.y - s * 0.16 + i * s * 0.16
				draw_line(Vector2(c.x - s * 0.2, y), Vector2(c.x + s * 0.2, y), Color.WHITE, 2.5)
		"VIEW":
			draw_circle(c, s / 2.0, dark)
			var q := s * 0.2
			draw_rect(Rect2(c.x - q * 1.1, c.y - q * 0.9, q * 1.3, q * 1.1), Color.WHITE, false, 2.0)
			draw_rect(Rect2(c.x - q * 0.2, c.y - q * 0.2, q * 1.3, q * 1.1), Color.WHITE, false, 2.0)
		"LS":
			draw_circle(c, s / 2.0, dark)
			draw_arc(c, s * 0.34, 0, TAU, 32, Color(0.6, 0.6, 0.7), 2.5, true)
			_text("L", c, int(s * 0.45), Color.WHITE, font)
		"DPAD":
			var t := s * 0.3
			draw_rect(Rect2(c.x - t / 2.0, c.y - s / 2.0, t, s), dark)
			draw_rect(Rect2(c.x - s / 2.0, c.y - t / 2.0, s, t), dark)
			draw_circle(c, t * 0.25, Color(0.5, 0.5, 0.6))


func _round_rect(r: Rect2, color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(int(minf(r.size.y, r.size.x) * 0.25))
	draw_style_box(sb, r)


func _text(t: String, centre: Vector2, fs: int, color: Color, font: Font) -> void:
	var ts := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2(centre.x - ts.x / 2.0, centre.y + fs * 0.36), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)
