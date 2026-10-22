extends Node
## Autoload "Audio": music with crossfades, ambience loops, sound effects, voice lines and car stereos.
## The .ogg files are read at runtime, so the game runs straight from the folder without importing.
## Each kind of sound has its own bus (Music, Effects, Voices, Stereos), so the settings sliders
## turn whole groups up and down.

const SFX_VOICES := 12
const BUSES := ["Music", "Effects", "Voices", "Stereos"]

## Every track, for the jukebox and the soundtrack setting: [file, title, style]
const TRACKS := [
	["menu", "Clocking On", "theme"], ["street", "Double Yellow Ska", "classic"], ["seaside", "Kiss Me Quick", "classic"],
	["snow", "Snow Chains", "classic"], ["night", "Night Shift", "classic"], ["posh", "Lord of the Manor", "classic"],
	["boss", "Boss Driver", "classic"], ["endless", "Endless Patrol", "classic"], ["versus", "Ticket Race", "classic"],
	["wedding", "Here Comes the Bride", "event"], ["matchday", "Match Day", "event"], ["xmas", "Jingle Bells", "event"],
	["rock", "Heavy Fine", "rock"], ["rock2", "Clamp Boogie", "rock"], ["metal", "Tow Truck of Doom", "rock"],
	["metal2", "Warden of Steel", "rock"], ["punk", "No Parking (Anarchy)", "rock"], ["synthwave", "Neon Ticket", "classic"],
]
const STEREOS := ["radio_rock", "radio_metal", "radio_rave", "radio_bass"]

var _cache := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _voice: AudioStreamPlayer
var _current_music := ""
var _requested_music := ""
var _fade_tween: Tween
var _voice_files := {}


func _enter_tree() -> void:
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _player("Music")
	_music_b = _player("Music")
	_ambience = _player("Effects")
	_voice = _player("Voices")
	for i in SFX_VOICES:
		_sfx.append(_player("Effects"))
	_index_voices()
	apply_volumes(Game.settings)


func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _load(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	var stream: AudioStream = null
	if FileAccess.file_exists(path):
		stream = AudioStreamOggVorbis.load_from_file(path)
	_cache[path] = stream
	return stream


func _index_voices() -> void:
	var dir := DirAccess.open("res://audio/voice")
	if dir == null:
		return
	for f in dir.get_files():
		if not f.ends_with(".ogg"):
			continue
		# heckle_3_1.ogg -> group "heckle_3", driver_oi_0.ogg -> group "driver_oi"
		var base := f.get_basename()
		var group := base
		var parts := base.split("_")
		if parts.size() > 1 and parts[-1].is_valid_int():
			group = "_".join(parts.slice(0, parts.size() - 1))
		# Numbered heckles (heckle_3_1) and the family-friendly ones (heckle_ff_2_0) also join the "heckle" pool
		var groups := [group]
		if parts[0] == "heckle" and parts.size() >= 3 and (parts[1].is_valid_int() or parts[1] == "ff"):
			groups.append("heckle")
		for g in groups:
			if not _voice_files.has(g):
				_voice_files[g] = []
			_voice_files[g].append("res://audio/voice/" + f)


# ---------------------------------------------------------------- volumes

static func _db(v: float) -> float:
	return linear_to_db(maxf(v, 0.0001))


## Sets every bus from the settings dictionary (master, music, sfx, voice, stereo: 0..1).
func apply_volumes(s: Dictionary) -> void:
	AudioServer.set_bus_volume_db(0, _db(float(s.get("master", 1.0))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), _db(float(s.get("music", 0.7))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Effects"), _db(float(s.get("sfx", 0.9))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Voices"), _db(float(s.get("voice", 0.9))))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Stereos"), _db(float(s.get("stereo", 0.8))))
	# Re-pick the level music if the soundtrack style changed
	if _requested_music != "" and _resolve(_requested_music) != _current_music:
		var want := _requested_music
		_requested_music = ""
		play_music(want)


## Older callers: music and effects only.
func set_volumes(music: float, sfx: float) -> void:
	var s: Dictionary = Game.settings.duplicate()
	s.music = music
	s.sfx = sfx
	apply_volumes(s)


# ---------------------------------------------------------------- music

## Swaps level music for the player's chosen soundtrack style ("classic", "rock" or "mix").
func _resolve(name: String) -> String:
	var style: String = Game.settings.get("soundtrack", "classic")
	if style == "classic" or name in ["menu", "boss", "wedding", "matchday", "xmas"] or name.begins_with("sting"):
		return name
	var pool := []
	for t in TRACKS:
		if (style == "rock" and t[2] == "rock") or (style == "mix" and t[2] in ["classic", "rock"]):
			pool.append(t[0])
	if pool.is_empty():
		return name
	return pool[absi(hash(name + str(Game.current_level))) % pool.size()]


func play_music(name: String, fade := 1.0, exact := false) -> void:
	_requested_music = name if not exact else ""
	var file := name if exact else _resolve(name)
	if file == _current_music:
		return
	_current_music = file
	var stream := _load("res://audio/music/%s.ogg" % file)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	var old := _music_a if _music_a.playing else _music_b
	var new := _music_b if old == _music_a else _music_a
	if _fade_tween:
		_fade_tween.kill()
	new.stream = stream
	new.volume_db = -40.0
	if stream:
		new.play()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(new, "volume_db", 0.0, fade)
	if old.playing:
		_fade_tween.tween_property(old, "volume_db", -60.0, fade)
		_fade_tween.chain().tween_callback(old.stop)


func current_music() -> String:
	return _current_music


func stop_music(fade := 0.6) -> void:
	_current_music = ""
	_requested_music = ""
	if _fade_tween:
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	for p in [_music_a, _music_b]:
		if p.playing:
			_fade_tween.tween_property(p, "volume_db", -60.0, fade)
	_fade_tween.chain().tween_callback(func() -> void:
		_music_a.stop()
		_music_b.stop())


func play_ambience(name: String) -> void:
	if name == "":
		_ambience.stop()
		return
	var stream := _load("res://audio/sfx/amb_%s.ogg" % name)
	if stream is AudioStreamOggVorbis:
		stream.loop = true
	_ambience.stream = stream
	_ambience.volume_db = _db(0.5)
	if stream:
		_ambience.play()


# ---------------------------------------------------------------- effects and voices

func sfx(name: String, pitch := 1.0, volume := 1.0) -> void:
	var stream := _load("res://audio/sfx/%s.ogg" % name)
	if stream == null:
		return
	var p := _sfx[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx.size()
	p.bus = "Effects"
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = _db(volume)
	p.play()


func sting(name: String) -> void:
	var stream := _load("res://audio/music/sting_%s.ogg" % name)
	if stream == null:
		return
	var p := _sfx[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx.size()
	p.bus = "Music"
	p.stream = stream
	p.pitch_scale = 1.0
	p.volume_db = _db(1.1)
	p.play()


## Plays a random line from a voice group ("heckle", "driver_oi", "punched", "warden_oof"...).
## who: -1 any speaker, 0 a man, 1 a woman (takes 0-1 are men, takes 2-3 women, no number counts as 0).
func voice(group: String, pitch := 1.0, volume := 1.0, interrupt := true, who := -1) -> void:
	var files: Array = _voice_files.get(group, [])
	if files.is_empty():
		# "punched" picks from any punched_* line
		for g in _voice_files:
			if g.begins_with(group):
				files.append_array(_voice_files[g])
	if who >= 0:
		var matching := files.filter(func(f: String) -> bool: return _take_is_woman(f) == (who == 1))
		if not matching.is_empty():
			files = matching
	if files.is_empty():
		return
	if _voice.playing and not interrupt:
		return
	_voice.stream = _load(files[randi() % files.size()])
	_voice.pitch_scale = pitch
	_voice.volume_db = _db(volume)
	_voice.play()


static func _take_is_woman(path: String) -> bool:
	var parts := path.get_file().get_basename().split("_")
	return parts.size() > 1 and parts[-1].is_valid_int() and int(parts[-1]) >= 2


## A looping car stereo that plays from a moving car (attach the returned player to it).
func make_stereo(name := "") -> AudioStreamPlayer3D:
	if name == "":
		name = STEREOS[randi() % STEREOS.size()]
	var stream := _load("res://audio/sfx/%s.ogg" % name)
	if stream is AudioStreamOggVorbis:
		stream = stream.duplicate()
		stream.loop = true
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "Stereos"
	p.unit_size = 14.0
	p.max_distance = 60.0
	p.volume_db = 4.0
	p.attenuation_filter_cutoff_hz = 2500.0
	p.panning_strength = 0.6
	return p
