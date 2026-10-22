extends Node
## Autoload "Audio": music with crossfades, ambience loops, sound effects and voice lines.
## The .ogg files are read at runtime, so the game runs straight from the folder without importing.

const SFX_VOICES := 12

var _cache := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _sfx: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _voice: AudioStreamPlayer
var _current_music := ""
var _music_vol := 0.7
var _sfx_vol := 0.9
var _fade_tween: Tween
var _voice_files := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_a = _player()
	_music_b = _player()
	_ambience = _player()
	_voice = _player()
	for i in SFX_VOICES:
		_sfx.append(_player())
	_index_voices()
	set_volumes(Game.settings.music, Game.settings.sfx)


func _player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
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
		# heckle_3_1.ogg -> group "heckle", driver_oi_0.ogg -> group "driver_oi"
		var base := f.get_basename()
		var group := base
		var parts := base.split("_")
		if parts.size() > 1 and parts[-1].is_valid_int():
			group = "_".join(parts.slice(0, parts.size() - 1))
		# heckle_3_1.ogg also counts towards the general "heckle" pool
		var groups := [group]
		if parts.size() == 3 and parts[0] == "heckle" and parts[1].is_valid_int():
			groups.append("heckle")
		for g in groups:
			if not _voice_files.has(g):
				_voice_files[g] = []
			_voice_files[g].append("res://audio/voice/" + f)


func set_volumes(music: float, sfx: float) -> void:
	_music_vol = music
	_sfx_vol = sfx
	if _music_a == null:
		return
	var active := _music_a if _music_a.playing else _music_b
	active.volume_db = _db(_music_vol)
	_ambience.volume_db = _db(_sfx_vol * 0.5)


func _db(v: float) -> float:
	return linear_to_db(maxf(v, 0.0001))


func play_music(name: String, fade := 1.0) -> void:
	if name == _current_music:
		return
	_current_music = name
	var stream := _load("res://audio/music/%s.ogg" % name)
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
	_fade_tween.tween_property(new, "volume_db", _db(_music_vol), fade)
	if old.playing:
		_fade_tween.tween_property(old, "volume_db", -60.0, fade)
		_fade_tween.chain().tween_callback(old.stop)


func stop_music(fade := 0.6) -> void:
	_current_music = ""
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
	_ambience.volume_db = _db(_sfx_vol * 0.5)
	if stream:
		_ambience.play()


func sfx(name: String, pitch := 1.0, volume := 1.0) -> void:
	var stream := _load("res://audio/sfx/%s.ogg" % name)
	if stream == null:
		return
	var p := _sfx[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx.size()
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = _db(_sfx_vol * volume)
	p.play()


func sting(name: String) -> void:
	var stream := _load("res://audio/music/sting_%s.ogg" % name)
	if stream == null:
		return
	var p := _sfx[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx.size()
	p.stream = stream
	p.pitch_scale = 1.0
	p.volume_db = _db(_music_vol * 1.1)
	p.play()


## Plays a random line from a voice group ("heckle", "driver_oi", "punched", "warden_oof"...).
func voice(group: String, pitch := 1.0, volume := 1.0, interrupt := true) -> void:
	var files: Array = _voice_files.get(group, [])
	if files.is_empty():
		# "punched" picks from any punched_* line
		for g in _voice_files:
			if g.begins_with(group):
				files.append_array(_voice_files[g])
	if files.is_empty():
		return
	if _voice.playing and not interrupt:
		return
	_voice.stream = _load(files[randi() % files.size()])
	_voice.pitch_scale = pitch
	_voice.volume_db = _db(_sfx_vol * volume)
	_voice.play()
