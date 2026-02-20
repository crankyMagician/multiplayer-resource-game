@tool
extends Node
## Handles audio playback and control.

signal audio_ready(result: Dictionary)


func handle_play_audio(params) -> Dictionary:
	_play_audio_deferred(params)
	return {"_deferred": audio_ready}


func _play_audio_deferred(params) -> void:
	await get_tree().process_frame

	if not params is Dictionary:
		audio_ready.emit({"error": "Invalid params"})
		return

	var tree := get_tree()
	if tree == null:
		audio_ready.emit({"error": "No scene tree available"})
		return

	var node_path: String = params.get("node_path", "")
	var audio_type: String = params.get("audio_type", "procedural")
	var volume_db: float = float(params.get("volume", 0.0))
	var bus: String = params.get("bus", "Master")
	var spatial: bool = params.get("spatial", false)
	var node_name: String = params.get("node_name", "MCP_Audio")

	# If node_path provided, play existing node
	if not node_path.is_empty():
		var node := tree.root.get_node_or_null(node_path.trim_prefix("/root"))
		if node == null:
			audio_ready.emit({"error": "Node not found: %s" % node_path})
			return
		if node.has_method("play"):
			node.call("play")
			audio_ready.emit({"status": "ok", "action": "play_existing", "node": node_path})
		else:
			audio_ready.emit({"error": "Node is not an audio player: %s" % node_path})
		return

	# Create new audio player
	var parent_path: String = params.get("parent_path", "")
	var parent: Node = null
	if not parent_path.is_empty():
		parent = tree.root.get_node_or_null(parent_path.trim_prefix("/root"))
	if parent == null:
		parent = tree.current_scene if tree.current_scene else tree.root

	var player: Node = null
	if spatial:
		player = AudioStreamPlayer2D.new()
	else:
		player = AudioStreamPlayer.new()

	player.name = node_name
	player.set("volume_db", volume_db)
	player.set("bus", bus)

	# Create audio stream
	var stream: AudioStream = null
	if audio_type == "file":
		var file_path: String = params.get("file_path", "")
		if file_path.is_empty():
			audio_ready.emit({"error": "file_path is required for audio_type 'file'"})
			player.queue_free()
			return
		if ResourceLoader.exists(file_path):
			stream = load(file_path) as AudioStream
		else:
			audio_ready.emit({"error": "Audio file not found: %s" % file_path})
			player.queue_free()
			return
	else:
		# Procedural audio
		var waveform: String = params.get("waveform", "sine")
		var frequency: float = float(params.get("frequency", 440))
		var duration: float = float(params.get("duration", 0.2))
		var loop: bool = params.get("loop", false)

		stream = _generate_audio(waveform, frequency, duration, loop)

	if stream == null:
		audio_ready.emit({"error": "Failed to create audio stream"})
		player.queue_free()
		return

	player.set("stream", stream)
	parent.add_child(player)
	player.call("play")

	# Auto-free non-looping audio after playback (both AudioStreamPlayer and AudioStreamPlayer2D)
	var loop_setting: bool = params.get("loop", false)
	if not loop_setting:
		if player is AudioStreamPlayer:
			(player as AudioStreamPlayer).finished.connect(func() -> void:
				player.queue_free()
			)
		elif player is AudioStreamPlayer2D:
			(player as AudioStreamPlayer2D).finished.connect(func() -> void:
				player.queue_free()
			)

	audio_ready.emit({
		"status": "ok",
		"action": "created_and_playing",
		"node_path": str(player.get_path()),
		"audio_type": audio_type,
		"spatial": spatial,
	})


func handle_stop_audio(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}

	var node_path: String = params.get("node_path", "")
	var remove_node: bool = params.get("remove_node", false)

	if node_path.is_empty():
		return {"error": "node_path is required"}

	var tree := get_tree()
	if tree == null:
		return {"error": "No scene tree available"}

	var node := tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node == null:
		return {"error": "Node not found: %s" % node_path}

	if node.has_method("stop"):
		node.call("stop")

	if remove_node:
		node.queue_free()

	return {"status": "ok", "node": node_path, "removed": remove_node}


func handle_set_bus_volume(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}
	var bus_name: String = params.get("bus_name", "Master")
	var volume_db: float = float(params.get("volume_db", 0.0))
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return {"error": "Audio bus not found: %s" % bus_name}
	AudioServer.set_bus_volume_db(idx, volume_db)
	return {"status": "ok", "bus": bus_name, "volume_db": volume_db}


func handle_set_bus_mute(params) -> Dictionary:
	if not params is Dictionary:
		return {"error": "Invalid params"}
	var bus_name: String = params.get("bus_name", "Master")
	var mute: bool = params.get("mute", true)
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return {"error": "Audio bus not found: %s" % bus_name}
	AudioServer.set_bus_mute(idx, mute)
	return {"status": "ok", "bus": bus_name, "mute": mute}


func _generate_audio(waveform: String, frequency: float, duration: float, loop: bool) -> AudioStream:
	# Generate a simple PCM waveform using AudioStreamWAV
	var sample_rate: int = 22050
	var num_samples: int = int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)  # 16-bit samples = 2 bytes each

	for i in range(num_samples):
		var t: float = float(i) / float(sample_rate)
		var sample: float = 0.0

		match waveform:
			"sine":
				sample = sin(2.0 * PI * frequency * t)
			"square":
				sample = 1.0 if fmod(t * frequency, 1.0) < 0.5 else -1.0
			"sawtooth":
				sample = 2.0 * fmod(t * frequency, 1.0) - 1.0
			"noise":
				sample = randf_range(-1.0, 1.0)

		# Apply fade out for last 10%
		var fade_start: float = duration * 0.9
		if t > fade_start:
			sample *= 1.0 - (t - fade_start) / (duration * 0.1)

		# Convert to 16-bit signed integer
		var int_sample: int = clampi(int(sample * 32767.0), -32768, 32767)
		data[i * 2] = int_sample & 0xFF
		data[i * 2 + 1] = (int_sample >> 8) & 0xFF

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.data = data
	wav.stereo = false
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = num_samples

	return wav
