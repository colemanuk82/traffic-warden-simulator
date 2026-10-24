extends CanvasLayer
## Rampage mode's screen effects: the view goes a shade of red, cartoon red drips run down from the
## top of the screen, and a shaking RAMPAGE! title with a bar for the time left.

const DRIPS := 22

var main
var root: Control
var level := 0.0  # 0 hidden .. 1 fully on
var want := false
var left_frac := 0.0
var drips: Array = []  # {x, len, speed, w, wobble}
var t := 0.0
var title: Label


func _ready() -> void:
	layer = 0  # under the HUD
	root = Control.new()
	root.size = Vector2(1280, 720)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.draw.connect(_draw_fx)
	add_child(root)
	title = Label.new()
	title.text = "RAMPAGE!"
	title.add_theme_font_override("font", Game.font_title)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1, 0.15, 0.1))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.0, 0.0))
	title.add_theme_constant_override("outline_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(600, 80)
	title.position = Vector2(340, 136)
	title.pivot_offset = Vector2(300, 40)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)
	for i in DRIPS:
		drips.append(_new_drip(true))
	visible = false


func _new_drip(start := false) -> Dictionary:
	return {"x": randf_range(10, 1270), "len": randf_range(0, 120) if start else 0.0, "speed": randf_range(40, 140),
		"w": randf_range(7, 18), "max": randf_range(60, 330), "wobble": randf() * TAU}


func set_active(on: bool) -> void:
	want = on
	if on:
		visible = true


func _process(delta: float) -> void:
	level = move_toward(level, 1.0 if want else 0.0, delta * (3.0 if want else 1.5))
	if level <= 0.0 and not want:
		visible = false
		return
	t += delta
	for d in drips:
		d.len += d.speed * delta * (1.0 if d.len < d.max else 0.25)
		# Long drips eventually let go and a fresh one starts at the top
		if d.len > d.max + 60.0:
			d.merge(_new_drip(), true)
	var shake := 1.0 + 0.06 * sin(t * 22.0)
	title.scale = Vector2(shake, shake)
	title.rotation = sin(t * 9.0) * 0.04
	title.modulate.a = level
	root.queue_redraw()


func _draw_fx() -> void:
	var a := level
	# Red wash, pulsing to the beat, with darker edges
	var pulse := 0.17 + 0.05 * absf(sin(t * PI * 178.0 / 60.0))
	root.draw_rect(Rect2(0, 0, 1280, 720), Color(0.85, 0.0, 0.0, pulse * a))
	for i in 6:
		var m := 18.0 * (i + 1)
		var edge := Color(0.35, 0.0, 0.0, 0.07 * a)
		root.draw_rect(Rect2(0, 0, 1280, m), edge)
		root.draw_rect(Rect2(0, 720 - m, 1280, m), edge)
		root.draw_rect(Rect2(0, 0, m, 720), edge)
		root.draw_rect(Rect2(1280 - m, 0, m, 720), edge)
	# A wavy band along the top that the drips run down from
	var red := Color(0.72, 0.0, 0.04, 0.92 * a)
	var hi := Color(1.0, 0.45, 0.45, 0.6 * a)
	var band := PackedVector2Array([Vector2(0, 0), Vector2(1280, 0)])
	var x := 1280.0
	while x >= 0.0:
		band.append(Vector2(x, 16.0 + 8.0 * sin(x * 0.03 + t * 0.8)))
		x -= 40.0
	root.draw_colored_polygon(band, red)
	for d in drips:
		var w: float = d.w
		var len: float = minf(d.len, d.max)
		var dx: float = d.x + sin(d.wobble + t) * 1.5
		var top := 14.0
		if d.len > d.max:
			# Let go: the drop falls on its own
			top = 14.0 + (d.len - d.max) * 6.0
			len = maxf(len - (d.len - d.max) * 6.0, 0.0)
		root.draw_rect(Rect2(dx - w / 2.0, top, w, len), red)
		root.draw_circle(Vector2(dx, top + len), w * 0.85, red)
		root.draw_circle(Vector2(dx - w * 0.25, top + len - w * 0.2), w * 0.22, hi)
		root.draw_line(Vector2(dx - w * 0.25, top + 4), Vector2(dx - w * 0.25, top + len - w), hi, 2.0)
	# Time left
	if left_frac > 0.0:
		root.draw_rect(Rect2(440, 218, 400, 14), Color(0.1, 0, 0, 0.7 * a))
		root.draw_rect(Rect2(442, 220, 396 * left_frac, 10), Color(1, 0.2, 0.1, a))
