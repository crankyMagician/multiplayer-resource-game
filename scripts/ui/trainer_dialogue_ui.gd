extends CanvasLayer

@onready var panel: PanelContainer = $Panel
@onready var name_label: Label = $Panel/VBox/NameLabel
@onready var text_label: Label = $Panel/VBox/TextLabel
@onready var ok_button: Button = $Panel/VBox/OkButton
@onready var button_row: HBoxContainer = $Panel/VBox/ButtonRow
@onready var accept_button: Button = $Panel/VBox/ButtonRow/AcceptButton
@onready var decline_button: Button = $Panel/VBox/ButtonRow/DeclineButton

var pending_trainer_id: String = ""
var is_challenge_mode: bool = false

func _ready() -> void:
	visible = false
	ok_button.pressed.connect(_on_ok)
	accept_button.pressed.connect(_on_accept)
	decline_button.pressed.connect(_on_decline)

# Post-battle dialogue (read-only, OK button only)
func show_dialogue(trainer_name: String, text: String) -> void:
	name_label.text = trainer_name
	text_label.text = text
	is_challenge_mode = false
	pending_trainer_id = ""
	ok_button.visible = true
	button_row.visible = false
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Auto-dismiss after 4 seconds
	await get_tree().create_timer(4.0).timeout
	if visible and not is_challenge_mode:
		visible = false

# Pre-battle challenge (accept/decline buttons)
func show_challenge(trainer_name: String, text: String, trainer_id: String) -> void:
	name_label.text = trainer_name
	text_label.text = text
	is_challenge_mode = true
	pending_trainer_id = trainer_id
	ok_button.visible = false
	button_row.visible = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_ok() -> void:
	visible = false
	is_challenge_mode = false

func _on_accept() -> void:
	visible = false
	is_challenge_mode = false
	if pending_trainer_id != "":
		# Find the trainer NPC and call request_challenge
		for npc in get_tree().get_nodes_in_group("trainer_npc"):
			if npc.trainer_id == pending_trainer_id:
				npc.request_challenge.rpc_id(1)
				break
	pending_trainer_id = ""

func _on_decline() -> void:
	visible = false
	is_challenge_mode = false
	if pending_trainer_id != "":
		# For gatekeepers: notify server to push player back
		var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
		if battle_mgr:
			battle_mgr._respond_gatekeeper_decline.rpc_id(1, pending_trainer_id)
	pending_trainer_id = ""
