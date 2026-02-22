@tool
extends Node3D

@export var district_name: String = "District"
@export var arrow_text: String = "->"
@export var district_color: Color = Color(0.85, 0.75, 0.35, 1.0)

func _ready() -> void:
	_apply()

func _apply() -> void:
	var main_label: Label3D = get_node_or_null("MainLabel")
	if main_label:
		main_label.text = district_name
		main_label.modulate = district_color

	var arrow_label: Label3D = get_node_or_null("ArrowLabel")
	if arrow_label:
		arrow_label.text = arrow_text
		arrow_label.modulate = district_color

	var board := get_node_or_null("Board") as MeshInstance3D
	if board and board.material_override is StandardMaterial3D:
		if not board.has_meta("unique_board_material"):
			board.material_override = (board.material_override as StandardMaterial3D).duplicate()
			board.set_meta("unique_board_material", true)
		var mat := board.material_override as StandardMaterial3D
		mat.albedo_color = Color(
			clampf(district_color.r * 0.6, 0.0, 1.0),
			clampf(district_color.g * 0.6, 0.0, 1.0),
			clampf(district_color.b * 0.6, 0.0, 1.0),
			1.0
		)
