extends Node3D

var owner_name: String = ""
var restaurant_index: int = -1

@onready var farm_manager: Node3D = $FarmArea/FarmManager
@onready var owner_label: Label3D = $OwnerLabel

func initialize(p_owner_name: String, idx: int, data: Dictionary) -> void:
	owner_name = p_owner_name
	restaurant_index = idx
	position = Vector3(1000 + idx * 200, 0, 1000)
	owner_label.text = p_owner_name + "'s Restaurant"
	# Load farm plot states if saved
	if data.has("farm_plots") and not data["farm_plots"].is_empty():
		# Defer loading until FarmManager has generated its plots
		farm_manager.load_save_data.call_deferred(data["farm_plots"])

func get_save_data() -> Dictionary:
	return {"farm_plots": farm_manager.get_save_data()}
