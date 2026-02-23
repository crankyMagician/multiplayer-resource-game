extends Node

## AudioManager — singleton for all game audio (music, SFX, ambience).
## Server guard: every public method exits early on dedicated server.

signal now_playing_changed(track_name: String)

# ── Bus names (order matches default_bus_layout.tres) ────────────────────────
const BUS_NAMES: Array = ["Master", "Music", "SFX", "UI", "Ambience", "Voice"]
const BUS_DEFAULTS: Dictionary = {
	"Master": 1.0, "Music": 0.8, "SFX": 0.8,
	"UI": 0.8, "Ambience": 0.6, "Voice": 0.8,
}

# ── Music contexts → folder paths ────────────────────────────────────────────
const MUSIC_CONTEXTS: Dictionary = {
	"menu":       "res://assets/audio/music/menu",
	"overworld":  "res://assets/audio/music/overworld",
	"battle":     "res://assets/audio/music/battle",
	"boss":       "res://assets/audio/music/boss",
	"restaurant": "res://assets/audio/music/restaurant",
	"excursion":  "res://assets/audio/music/excursion",
	"victory":    "res://assets/audio/music/victory",
	"defeat":     "res://assets/audio/music/defeat",
}

# ── SFX registry: id → file path ─────────────────────────────────────────────
const SFX_REGISTRY: Dictionary = {
	# UI
	"ui_click":    "res://assets/audio/sfx/ui/click.ogg",
	"ui_confirm":  "res://assets/audio/sfx/ui/confirm.ogg",
	"ui_cancel":   "res://assets/audio/sfx/ui/cancel.ogg",
	"ui_open":     "res://assets/audio/sfx/ui/open.ogg",
	"ui_close":    "res://assets/audio/sfx/ui/close.ogg",
	"ui_tab":      "res://assets/audio/sfx/ui/tab.ogg",
	"ui_error":    "res://assets/audio/sfx/ui/error.ogg",
	"ui_hover":    "res://assets/audio/sfx/ui/hover.ogg",
	"ui_reward":   "res://assets/audio/sfx/ui/confirm.ogg",
	"ui_warning":  "res://assets/audio/sfx/ui/error.ogg",
	# Combat
	"hit_physical":   "res://assets/audio/sfx/combat/hit_physical.ogg",
	"hit_special":    "res://assets/audio/sfx/combat/hit_special.ogg",
	"hit_crit":       "res://assets/audio/sfx/combat/crit.ogg",
	"super_effective": "res://assets/audio/sfx/combat/super_effective.ogg",
	"not_effective":  "res://assets/audio/sfx/combat/not_effective.ogg",
	"miss":           "res://assets/audio/sfx/combat/miss.ogg",
	"faint":          "res://assets/audio/sfx/combat/faint.ogg",
	"switch":         "res://assets/audio/sfx/combat/switch.ogg",
	"flee":           "res://assets/audio/sfx/combat/flee.ogg",
	"heal":           "res://assets/audio/sfx/combat/heal.ogg",
	"buff":           "res://assets/audio/sfx/combat/buff.ogg",
	"debuff":         "res://assets/audio/sfx/combat/debuff.ogg",
	"status_apply":   "res://assets/audio/sfx/combat/status_apply.ogg",
	"xp_gain":        "res://assets/audio/sfx/combat/xp_gain.ogg",
	"level_up":       "res://assets/audio/sfx/combat/level_up.ogg",
	# Footsteps
	"footstep_grass":  "res://assets/audio/sfx/footsteps/grass.ogg",
	"footstep_stone":  "res://assets/audio/sfx/footsteps/stone.ogg",
	"footstep_dirt":   "res://assets/audio/sfx/footsteps/dirt.ogg",
	"footstep_wood":   "res://assets/audio/sfx/footsteps/wood.ogg",
	# Tools
	"tool_hoe":     "res://assets/audio/sfx/tools/hoe.ogg",
	"tool_axe":     "res://assets/audio/sfx/tools/axe.ogg",
	"tool_water":   "res://assets/audio/sfx/tools/water.ogg",
	"tool_harvest": "res://assets/audio/sfx/tools/harvest.ogg",
	# Items
	"item_pickup":  "res://assets/audio/sfx/items/pickup.ogg",
	"item_craft":   "res://assets/audio/sfx/items/craft.ogg",
	"item_coin":    "res://assets/audio/sfx/items/coin.ogg",
	"item_equip":   "res://assets/audio/sfx/items/equip.ogg",
	"item_eat":     "res://assets/audio/sfx/items/eat.ogg",
	"item_door":    "res://assets/audio/sfx/items/door.ogg",
	# Fishing
	"fish_cast":    "res://assets/audio/sfx/fishing/cast.ogg",
	"fish_reel":    "res://assets/audio/sfx/fishing/reel.ogg",
	"fish_splash":  "res://assets/audio/sfx/fishing/splash.ogg",
	"fish_catch":   "res://assets/audio/sfx/fishing/catch.ogg",
	# Social
	"dialogue_blip":    "res://assets/audio/sfx/social/dialogue_blip.ogg",
	"gift":             "res://assets/audio/sfx/social/gift.ogg",
	"quest_accept":     "res://assets/audio/sfx/social/quest_accept.ogg",
	"quest_complete":   "res://assets/audio/sfx/social/quest_complete.ogg",
	"quest_progress":   "res://assets/audio/sfx/social/quest_progress.ogg",
	"friend_request":   "res://assets/audio/sfx/social/friend.ogg",
}

# ── Ambience registry ─────────────────────────────────────────────────────────
const AMBIENCE_REGISTRY: Dictionary = {
	"rain":        "res://assets/audio/ambience/weather/rain.ogg",
	"storm":       "res://assets/audio/ambience/weather/storm.ogg",
	"wind":        "res://assets/audio/ambience/weather/wind.ogg",
	"overworld":   "res://assets/audio/ambience/overworld/world_loop.ogg",
	"restaurant":  "res://assets/audio/ambience/restaurant/indoor.ogg",
	"excursion":   "res://assets/audio/ambience/excursion/wilderness.ogg",
}

# ── Internals ─────────────────────────────────────────────────────────────────
const CROSSFADE_DURATION := 1.5
const SETTINGS_PATH := "user://settings.cfg"
const SFX_POOL_SIZE := 12
const SFX_3D_POOL_SIZE := 8
const AMBIENCE_LAYERS := 3

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_current_is_a: bool = true
var _music_context: String = ""
var _music_previous_context: String = ""
var _current_track_name: String = ""

var _sfx_pool: Array[AudioStreamPlayer] = []
var _ui_player: AudioStreamPlayer
var _sfx_3d_pool: Array[AudioStreamPlayer3D] = []
var _ambience_players: Array[AudioStreamPlayer] = []

var _is_muted: bool = false

# Cache of scanned folder → file list
var _folder_cache: Dictionary = {}

# ── Lifecycle ─────────────────────────────────────────────────────────────────

func _ready() -> void:
	if _is_server():
		var reason := "unknown"
		if DisplayServer.get_name() == "headless":
			reason = "headless"
		elif OS.has_feature("dedicated_server"):
			reason = "dedicated_server"
		else:
			reason = "CLI arg"
		print("[AudioManager] _ready() — server mode (%s), audio disabled" % reason)
		return
	_create_audio_nodes()
	_load_settings()
	# Diagnostic dump
	print("[AudioManager] _ready() — client mode")
	print("[AudioManager]   AudioServer buses: %d" % AudioServer.bus_count)
	for i in AudioServer.bus_count:
		var bname := AudioServer.get_bus_name(i)
		var vol := db_to_linear(AudioServer.get_bus_volume_db(i))
		var muted := AudioServer.is_bus_mute(i)
		print("[AudioManager]   Bus '%s': volume=%.2f muted=%s" % [bname, vol, muted])
	print("[AudioManager]   Nodes: music=2, sfx=%d, ui=1, 3d=%d, ambience=%d" % [_sfx_pool.size(), _sfx_3d_pool.size(), _ambience_players.size()])
	# Spot-check first SFX and first music folder
	var first_sfx_path: String = SFX_REGISTRY.values()[0] if not SFX_REGISTRY.is_empty() else ""
	if first_sfx_path != "":
		print("[AudioManager]   Spot-check SFX '%s': ResourceLoader.exists=%s" % [first_sfx_path, ResourceLoader.exists(first_sfx_path)])
	var first_music_folder: String = MUSIC_CONTEXTS.values()[0] if not MUSIC_CONTEXTS.is_empty() else ""
	if first_music_folder != "":
		var test_files := _scan_audio_folder(first_music_folder)
		print("[AudioManager]   Spot-check music folder '%s': %d files" % [first_music_folder, test_files.size()])

func _is_server() -> bool:
	# Only suppress audio on dedicated/headless servers, NOT listen servers
	if DisplayServer.get_name() == "headless":
		return true
	if OS.has_feature("dedicated_server"):
		return true
	for arg in OS.get_cmdline_user_args():
		if arg == "--server" or arg == "--role=server":
			return true
	return false

func _create_audio_nodes() -> void:
	# Music players (two for crossfade)
	_music_a = AudioStreamPlayer.new()
	_music_a.bus = &"Music"
	_music_a.name = "MusicA"
	add_child(_music_a)
	_music_a.finished.connect(_on_music_finished.bind(_music_a))

	_music_b = AudioStreamPlayer.new()
	_music_b.bus = &"Music"
	_music_b.name = "MusicB"
	add_child(_music_b)
	_music_b.finished.connect(_on_music_finished.bind(_music_b))

	# SFX pool
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = &"SFX"
		p.name = "SFX_%d" % i
		add_child(p)
		_sfx_pool.append(p)

	# UI player
	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = &"UI"
	_ui_player.name = "UIPlayer"
	add_child(_ui_player)

	# 3D SFX pool
	for i in SFX_3D_POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"SFX"
		p.name = "SFX3D_%d" % i
		add_child(p)
		_sfx_3d_pool.append(p)

	# Ambience layers
	for i in AMBIENCE_LAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = &"Ambience"
		p.name = "Ambience_%d" % i
		add_child(p)
		_ambience_players.append(p)

# ── Music ─────────────────────────────────────────────────────────────────────

func play_music(context: String) -> void:
	if _is_server():
		print("[AudioManager] play_music('%s') skipped — server mode" % context)
		return
	if context == _music_context:
		print("[AudioManager] play_music('%s') skipped — already active" % context)
		return
	_music_previous_context = _music_context
	_music_context = context

	var folder: String = MUSIC_CONTEXTS.get(context, "")
	if folder == "":
		print("[AudioManager] play_music('%s') — unknown context, stopping" % context)
		stop_music()
		return

	var tracks := _scan_audio_folder(folder)
	if tracks.is_empty():
		print("[AudioManager] play_music('%s') — folder '%s' scan returned 0 files" % [context, folder])
		return

	var track_path: String = tracks[randi() % tracks.size()]
	var stream := _load_audio(track_path)
	if not stream:
		print("[AudioManager] Failed to load track: %s" % track_path)
		return

	print("[AudioManager] Playing music context '%s', track: %s" % [context, track_path])
	_current_track_name = _pretty_track_name(track_path)
	now_playing_changed.emit(_current_track_name)
	_crossfade_to(stream)

func stop_music() -> void:
	if _is_server():
		return
	_music_context = ""
	_current_track_name = ""
	now_playing_changed.emit("")
	var active := _get_active_music_player()
	if not active:
		return
	if active.playing:
		var tw := create_tween()
		tw.tween_property(active, "volume_db", -80.0, CROSSFADE_DURATION)
		tw.tween_callback(active.stop)

func restore_previous_music() -> void:
	if _music_previous_context != "":
		var ctx := _music_previous_context
		_music_context = ""  # Force re-entry
		play_music(ctx)

func get_music_context() -> String:
	return _music_context

func _crossfade_to(stream: AudioStream) -> void:
	var old := _get_active_music_player()
	var new_player := _get_inactive_music_player()
	if not new_player or not old:
		return
	_music_current_is_a = not _music_current_is_a

	new_player.stream = stream
	new_player.volume_db = -80.0
	new_player.play()

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(new_player, "volume_db", 0.0, CROSSFADE_DURATION)
	if old.playing:
		tw.tween_property(old, "volume_db", -80.0, CROSSFADE_DURATION)
	tw.set_parallel(false)
	tw.tween_callback(func():
		if old != _get_active_music_player():
			old.stop()
	)

func _on_music_finished(player: AudioStreamPlayer) -> void:
	# If this is the active player, pick another track from same context
	if player == _get_active_music_player() and _music_context != "":
		play_music_next_track()

func play_music_next_track() -> void:
	var folder: String = MUSIC_CONTEXTS.get(_music_context, "")
	if folder == "":
		return
	var tracks := _scan_audio_folder(folder)
	if tracks.is_empty():
		return
	var track_path: String = tracks[randi() % tracks.size()]
	var stream := _load_audio(track_path)
	if not stream:
		return
	_current_track_name = _pretty_track_name(track_path)
	now_playing_changed.emit(_current_track_name)
	var active := _get_active_music_player()
	active.stream = stream
	active.volume_db = 0.0
	active.play()

func _get_active_music_player() -> AudioStreamPlayer:
	return _music_a if _music_current_is_a else _music_b

func _get_inactive_music_player() -> AudioStreamPlayer:
	return _music_b if _music_current_is_a else _music_a

# ── SFX ───────────────────────────────────────────────────────────────────────

func play_sfx(id: String, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if _is_server():
		return
	var path: String = SFX_REGISTRY.get(id, "")
	if path == "":
		print("[AudioManager] play_sfx('%s') — not in SFX_REGISTRY" % id)
		return
	var stream := _load_audio(path)
	if not stream:
		print("[AudioManager] play_sfx('%s') — failed to load '%s'" % [id, path])
		return
	var player := _get_idle_sfx_player()
	if not player:
		print("[AudioManager] play_sfx('%s') — all %d players busy" % [id, SFX_POOL_SIZE])
		return
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()
	print("[AudioManager] play_sfx('%s') on %s" % [id, player.name])

func play_sfx_varied(id: String, pitch_min: float = 0.9, pitch_max: float = 1.1) -> void:
	play_sfx(id, 0.0, randf_range(pitch_min, pitch_max))

func play_ui_sfx(id: String) -> void:
	if _is_server():
		return
	var path: String = SFX_REGISTRY.get(id, "")
	if path == "":
		print("[AudioManager] play_ui_sfx('%s') — not in SFX_REGISTRY" % id)
		return
	var stream := _load_audio(path)
	if not stream:
		print("[AudioManager] play_ui_sfx('%s') — failed to load '%s'" % [id, path])
		return
	_ui_player.stream = stream
	_ui_player.volume_db = 0.0
	_ui_player.play()
	print("[AudioManager] play_ui_sfx('%s') on UIPlayer" % id)

func play_sfx_3d(id: String, position: Vector3, volume_db: float = 0.0) -> void:
	if _is_server():
		return
	var path: String = SFX_REGISTRY.get(id, "")
	if path == "":
		print("[AudioManager] play_sfx_3d('%s') — not in SFX_REGISTRY" % id)
		return
	var stream := _load_audio(path)
	if not stream:
		print("[AudioManager] play_sfx_3d('%s') — failed to load '%s'" % [id, path])
		return
	var player := _get_idle_3d_player()
	if not player:
		print("[AudioManager] play_sfx_3d('%s') — all %d players busy" % [id, SFX_3D_POOL_SIZE])
		return
	player.global_position = position
	player.stream = stream
	player.volume_db = volume_db
	player.play()
	print("[AudioManager] play_sfx_3d('%s') on %s" % [id, player.name])

func _get_idle_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_pool:
		if not p.playing:
			return p
	return null  # All busy

func _get_idle_3d_player() -> AudioStreamPlayer3D:
	for p in _sfx_3d_pool:
		if not p.playing:
			return p
	return null

# ── Ambience ──────────────────────────────────────────────────────────────────

## layer: 0=base, 1=weather, 2=zone
func play_ambience(layer: int, id: String) -> void:
	if _is_server():
		return
	if layer < 0 or layer >= _ambience_players.size():
		print("[AudioManager] play_ambience(%d, '%s') — invalid layer" % [layer, id])
		return
	var path: String = AMBIENCE_REGISTRY.get(id, "")
	if path == "":
		print("[AudioManager] play_ambience(%d, '%s') — not in AMBIENCE_REGISTRY" % [layer, id])
		stop_ambience(layer)
		return
	var stream := _load_audio(path)
	if not stream:
		print("[AudioManager] play_ambience(%d, '%s') — failed to load '%s'" % [layer, id, path])
		return
	var player := _ambience_players[layer]
	if player.stream == stream and player.playing:
		print("[AudioManager] play_ambience(%d, '%s') — already playing" % [layer, id])
		return  # Already playing this
	print("[AudioManager] play_ambience(%d, '%s') — starting" % [layer, id])
	var tw := create_tween()
	if player.playing:
		tw.tween_property(player, "volume_db", -80.0, 0.5)
		tw.tween_callback(func():
			player.stream = stream
			player.volume_db = -80.0
			player.play()
		)
		tw.tween_property(player, "volume_db", 0.0, 1.0)
	else:
		player.stream = stream
		player.volume_db = -80.0
		player.play()
		tw.tween_property(player, "volume_db", 0.0, 1.0)

func stop_ambience(layer: int) -> void:
	if _is_server():
		return
	if layer < 0 or layer >= _ambience_players.size():
		return
	var player := _ambience_players[layer]
	if player.playing:
		var tw := create_tween()
		tw.tween_property(player, "volume_db", -80.0, 0.5)
		tw.tween_callback(player.stop)

func stop_all_ambience() -> void:
	for i in AMBIENCE_LAYERS:
		stop_ambience(i)

# ── Volume / Mute ─────────────────────────────────────────────────────────────

var is_muted: bool:
	get: return _is_muted

func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(linear, 0.0, 1.0)))

func get_bus_volume(bus_name: String) -> float:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return 1.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))

func toggle_mute() -> void:
	set_muted(not _is_muted)

func set_muted(muted: bool) -> void:
	_is_muted = muted
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, muted)
	_save_settings()

# ── Settings persistence ──────────────────────────────────────────────────────

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		print("[AudioManager] _load_settings — no settings file at '%s', applying defaults" % SETTINGS_PATH)
		_apply_defaults()
		return
	print("[AudioManager] _load_settings — loaded '%s'" % SETTINGS_PATH)

	# Per-bus volumes
	for bus_name in BUS_NAMES:
		var key: String = bus_name.to_lower() + "_volume"
		var vol: float = config.get_value("audio", key, -1.0)
		if vol < 0.0:
			# Backward compat: old single master_volume key
			if bus_name == "Master":
				vol = config.get_value("audio", "master_volume", BUS_DEFAULTS.get(bus_name, 1.0))
			else:
				vol = BUS_DEFAULTS.get(bus_name, 0.8)
		set_bus_volume(bus_name, vol)
		print("[AudioManager] Bus '%s' volume: %.2f" % [bus_name, vol])

	_is_muted = config.get_value("audio", "muted", false)
	print("[AudioManager] Loaded settings — muted: %s" % str(_is_muted))
	if _is_muted:
		var master_idx := AudioServer.get_bus_index("Master")
		if master_idx >= 0:
			AudioServer.set_bus_mute(master_idx, true)

func _apply_defaults() -> void:
	for bus_name in BUS_NAMES:
		set_bus_volume(bus_name, BUS_DEFAULTS.get(bus_name, 0.8))
	_save_settings()

func _save_settings() -> void:
	var config := ConfigFile.new()
	# Load existing to preserve non-audio keys
	config.load(SETTINGS_PATH)
	for bus_name in BUS_NAMES:
		config.set_value("audio", bus_name.to_lower() + "_volume", get_bus_volume(bus_name))
	config.set_value("audio", "muted", _is_muted)
	# Preserve backward compat key
	config.set_value("audio", "master_volume", get_bus_volume("Master"))
	config.save(SETTINGS_PATH)

func save_bus_volumes() -> void:
	_save_settings()

# ── Audio file helpers ────────────────────────────────────────────────────────

func _scan_audio_folder(folder_path: String) -> Array:
	if _folder_cache.has(folder_path):
		return _folder_cache[folder_path]

	var files: Array = []
	var dir := DirAccess.open(folder_path)
	if not dir:
		print("[AudioManager] _scan_audio_folder('%s') — DirAccess.open failed" % folder_path)
		_folder_cache[folder_path] = files
		return files

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			# Handle export .remap files
			var lower := file_name.to_lower()
			if lower.ends_with(".ogg") or lower.ends_with(".mp3") or lower.ends_with(".wav"):
				files.append(folder_path.path_join(file_name))
			elif lower.ends_with(".ogg.remap") or lower.ends_with(".mp3.remap") or lower.ends_with(".wav.remap"):
				# Strip .remap suffix for ResourceLoader
				files.append(folder_path.path_join(file_name.get_basename()))
			elif lower.ends_with(".import"):
				# .import files also indicate the original resource exists
				var original := file_name.get_basename()  # strip .import
				var orig_lower := original.to_lower()
				if orig_lower.ends_with(".ogg") or orig_lower.ends_with(".mp3") or orig_lower.ends_with(".wav"):
					var full_path := folder_path.path_join(original)
					if full_path not in files:
						files.append(full_path)
		file_name = dir.get_next()
	dir.list_dir_end()

	_folder_cache[folder_path] = files
	print("[AudioManager] _scan_audio_folder('%s') — found %d files" % [folder_path, files.size()])
	return files

func _load_audio(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		print("[AudioManager] _load_audio('%s') — ResourceLoader.exists() = false" % path)
		return null
	var res = ResourceLoader.load(path)
	if res is AudioStream:
		return res
	print("[AudioManager] _load_audio('%s') — loaded but not AudioStream (is %s)" % [path, type_string(typeof(res))])
	return null

func _pretty_track_name(path: String) -> String:
	var file_name := path.get_file().get_basename()
	# Replace underscores and hyphens with spaces, title-case
	return file_name.replace("_", " ").replace("-", " ").capitalize()
