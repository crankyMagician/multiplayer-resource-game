@tool
extends Node
## Handles procedural generation: noise maps, tilemap fills, object scattering.

signal noise_ready(result: Dictionary)
signal scatter_ready(result: Dictionary)

func handle_generate_noise_map(params) -> Dictionary:
	_gen_noise_deferred(params)
	return {"_deferred": noise_ready}

func _gen_noise_deferred(params) -> void:
	await get_tree().process_frame
	if not params is Dictionary:
		noise_ready.emit({"error": "Invalid params"})
		return
	var w: int = int(params.get("width", 64))
	var h: int = int(params.get("height", 64))
	var noise := FastNoiseLite.new()
	noise.noise_type = _get_noise_type(params.get("noise_type", "simplex"))
	noise.frequency = float(params.get("frequency", 0.05))
	noise.seed = int(params.get("seed", randi()))

	var data: Array = []
	for y in range(h):
		var row: Array = []
		for x in range(w):
			row.append(noise.get_noise_2d(float(x), float(y)))
		data.append(row)

	noise_ready.emit({"status": "ok", "width": w, "height": h, "data": data, "seed": noise.seed})

func handle_fill_tilemap_from_noise(params) -> Dictionary:
	_fill_tilemap_deferred(params)
	return {"_deferred": noise_ready}

func _fill_tilemap_deferred(params) -> void:
	await get_tree().process_frame
	if not params is Dictionary:
		noise_ready.emit({"error": "Invalid params"})
		return
	var node_path: String = params.get("node_path", "")
	var tree := get_tree()
	var node := tree.root.get_node_or_null(node_path.trim_prefix("/root"))
	if node_path == "/root":
		node = tree.root
	if node == null or not node is TileMapLayer:
		noise_ready.emit({"error": "TileMapLayer not found: %s" % node_path})
		return
	var tilemap := node as TileMapLayer
	var w: int = int(params.get("width", 32))
	var h: int = int(params.get("height", 32))
	var thresholds: Array = params.get("thresholds", [])
	if thresholds.is_empty():
		noise_ready.emit({"error": "thresholds array is required"})
		return
	var noise := FastNoiseLite.new()
	noise.noise_type = _get_noise_type(params.get("noise_type", "simplex"))
	noise.frequency = float(params.get("frequency", 0.05))
	noise.seed = int(params.get("seed", randi()))

	var tiles_set: int = 0
	for y in range(h):
		for x in range(w):
			var val: float = noise.get_noise_2d(float(x), float(y))
			for threshold in thresholds:
				if val <= float(threshold.get("max_value", 0)):
					var src_id: int = int(threshold.get("source_id", 0))
					var ax: int = int(threshold.get("atlas_x", 0))
					var ay: int = int(threshold.get("atlas_y", 0))
					tilemap.set_cell(Vector2i(x, y), src_id, Vector2i(ax, ay))
					tiles_set += 1
					break

	noise_ready.emit({"status": "ok", "tiles_set": tiles_set, "width": w, "height": h})

func handle_scatter_objects(params) -> Dictionary:
	_scatter_deferred(params)
	return {"_deferred": scatter_ready}

func _scatter_deferred(params) -> void:
	await get_tree().process_frame
	if not params is Dictionary:
		scatter_ready.emit({"error": "Invalid params"})
		return
	var scene_path: String = params.get("scene_path", "")
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		scatter_ready.emit({"error": "Scene not found: %s" % scene_path})
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		scatter_ready.emit({"error": "Failed to load: %s" % scene_path})
		return

	var tree := get_tree()
	var parent_path: String = params.get("parent_path", "")
	var parent: Node = null
	if not parent_path.is_empty():
		parent = tree.root.get_node_or_null(parent_path.trim_prefix("/root"))
	if parent == null:
		parent = tree.current_scene if tree.current_scene else tree.root

	var count: int = int(params.get("count", 10))
	var area = params.get("area", {"x": 0, "y": 0, "width": 1000, "height": 1000})
	var ax: float = float(area.get("x", 0))
	var ay: float = float(area.get("y", 0))
	var aw: float = float(area.get("width", 1000))
	var ah: float = float(area.get("height", 1000))
	var noise := FastNoiseLite.new()
	noise.frequency = float(params.get("noise_frequency", 0.02))
	noise.seed = int(params.get("noise_seed", randi()))
	var threshold: float = float(params.get("density_threshold", 0.0))

	var placed: Array = []
	var attempts: int = 0
	while placed.size() < count and attempts < count * 5:
		attempts += 1
		var px: float = ax + randf() * aw
		var py: float = ay + randf() * ah
		var noise_val: float = noise.get_noise_2d(px, py)
		if noise_val >= threshold:
			var inst := packed.instantiate()
			if inst is Node2D:
				(inst as Node2D).position = Vector2(px, py)
			parent.add_child(inst)
			placed.append({"x": px, "y": py, "name": inst.name})

	scatter_ready.emit({"status": "ok", "placed": placed.size(), "attempts": attempts, "objects": placed})

func _get_noise_type(t: String) -> FastNoiseLite.NoiseType:
	match t.to_lower():
		"simplex": return FastNoiseLite.TYPE_SIMPLEX
		"simplex_smooth": return FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		"cellular": return FastNoiseLite.TYPE_CELLULAR
		"perlin": return FastNoiseLite.TYPE_PERLIN
		"value": return FastNoiseLite.TYPE_VALUE
		"value_cubic": return FastNoiseLite.TYPE_VALUE_CUBIC
	return FastNoiseLite.TYPE_SIMPLEX
