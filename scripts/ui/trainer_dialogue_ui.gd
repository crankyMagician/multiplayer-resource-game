extends CanvasLayer

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

@onready var panel: PanelContainer = $Panel
@onready var name_label: Label = $Panel/VBox/NameLabel
@onready var text_label: Label = $Panel/VBox/TextLabel
@onready var ok_button: Button = $Panel/VBox/OkButton
@onready var button_row: HBoxContainer = $Panel/VBox/ButtonRow
@onready var accept_button: Button = $Panel/VBox/ButtonRow/AcceptButton
@onready var decline_button: Button = $Panel/VBox/ButtonRow/DeclineButton

var pending_trainer_id: String = ""
var is_challenge_mode: bool = false
var _typewriter_tween: Tween = null

func _ready() -> void:
	visible = false
	UITheme.init()
	UITheme.style_modal(panel)
	UITheme.style_heading(name_label)
	name_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_H2))
	name_label.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
	UITheme.style_body(text_label)
	text_label.add_theme_color_override("font_color", UITokens.INK_DARK)
	UITheme.style_button(ok_button, "secondary")
	UITheme.style_button(accept_button, "primary")
	UITheme.style_button(decline_button, "danger")
	ok_button.pressed.connect(_on_ok)
	accept_button.pressed.connect(_on_accept)
	decline_button.pressed.connect(_on_decline)

# Post-battle dialogue (read-only, OK button only)
func show_dialogue(trainer_name: String, text: String) -> void:
	name_label.text = trainer_name
	is_challenge_mode = false
	pending_trainer_id = ""
	ok_button.visible = true
	button_row.visible = false
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_typewrite_label(text_label, text)
	# Wait for typewriter to finish before starting auto-dismiss timer
	if _typewriter_tween and _typewriter_tween.is_valid():
		await _typewriter_tween.finished
	await get_tree().create_timer(4.0).timeout
	if visible and not is_challenge_mode:
		visible = false

# Pre-battle challenge (accept/decline buttons)
func show_challenge(trainer_name: String, text: String, trainer_id: String) -> void:
	name_label.text = trainer_name
	is_challenge_mode = true
	pending_trainer_id = trainer_id
	ok_button.visible = false
	button_row.visible = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_typewrite_label(text_label, text)

func _typewrite_label(label: Label, text: String) -> void:
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
		_typewriter_tween = null
	label.text = text
	var cps := UITheme.get_text_speed()
	if cps < 0:
		label.visible_characters = -1
		return
	var char_count := text.length()
	if char_count <= 0:
		label.visible_characters = -1
		return
	label.visible_characters = 0
	var duration := char_count / cps
	_typewriter_tween = create_tween()
	_typewriter_tween.tween_property(label, "visible_characters", char_count, duration)

func _skip_typewriter() -> void:
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
		_typewriter_tween = null
		text_label.visible_characters = -1

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

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	# ESC closes/declines the dialogue
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if is_challenge_mode:
			_on_decline()
		else:
			_on_ok()
		get_viewport().set_input_as_handled()
		return
	# Click-to-skip typewriter
	if _typewriter_tween and _typewriter_tween.is_valid():
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed and event.keycode != KEY_ESCAPE):
			_skip_typewriter()
			get_viewport().set_input_as_handled()
