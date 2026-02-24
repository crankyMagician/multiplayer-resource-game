extends Node

const BattleArenaUIScene = preload("res://scenes/battle/battle_arena_ui.tscn")
const BattleManagerScript = preload("res://scripts/battle/battle_manager.gd")

@export var give_battle_items: bool = true
@export var auto_press_item: bool = true
@export var arena_theme: String = "farm"

var _battle_mgr: Node
var _battle_ui: Node

func _ready() -> void:
	DataRegistry.ensure_loaded()
	_seed_party()
	_seed_inventory()

	_battle_mgr = Node.new()
	_battle_mgr.name = "BattleManager"
	_battle_mgr.set_script(BattleManagerScript)
	add_child(_battle_mgr)

	_battle_ui = BattleArenaUIScene.instantiate()
	_battle_ui.name = "BattleArenaUI"
	add_child(_battle_ui)
	_battle_ui.setup(_battle_mgr)

	var enemy := _build_enemy()
	_battle_mgr.start_battle_client(enemy, 0, "", arena_theme)
	print("[BattleIsolation] Battle started. give_battle_items=", give_battle_items, " theme=", arena_theme)

	await get_tree().create_timer(1.7).timeout
	if _battle_ui and _battle_ui.has_method("_has_usable_battle_items"):
		print("[BattleIsolation] _has_usable_battle_items()=", _battle_ui._has_usable_battle_items())
	if auto_press_item and _battle_ui and _battle_ui.has_method("_on_item_pressed"):
		print("[BattleIsolation] Calling _on_item_pressed()")
		_battle_ui._on_item_pressed()
		print("[BattleIsolation] _on_item_pressed() returned")

func _seed_party() -> void:
	PlayerData.party.clear()
	PlayerData.party.append({
		"species_id": "rice_ball",
		"nickname": "Rice Ball",
		"level": 5,
		"hp": 45,
		"max_hp": 45,
		"attack": 12,
		"defense": 14,
		"sp_attack": 10,
		"sp_defense": 14,
		"speed": 10,
		"moves": ["grain_bash", "quick_bite", "bread_wall", "taste_test"],
		"pp": [15, 25, 10, 5],
		"types": ["grain"],
		"ability_id": ""
	})
	PlayerData.party_changed.emit()

func _seed_inventory() -> void:
	PlayerData.inventory.clear()
	if give_battle_items:
		PlayerData.inventory["herb_poultice"] = 1
		PlayerData.inventory["revival_soup"] = 1
	else:
		PlayerData.inventory["grain_wheat"] = 3
	PlayerData.inventory_changed.emit()

func _build_enemy() -> Dictionary:
	return {
		"species_id": "wheat_golem",
		"nickname": "Wheat Golem",
		"level": 4,
		"hp": 40,
		"max_hp": 40,
		"attack": 10,
		"defense": 10,
		"sp_attack": 8,
		"sp_defense": 8,
		"speed": 8,
		"moves": ["quick_bite", "grain_bash"],
		"pp": [25, 15],
		"types": ["grain"],
		"ability_id": ""
	}
