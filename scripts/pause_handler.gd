extends Node
## Toggles pause with Esc / Start. Runs even while the tree is paused.

var main


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	var hud = main.get("hud")
	var in_settings: bool = hud != null and hud.pause_settings != null and hud.pause_settings.visible
	if in_settings and (event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause")):
		Audio.sfx("ui_back")
		hud.close_pause_settings()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("pause") and main.state != "results":
		main.set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and get_tree().paused and main.state != "results":
		main.set_paused(false)
		get_viewport().set_input_as_handled()
