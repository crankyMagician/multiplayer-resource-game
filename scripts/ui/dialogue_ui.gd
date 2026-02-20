extends CanvasLayer

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

var npc_name_label: Label = null
var friendship_label: Label = null
var friendship_bar: ProgressBar = null
var dialogue_text: RichTextLabel = null
var choices_container: VBoxContainer = null
var action_container: HBoxContainer = null
var give_gift_button: Button = null
var close_button: Button = null

# Gift panel
var gift_panel: PanelContainer = null
var gift_list: VBoxContainer = null
var gift_back_button: Button = null

var current_npc_id: String = ""
var current_friendship: int = 0
var current_tier: String = "neutral"
var showing_gift_panel: bool = false
var _typewriter_tween: Tween = null
var _gift_popup_mode: bool = false
var _auto_close_tween: Tween = null

func _ready() -> void:
	UITheme.init()
	visible = false
	_build_ui()

func _build_ui() -> void:
	var panel = PanelContainer.new()
	panel.name = "Panel"
	panel.anchors_preset = Control.PRESET_CENTER
	panel.custom_minimum_size = UITheme.scaled_vec(Vector2(550, 350))
	UITheme.style_modal(panel)
	add_child(panel)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var vbox = VBoxContainer.new()
	margin.add_child(vbox)

	# NPC name
	npc_name_label = Label.new()
	npc_name_label.text = "NPC Name"
	npc_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_heading(npc_name_label)
	vbox.add_child(npc_name_label)

	# Friendship bar
	var friend_row = HBoxContainer.new()
	vbox.add_child(friend_row)

	friendship_label = Label.new()
	friendship_label.text = "Neutral (0)"
	friendship_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_small(friendship_label)
	friend_row.add_child(friendship_label)

	friendship_bar = ProgressBar.new()
	friendship_bar.min_value = -100
	friendship_bar.max_value = 100
	friendship_bar.value = 0
	friendship_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	friendship_bar.custom_minimum_size.x = 200
	friendship_bar.show_percentage = false
	friend_row.add_child(friendship_bar)

	# Dialogue text
	dialogue_text = RichTextLabel.new()
	dialogue_text.bbcode_enabled = true
	dialogue_text.fit_content = true
	dialogue_text.custom_minimum_size.y = 80
	dialogue_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.style_richtext_defaults(dialogue_text)
	vbox.add_child(dialogue_text)

	# Choices container
	choices_container = VBoxContainer.new()
	vbox.add_child(choices_container)

	# Action buttons (Give Gift + Close)
	action_container = HBoxContainer.new()
	action_container.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(action_container)

	give_gift_button = Button.new()
	give_gift_button.text = "Give Gift"
	UITheme.style_button(give_gift_button, "secondary")
	give_gift_button.pressed.connect(_show_gift_panel)
	action_container.add_child(give_gift_button)

	close_button = Button.new()
	close_button.text = "Close"
	UITheme.style_button(close_button, "danger")
	close_button.pressed.connect(_close)
	action_container.add_child(close_button)

	# Gift selection panel (hidden by default)
	gift_panel = PanelContainer.new()
	gift_panel.name = "GiftPanel"
	gift_panel.anchors_preset = Control.PRESET_CENTER
	gift_panel.custom_minimum_size = UITheme.scaled_vec(Vector2(400, 300))
	gift_panel.visible = false
	UITheme.style_modal(gift_panel)
	add_child(gift_panel)

	var gift_margin = MarginContainer.new()
	gift_margin.add_theme_constant_override("margin_left", 10)
	gift_margin.add_theme_constant_override("margin_right", 10)
	gift_margin.add_theme_constant_override("margin_top", 10)
	gift_margin.add_theme_constant_override("margin_bottom", 10)
	gift_panel.add_child(gift_margin)

	var gift_vbox = VBoxContainer.new()
	gift_margin.add_child(gift_vbox)

	var gift_title = Label.new()
	gift_title.text = "Select a Gift"
	gift_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_subheading(gift_title)
	gift_vbox.add_child(gift_title)

	var gift_scroll = ScrollContainer.new()
	gift_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gift_scroll.custom_minimum_size.y = 200
	gift_vbox.add_child(gift_scroll)

	gift_list = VBoxContainer.new()
	gift_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gift_scroll.add_child(gift_list)

	gift_back_button = Button.new()
	gift_back_button.text = "Back"
	UITheme.style_button(gift_back_button, "secondary")
	gift_back_button.pressed.connect(_hide_gift_panel)
	gift_vbox.add_child(gift_back_button)

# === Public methods called by SocialManager RPCs ===

func show_dialogue(npc_id: String, text: String, choices: Array, friendship_points: int, tier: String) -> void:
	current_npc_id = npc_id
	current_friendship = friendship_points
	current_tier = tier
	showing_gift_panel = false

	DataRegistry.ensure_loaded()
	var npc_def = DataRegistry.get_npc(npc_id)
	npc_name_label.text = npc_def.display_name if npc_def else npc_id

	_update_friendship_display(friendship_points, tier)
	_typewrite(dialogue_text, text)

	# Build choice buttons
	_clear_choices()
	if choices.size() > 0:
		for i in range(choices.size()):
			var btn = Button.new()
			btn.text = choices[i]
			UITheme.style_button(btn, "secondary")
			var idx = i
			btn.pressed.connect(_on_choice_pressed.bind(idx))
			choices_container.add_child(btn)
		action_container.visible = false
	else:
		# Simple dialogue — just show Continue + action buttons
		var continue_btn = Button.new()
		continue_btn.text = "Continue"
		UITheme.style_button(continue_btn, "primary")
		continue_btn.pressed.connect(_on_continue)
		choices_container.add_child(continue_btn)
		action_container.visible = false

	gift_panel.visible = false
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	NetworkManager.request_set_busy.rpc_id(1, true)

func show_choice_result(response: String, new_points: int, new_tier: String) -> void:
	current_friendship = new_points
	current_tier = new_tier
	_typewrite(dialogue_text, response)
	_update_friendship_display(new_points, new_tier)

	# Show action buttons after choice result
	_clear_choices()
	action_container.visible = true

func show_gift_response(npc_id: String, message: String, points_change: int) -> void:
	# If DialogueUI is not already open, enter popup mode (direct E-key gift path)
	if not visible:
		_gift_popup_mode = true
		current_npc_id = npc_id

		# Populate NPC name and friendship bar
		DataRegistry.ensure_loaded()
		var npc_def = DataRegistry.get_npc(npc_id)
		npc_name_label.text = npc_def.display_name if npc_def else npc_id

		var fs = PlayerData.npc_friendships.get(npc_id, {})
		var pts: int = int(fs.get("points", 0))
		_update_friendship_display(pts, _get_friendship_tier(pts))

		# Hide interactive elements — this is display-only
		_clear_choices()
		action_container.visible = false
		gift_panel.visible = false
		showing_gift_panel = false

		visible = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var full_text := message
	if points_change > 0:
		full_text += "\n[color=#%s](+%d friendship)[/color]" % [UITheme.bbcode_color("success"), points_change]
	elif points_change < 0:
		full_text += "\n[color=#%s](%d friendship)[/color]" % [UITheme.bbcode_color("danger"), points_change]
	_typewrite(dialogue_text, full_text)

	# Update from synced PlayerData
	var fs2 = PlayerData.npc_friendships.get(current_npc_id, {})
	var pts2: int = int(fs2.get("points", current_friendship))
	_update_friendship_display(pts2, _get_friendship_tier(pts2))

	if _gift_popup_mode:
		_schedule_auto_close(3.5)
	else:
		_hide_gift_panel()

# === Internal ===

func _update_friendship_display(points: int, tier: String) -> void:
	var tier_colors = {
		"hate": UITokens.TEXT_DANGER,
		"dislike": UITokens.TEXT_WARNING,
		"neutral": UITokens.INK_PRIMARY,
		"like": UITokens.TEXT_SUCCESS,
		"love": UITokens.STAMP_GOLD,
	}
	var color: Color = tier_colors.get(tier, UITokens.INK_PRIMARY)
	friendship_label.text = tier.capitalize() + " (" + str(points) + ")"
	friendship_label.modulate = color
	friendship_bar.value = points

func _clear_choices() -> void:
	for child in choices_container.get_children():
		child.queue_free()

func _on_choice_pressed(idx: int) -> void:
	# Disable all choice buttons while waiting
	for child in choices_container.get_children():
		if child is Button:
			child.disabled = true
	# Send choice to server
	var social_mgr = get_node_or_null("/root/Main/GameWorld/SocialManager")
	if social_mgr:
		social_mgr.request_dialogue_choice.rpc_id(1, idx)

func _on_continue() -> void:
	_clear_choices()
	action_container.visible = true

func _show_gift_panel() -> void:
	showing_gift_panel = true
	gift_panel.visible = true
	_populate_gift_list()

func _hide_gift_panel() -> void:
	showing_gift_panel = false
	gift_panel.visible = false

func _populate_gift_list() -> void:
	for child in gift_list.get_children():
		child.queue_free()

	# Get NPC gift preferences for color coding
	DataRegistry.ensure_loaded()
	var npc_def = DataRegistry.get_npc(current_npc_id)

	for item_id in PlayerData.inventory:
		var count: int = PlayerData.inventory[item_id]
		if count <= 0:
			continue
		# Skip non-giftable items (tools, recipe scrolls, fragments)
		if not DataRegistry.is_item_giftable(str(item_id)):
			continue
		var info = DataRegistry.get_item_display_info(item_id)

		var btn = Button.new()
		var display_name: String = info.get("display_name", item_id)
		var gift_tier: String = "neutral"
		if npc_def:
			gift_tier = _get_npc_gift_tier(npc_def, item_id)

		# Use plain text for button (RichTextLabel doesn't work well in buttons)
		var tier_plain = ""
		match gift_tier:
			"loved":
				tier_plain = " ★★★"
			"liked":
				tier_plain = " ★★"
			"disliked":
				tier_plain = " ✗"
			"hated":
				tier_plain = " ✗✗"

		btn.text = display_name + " (x" + str(count) + ")" + tier_plain
		UITheme.style_button(btn, "secondary")
		var captured_id = item_id
		btn.pressed.connect(_give_gift.bind(captured_id))

		# Color the button based on tier
		match gift_tier:
			"loved":
				btn.modulate = UITokens.STAMP_GOLD
			"liked":
				btn.modulate = UITokens.TEXT_SUCCESS
			"disliked":
				btn.modulate = UITokens.TEXT_WARNING
			"hated":
				btn.modulate = UITokens.TEXT_DANGER

		gift_list.add_child(btn)

	if gift_list.get_child_count() == 0:
		var empty_label = Label.new()
		empty_label.text = "No items to give"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UITheme.style_small(empty_label)
		gift_list.add_child(empty_label)

func _give_gift(item_id: String) -> void:
	# Find the nearest social NPC and send gift RPC
	var social_npcs = get_tree().get_nodes_in_group("social_npc")
	for npc in social_npcs:
		if npc.has_method("request_give_gift") and "npc_id" in npc and npc.npc_id == current_npc_id:
			npc.request_give_gift.rpc_id(1, item_id)
			break
	_hide_gift_panel()

func _get_friendship_tier(points: int) -> String:
	if points < -60:
		return "hate"
	elif points < -20:
		return "dislike"
	elif points < 20:
		return "neutral"
	elif points < 60:
		return "like"
	else:
		return "love"

func _get_npc_gift_tier(npc_def: Resource, item_id: String) -> String:
	var prefs: Dictionary = npc_def.gift_preferences
	if item_id in prefs.get("loved", []):
		return "loved"
	elif item_id in prefs.get("liked", []):
		return "liked"
	elif item_id in prefs.get("disliked", []):
		return "disliked"
	elif item_id in prefs.get("hated", []):
		return "hated"
	return "neutral"

func _typewrite(rtl: RichTextLabel, text: String) -> void:
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
		_typewriter_tween = null
	rtl.text = text
	var cps := UITheme.get_text_speed()
	if cps < 0:
		rtl.visible_characters = -1
		return
	var char_count := rtl.get_total_character_count()
	if char_count <= 0:
		rtl.visible_characters = -1
		return
	rtl.visible_characters = 0
	var duration := char_count / cps
	_typewriter_tween = create_tween()
	_typewriter_tween.tween_property(rtl, "visible_characters", char_count, duration)

func _skip_typewriter() -> void:
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
		_typewriter_tween = null
		dialogue_text.visible_characters = -1

func _schedule_auto_close(delay: float) -> void:
	if _auto_close_tween and _auto_close_tween.is_valid():
		_auto_close_tween.kill()
	_auto_close_tween = create_tween()
	_auto_close_tween.tween_callback(_close_popup).set_delay(delay)

func _close_popup() -> void:
	if _auto_close_tween and _auto_close_tween.is_valid():
		_auto_close_tween.kill()
		_auto_close_tween = null
	if _typewriter_tween and _typewriter_tween.is_valid():
		_typewriter_tween.kill()
		_typewriter_tween = null
	_gift_popup_mode = false
	visible = false
	gift_panel.visible = false
	showing_gift_panel = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _close() -> void:
	if _auto_close_tween and _auto_close_tween.is_valid():
		_auto_close_tween.kill()
		_auto_close_tween = null
	if _gift_popup_mode:
		_close_popup()
		return
	visible = false
	gift_panel.visible = false
	showing_gift_panel = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	NetworkManager.request_set_busy.rpc_id(1, false)
	# Cancel any pending dialogue on server
	var social_mgr = get_node_or_null("/root/Main/GameWorld/SocialManager")
	if social_mgr:
		social_mgr.cancel_dialogue.rpc_id(1)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_close()
		get_viewport().set_input_as_handled()
		return
	# Click-to-skip typewriter
	if _typewriter_tween and _typewriter_tween.is_valid():
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
			_skip_typewriter()
			get_viewport().set_input_as_handled()
			return
	# In popup mode, any key/click after typewriter finishes closes it
	if _gift_popup_mode:
		if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
			_close_popup()
			get_viewport().set_input_as_handled()
