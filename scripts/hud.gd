extends CanvasLayer
## On-screen UI, laid out for the 1280x720 base resolution.

const Prompt := preload("res://scripts/prompt.gd")
const Career := preload("res://scripts/career.gd")
const BAR_W := 400.0

var main
var root: Control
var time_label: Label
var level_label: Label
var score_label: Label
var tickets_label: Label
var banner_label: Label
var boss_label: Label
var flash_rect: ColorRect
var minimap: Control
var pause_root: Control
var pause_first: Button
var results_root: Control
var results_box: VBoxContainer
var results_first: Button
var results_buttons: Array = []
var pui: Array = []  # per player widgets
var two := false


func _ready() -> void:
	root = Control.new()
	root.size = Vector2(1280, 720)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Game.theme
	add_child(root)
	two = main.players.size() > 1

	if two:
		_rect(Color(0.06, 0.05, 0.12), Vector2(638, 0), Vector2(4, 720))
		time_label = _label("3:00", 46, Color.WHITE, Vector2(540, 4), Vector2(200, 54), HORIZONTAL_ALIGNMENT_CENTER, null, true)
		tickets_label = _label("", 26, Color.WHITE, Vector2(490, 56), Vector2(300, 34), HORIZONTAL_ALIGNMENT_CENTER, null, true)
		score_label = _label("", 30, Color.WHITE, Vector2(490, 88), Vector2(300, 40), HORIZONTAL_ALIGNMENT_CENTER, null, true)
		level_label = _label("", 18, Color(1, 1, 1, 0.85), Vector2(440, 694), Vector2(400, 24), HORIZONTAL_ALIGNMENT_CENTER)
	else:
		time_label = _label("3:00", 52, Color.WHITE, Vector2(24, 8), Vector2(220, 60), HORIZONTAL_ALIGNMENT_LEFT, null, true)
		level_label = _label("", 20, Color(1, 1, 1, 0.85), Vector2(26, 66), Vector2(600, 28))
		score_label = _label("0", 50, Color.WHITE, Vector2(440, 4), Vector2(400, 60), HORIZONTAL_ALIGNMENT_CENTER, null, true)
		tickets_label = _label("Tickets 0 / 10", 36, Color.WHITE, Vector2(840, 14), Vector2(416, 50), HORIZONTAL_ALIGNMENT_RIGHT, null, true)
	boss_label = _label("", 28, Color(1, 0.45, 0.9), Vector2(340, 128 if two else 96), Vector2(600, 40), HORIZONTAL_ALIGNMENT_CENTER, null, true)

	for i in main.players.size():
		var area := Rect2(0, 0, 1280, 720)
		if two:
			area = Rect2(i * 642, 0, 638, 720)
		pui.append(_build_player_ui(i, area))

	if not two:
		var bar := HBoxContainer.new()
		bar.position = Vector2(24, 676)
		bar.add_theme_constant_override("separation", 18)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bar)
		var items := [["move", "Move"], ["ticket", "Ticket"], ["punch", "Punch"], ["whistle", "Whistle"],
				["dive", "Dive"], ["sprint", "Sprint"]]
		if not main.players[0].gadgets.is_empty():
			items.append(["gadget", "Gadget"])
			if main.players[0].gadgets.size() > 1:
				items.append(["gadget_next", "Switch"])
		items.append(["pause", "Pause"])
		for p in items:
			bar.add_child(Prompt.make(p[0], p[1], 26, 18))

	banner_label = _label("", 52 if two else 56, Color(1, 0.9, 0.2), Vector2(40, 190), Vector2(1200, 150), HORIZONTAL_ALIGNMENT_CENTER, null, true)
	banner_label.visible = false

	minimap = Control.new()
	minimap.position = Vector2(1060, 500) if not two else Vector2(552, 540)
	minimap.size = Vector2(196, 160) if not two else Vector2(176, 140)
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	minimap.draw.connect(_draw_minimap)
	root.add_child(minimap)

	flash_rect = ColorRect.new()
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.size = Vector2(1280, 720)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)

	_build_pause()
	_build_results()


func _build_player_ui(i: int, area: Rect2) -> Dictionary:
	var u := {}
	var c := Control.new()
	c.position = area.position
	c.size = area.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(c)
	u.root = c
	var w := area.size.x
	var col := Color(1, 0.85, 0.1) if i == 0 else Color(0.35, 0.75, 1.0)
	# In split-screen, player 2's readouts hug the right edge so they stay clear of the centre column
	var right := two and i == 1
	var align := HORIZONTAL_ALIGNMENT_RIGHT if right else HORIZONTAL_ALIGNMENT_LEFT
	if two:
		u.score = _label("P%d  0" % (i + 1), 34, col, Vector2(w - 316 if right else 16, 8), Vector2(300, 46), align, c, true)
		u.combo = _label("", 26, Color(1, 0.6, 0.15), Vector2(w - 236 if right else 16, 50), Vector2(220, 34), align, c, true)
		u.combo_bar = _rect(Color(1, 0.6, 0.15), Vector2(w - 178 if right else 18, 84), Vector2(160, 6), c)
	else:
		u.score = null
		u.combo = _label("", 30, Color(1, 0.6, 0.15), Vector2(440, 60), Vector2(400, 40), HORIZONTAL_ALIGNMENT_CENTER, c, true)
		u.combo_bar = _rect(Color(1, 0.6, 0.15), Vector2(540, 102), Vector2(200, 8), c)
	var base_y := 604.0 if not two else 640.0
	var sx := w - 244.0 if right else 24.0
	_label("STAMINA", 18, Color.WHITE, Vector2(sx, base_y), Vector2(220, 24), align, c)
	_rect(Color(0, 0, 0, 0.6), Vector2(sx, base_y + 26), Vector2(220, 18), c)
	u.stamina = _rect(Color(0.3, 0.9, 0.4), Vector2(sx + 2, base_y + 28), Vector2(216, 14), c)
	var tx := w - 424.0 if right else 24.0
	u.status = _label("", 22, Color(0.6, 0.85, 1.0), Vector2(tx, base_y - 30), Vector2(400, 28), align, c, true)
	u.gadget = _label("", 22, Color(1, 0.85, 0.4), Vector2(tx, base_y - 58), Vector2(400, 28), align, c, true)
	var hint := HBoxContainer.new()
	hint.position = Vector2(w / 2.0 - 200, 560 if not two else 580)
	hint.size = Vector2(400, 44)
	hint.alignment = BoxContainer.ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(hint)
	u.hint = hint
	u.hint_key = ""
	# Ticket mini-game: stop the needle in the green
	var tp := Control.new()
	tp.position = Vector2(w / 2.0 - 210, 150 if two else 120)
	tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(tp)
	_rect(Color(0.1, 0.1, 0.15, 0.85), Vector2(0, 0), Vector2(420, 100), tp)
	u.ticket_label = _label("", 22, Color.WHITE, Vector2(0, 4), Vector2(420, 32), HORIZONTAL_ALIGNMENT_CENTER, tp)
	_rect(Color(0.85, 0.3, 0.25), Vector2(10, 42), Vector2(BAR_W, 24), tp)
	u.green = _rect(Color(0.3, 0.9, 0.35), Vector2(10, 42), Vector2(60, 24), tp)
	u.needle = _rect(Color.WHITE, Vector2(10, 36), Vector2(6, 36), tp)
	_rect(Color(0, 0, 0, 0.6), Vector2(10, 78), Vector2(BAR_W, 12), tp)
	u.progress = _rect(Color(1, 0.88, 0.1), Vector2(10, 78), Vector2(0, 12), tp)
	tp.visible = false
	u.ticket = tp
	u.pad = -1
	if two:
		# Each player's prompts follow their own device
		var dev: Dictionary = {"p1": not Input.get_connected_joypads().is_empty() and Input.get_connected_joypads().size() >= 2,
			"p2": not Input.get_connected_joypads().is_empty()}
		u.pad = 1 if (dev.p1 if i == 0 else dev.p2) else 0
	return u


func _label(text: String, size: int, color: Color, pos: Vector2, box: Vector2,
		align := HORIZONTAL_ALIGNMENT_LEFT, parent: Control = null, title := false) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = box
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if title:
		l.add_theme_font_override("font", Game.font_title)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.1))
	l.add_theme_constant_override("outline_size", maxi(size / 4, 6))
	(parent if parent else root).add_child(l)
	return l


func _rect(color: Color, pos: Vector2, box: Vector2, parent: Control = null) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = box
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent else root).add_child(r)
	return r


func _button(text: String, parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 58)
	b.pressed.connect(func() -> void:
		Audio.sfx("ui_select")
		cb.call())
	b.focus_entered.connect(func() -> void: Audio.sfx("ui_move", 1.0, 0.6))
	parent.add_child(b)
	return b


func _build_pause() -> void:
	pause_root = ColorRect.new()
	pause_root.color = Color(0, 0, 0, 0.6)
	pause_root.size = Vector2(1280, 720)
	pause_root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(pause_root)
	var panel := PanelContainer.new()
	panel.position = Vector2(440, 170)
	panel.size = Vector2(400, 380)
	pause_root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	var title := Label.new()
	title.text = "ON A BREAK"
	title.add_theme_font_override("font", Game.font_title)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1, 0.86, 0.15))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	pause_first = _button("Back to Work", v, func() -> void: main.set_paused(false))
	_button("Restart Shift", v, func() -> void: main.restart())
	_button("Quit to Menu", v, func() -> void: main.quit_to_menu())
	var hints := HBoxContainer.new()
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.add_theme_constant_override("separation", 20)
	hints.add_child(Prompt.make("ui_accept", "Select", 28, 20))
	hints.add_child(Prompt.make("pause", "Resume", 28, 20))
	v.add_child(hints)
	pause_root.visible = false


func _build_results() -> void:
	results_root = ColorRect.new()
	results_root.color = Color(0, 0, 0, 0.7)
	results_root.size = Vector2(1280, 720)
	results_root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.add_child(results_root)
	var panel := PanelContainer.new()
	panel.position = Vector2(250, 20)
	panel.size = Vector2(780, 680)
	results_root.add_child(panel)
	results_box = VBoxContainer.new()
	results_box.add_theme_constant_override("separation", 6)
	results_box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(results_box)
	results_root.visible = false


func update_stats(time_left: float, score: int, tickets: int, quota: int) -> void:
	var secs := int(ceil(time_left))
	time_label.text = "%d:%02d" % [secs / 60, secs % 60]
	var hurry := time_left <= (30.0 if main.mode != "endless" else 15.0)
	time_label.add_theme_color_override("font_color", Color(1, 0.3, 0.25) if hurry else Color.WHITE)
	match main.mode:
		"endless":
			tickets_label.text = "Wave %d:  %d / %d" % [main.wave, tickets, quota]
		"race":
			tickets_label.text = "TICKET RACE"
		_:
			tickets_label.text = "Tickets %d / %d" % [tickets, quota]
	tickets_label.add_theme_color_override("font_color", Color(0.4, 1, 0.45) if tickets >= quota and main.mode != "race" else Color.WHITE)
	if main.mode == "race":
		score_label.text = ""
	elif two:
		score_label.text = "Team  %d" % score
	else:
		score_label.text = str(score)
	minimap.queue_redraw()


func update_player(i: int, d: Dictionary) -> void:
	var u: Dictionary = pui[i]
	if u.score:
		u.score.text = "P%d  %d%s" % [i + 1, d.score, ("   %d ticket%s" % [d.tickets, "" if d.tickets == 1 else "s"]) if main.mode == "race" else ""]
	var mult: float = d.combo
	u.combo.text = "COMBO x%s" % str(mult) if mult > 1.0 else ""
	u.combo_bar.visible = mult > 1.0
	u.combo_bar.size.x = (160.0 if two else 200.0) * clampf(d.combo_frac, 0.0, 1.0)
	u.stamina.size.x = 216.0 * clampf(d.stamina, 0.0, 1.0)
	u.stamina.color = Color(0.9, 0.35, 0.3) if d.exhausted else (Color(0.3, 0.8, 1.0) if d.boost > 0.0 else Color(0.3, 0.9, 0.4))
	var status := ""
	if d.boost > 0.0:
		status = "SPEED BOOST %ds" % int(ceil(d.boost))
	if d.soaked:
		status = "SOAKED!"
	if status == "" and d.get("sweets", -1) >= 0:
		status = "SWEETS x%d" % d.sweets if d.sweets > 0 else "NO SWEETS! WATCH OUT"
	u.status.text = status
	if d.gadget != "":
		var name: String = {"clamp": "Wheel Clamp", "tow": "Tow Truck", "camera": "Camera Van"}[d.gadget]
		u.gadget.text = "GADGET: %s  x%d" % [name, d.uses]
		u.gadget.add_theme_color_override("font_color", Color(1, 0.85, 0.4) if d.uses > 0 else Color(0.6, 0.6, 0.6))
	else:
		u.gadget.text = ""


func set_boss(name: String, hp: int, max_hp: int) -> void:
	if name == "":
		boss_label.text = ""
		return
	var pips := ""
	for k in max_hp:
		pips += "#" if k < hp else "-"
	boss_label.text = "BOSS: %s   [%s]" % [name, pips]


func flash() -> void:
	flash_rect.color = Color(1, 1, 1, 0.85)
	var tw := create_tween()
	tw.tween_property(flash_rect, "color:a", 0.0, 0.35)


func set_level_info(text: String) -> void:
	level_label.text = text


func set_hint(i: int, text: String, action := "ticket") -> void:
	var u: Dictionary = pui[i]
	var key := text + action
	if key == u.hint_key:
		return
	u.hint_key = key
	for c in u.hint.get_children():
		c.queue_free()
	if text != "":
		var p := Prompt.make(action, text, 38 if not two else 32, 30 if not two else 24)
		if u.pad >= 0:
			p.get_child(0).force_pad = u.pad
			p.get_child(0).call_deferred("_refresh")
		p.get_child(1).add_theme_color_override("font_color", Color(1, 0.95, 0.4))
		u.hint.add_child(p)


func set_ticket_ui(i: int, show: bool, needle: float, green_start: float, green_size: float,
		phase: String, progress: float) -> void:
	var u: Dictionary = pui[i]
	u.ticket.visible = show
	if not show:
		return
	u.green.position.x = 10.0 + green_start * BAR_W
	u.green.size.x = green_size * BAR_W
	u.needle.position.x = 10.0 + needle * BAR_W - 3.0
	if phase == "needle":
		u.ticket_label.text = "Ticket again to stop the needle in the green!"
		u.progress.size.x = 0.0
	else:
		u.ticket_label.text = "Writing ticket..."
		u.progress.size.x = BAR_W * clampf(progress, 0.0, 1.0)


func _draw_minimap() -> void:
	if main == null or main.world == null:
		return
	var world = main.world
	var b: Rect2 = world.bounds
	var sc := minf(minimap.size.x / b.size.x, minimap.size.y / b.size.y)
	var off := (minimap.size - b.size * sc) / 2.0
	var to_map := func(p: Vector3) -> Vector2: return off + (Vector2(p.x, p.z) - b.position) * sc
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.14, 0.75)
	bg.set_corner_radius_all(10)
	bg.border_color = Color(1, 0.86, 0.15)
	bg.set_border_width_all(2)
	minimap.draw_style_box(bg, Rect2(Vector2(-6, -6), minimap.size + Vector2(12, 12)))
	for r in world.walk_rects:
		minimap.draw_rect(Rect2(off + (r.position - b.position) * sc, r.size * sc), Color(0.6, 0.6, 0.65, 0.8))
	for c in get_tree().get_nodes_in_group("cars"):
		if c.spot != null and c.is_parked() and not c.ticketed:
			minimap.draw_circle(to_map.call(c.position), 2.5, Color(1, 1, 1))
	for d in get_tree().get_nodes_in_group("drivers"):
		minimap.draw_circle(to_map.call(d.global_position), 3.0, Color(1, 0.3, 0.25))
	for pk in main.pickups:
		var pk_col: Color = {"coffee": Color(0.6, 0.4, 0.2), "sweets": Color(1, 0.55, 0.1), "present": Color(1, 0.3, 0.3)}.get(pk.kind, Color(0.3, 1, 0.3))
		minimap.draw_circle(to_map.call(pk.node.position), 3.0, pk_col)
	if main.boss_car != null and is_instance_valid(main.boss_car):
		minimap.draw_circle(to_map.call(main.boss_car.position), 5.0, Color(1, 0.3, 0.9))
	for i in main.players.size():
		var wp: Vector2 = to_map.call(main.players[i].warden.global_position)
		minimap.draw_circle(wp, 4.5, Color(0.1, 0.1, 0.1))
		minimap.draw_circle(wp, 3.5, Color(1, 0.9, 0.1) if i == 0 else Color(0.3, 0.75, 1.0))


func popup(text: String, color: Color, screen_pos: Vector2, size := 36) -> void:
	var l := _label(text, size, color, screen_pos - Vector2(250, 24), Vector2(500, 48), HORIZONTAL_ALIGNMENT_CENTER, null, true)
	l.pivot_offset = Vector2(250, 24)
	l.scale = Vector2.ONE * 1.6
	l.rotation = randf_range(-0.12, 0.12)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE, 0.15)
	tw.tween_property(l, "position:y", l.position.y - 70.0, 1.1)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)


func banner(text: String, duration: float) -> void:
	banner_label.text = text
	banner_label.visible = true
	banner_label.pivot_offset = Vector2(600, 75)
	banner_label.scale = Vector2.ONE * 1.4
	var tw := create_tween()
	tw.tween_property(banner_label, "scale", Vector2.ONE, 0.2)
	tw.tween_interval(duration)
	tw.tween_callback(func() -> void: banner_label.visible = false)


func show_pause(paused: bool) -> void:
	pause_root.visible = paused
	if paused:
		pause_first.grab_focus()


func show_results(r: Dictionary) -> void:
	for i in pui.size():
		set_hint(i, "")
		pui[i].ticket.visible = false
	for c in results_box.get_children():
		c.queue_free()
	var title_text := "SHIFT OVER"
	var verdict_text := "QUOTA MET!" if r.passed else "QUOTA MISSED"
	var good: bool = r.passed
	match r.mode:
		"endless":
			title_text = "GAME OVER"
			verdict_text = "You reached wave %d" % r.wave
			good = r.wave > 1
		"race":
			var a: Dictionary = r.players[0]
			var b: Dictionary = r.players[1]
			if a.tickets == b.tickets and a.score == b.score:
				verdict_text = "IT'S A DRAW!"
			else:
				var p1: bool = a.tickets > b.tickets or (a.tickets == b.tickets and a.score > b.score)
				verdict_text = "PLAYER %d WINS!" % (1 if p1 else 2)
			good = true
	_res_label(title_text, 50, Color(1, 0.86, 0.15), true)
	_res_label(verdict_text, 32, Color(0.4, 1, 0.45) if good else Color(1, 0.4, 0.35))

	if r.mode in ["career", "event", "coop"]:
		var stars := HBoxContainer.new()
		stars.alignment = BoxContainer.ALIGNMENT_CENTER
		stars.add_theme_constant_override("separation", 14)
		results_box.add_child(stars)
		for i in 3:
			var star := Control.new()
			star.custom_minimum_size = Vector2(56, 56)
			star.pivot_offset = Vector2(28, 28)
			star.set_meta("lit", false)
			star.draw.connect(func() -> void: draw_star(star, Vector2(28, 28), 26.0, star.get_meta("lit")))
			stars.add_child(star)
			if i < r.stars:
				var tw := create_tween()
				tw.tween_interval(0.5 + i * 0.4)
				tw.tween_callback(func() -> void:
					star.set_meta("lit", true)
					star.queue_redraw()
					star.scale = Vector2.ONE * 1.6
					Audio.sfx("star", 1.0 + i * 0.12))
				tw.tween_property(star, "scale", Vector2.ONE, 0.2)

	var lines := PackedStringArray()
	if r.mode == "race":
		for i in 2:
			var pr: Dictionary = r.players[i]
			lines.append("Player %d:  %d tickets   %d points   %d punches" % [i + 1, pr.tickets, pr.score, pr.punches])
	else:
		lines.append("Tickets  %d%s        Score  %d%s" % [r.tickets, (" / %d" % r.quota) if r.mode != "endless" else "", r.score, "   NEW BEST!" if r.new_best else ""])
	lines.append("Perfect writes %d    Best combo x%s    Close calls %d    Bosses beaten %d" % [r.perfects, str(r.best_combo), r.close_calls, r.bosses])
	lines.append("Drivers punched %d    Heckled %d times    Wrong tickets %d    Times hit %d" % [r.punches, r.heckles, r.wrong, r.hit])
	if r.quota_time > 0.0:
		var medal: String = ["", "BRONZE", "SILVER", "GOLD"][r.medal]
		lines.append("Quota met in %s%s%s" % [_clock(r.quota_time), "   NEW BEST TIME!" if r.new_time else "",
			("   Best time medal: " + medal) if medal != "" else ""])
	_res_label("\n".join(lines), 19)

	var pay: Dictionary = r.pay
	var pay_text := "PAY PACKET:  +£%d wages   +%d XP" % [pay.wages, pay.xp]
	if pay.rank_after > pay.rank_before:
		pay_text += "\nPROMOTED TO %s!" % Career.RANKS[pay.rank_after].name.to_upper()
	_res_label(pay_text, 22, Color(0.5, 1, 0.7) if pay.rank_after == pay.rank_before else Color(1, 0.85, 0.2), pay.rank_after > pay.rank_before)
	if not r.challenges.is_empty():
		var ct := PackedStringArray()
		for c in r.challenges:
			ct.append("%s CHALLENGE DONE: %s  (+£%d)" % ["WEEKLY" if c.get("weekly", false) else "DAILY", c.text, c.wages])
		_res_label("\n".join(ct), 19, Color(0.5, 0.85, 1.0))
	if not r.unlocks.is_empty():
		var t := "UNLOCKED!  " + ",  ".join(PackedStringArray(r.unlocks.slice(0, 4)))
		if r.unlocks.size() > 4:
			t += "  ...and %d more" % (r.unlocks.size() - 4)
		var u := _res_label(t, 19, Color(1, 0.6, 0.9))
		u.autowrap_mode = TextServer.AUTOWRAP_WORD
		u.custom_minimum_size = Vector2(640, 0)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	results_first = null
	results_buttons = []
	var entry = null
	if r.board != "":
		entry = load("res://scripts/initials.gd").new()
		entry.initials = Game.initials
		entry.board_id = r.board
		entry.main = main
		results_box.add_child(entry)
		entry.done.connect(func(place: int) -> void:
			for b in results_buttons:
				b.disabled = false
			if results_first:
				results_first.grab_focus())
	results_box.add_child(buttons)
	if r.has_next:
		results_first = _button("Next Level", buttons, func() -> void: main.next_level())
	var retry := _button("Retry", buttons, func() -> void: main.restart())
	_button("Menu", buttons, func() -> void: main.quit_to_menu())
	for b in buttons.get_children():
		b.custom_minimum_size = Vector2(200, 54)
		results_buttons.append(b)
	if results_first == null:
		results_first = retry
	var hints := HBoxContainer.new()
	hints.alignment = BoxContainer.ALIGNMENT_CENTER
	hints.add_child(Prompt.make("ui_accept", "Select", 28, 20))
	results_box.add_child(hints)
	results_root.visible = true
	results_root.modulate.a = 0.0
	create_tween().tween_property(results_root, "modulate:a", 1.0, 0.4)
	if entry != null:
		for b in results_buttons:
			b.disabled = true
		entry.grab_focus()
	else:
		results_first.grab_focus()


func _res_label(text: String, size: int, color := Color.WHITE, title := false) -> Label:
	var l := Label.new()
	l.text = text
	if title:
		l.add_theme_font_override("font", Game.font_title)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	results_box.add_child(l)
	return l


static func _clock(t: float) -> String:
	var s := int(t)
	return "%d:%02d" % [s / 60, s % 60]


static func draw_star(c: Control, centre: Vector2, radius: float, lit: bool) -> void:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var rr := radius if i % 2 == 0 else radius * 0.45
		pts.append(centre + Vector2(cos(a), sin(a)) * rr)
	var outline := pts.duplicate()
	outline.append(pts[0])
	c.draw_colored_polygon(pts, Color(1, 0.85, 0.1) if lit else Color(0.3, 0.3, 0.36))
	c.draw_polyline(outline, Color(0.06, 0.05, 0.1), 4.0, true)
