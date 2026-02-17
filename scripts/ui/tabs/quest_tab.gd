extends Control

# Quest log tab content for PauseMenu. Ported from quest_log_ui.gd.

var tab_bar: TabBar
var quest_list: VBoxContainer
var detail_panel: VBoxContainer
var detail_name: Label
var detail_desc: RichTextLabel
var detail_objectives: VBoxContainer
var detail_rewards: Label
var action_button: Button
var tracked_quest_id: String = ""
var _current_tab: int = 0
var _npc_quests: Array = []
var _showing_npc_quests: bool = false

func _ready() -> void:
	_build_ui()
	PlayerData.quests_changed.connect(_refresh)

func _build_ui() -> void:
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)

	# Tab bar
	tab_bar = TabBar.new()
	tab_bar.add_tab("Active")
	tab_bar.add_tab("Completed")
	tab_bar.add_tab("Main Story")
	tab_bar.tab_changed.connect(_on_tab_changed)
	main_vbox.add_child(tab_bar)

	# Content split
	var hsplit := HSplitContainer.new()
	hsplit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(hsplit)

	# Left: quest list
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size = Vector2(250, 0)
	hsplit.add_child(left_scroll)

	quest_list = VBoxContainer.new()
	quest_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(quest_list)

	# Right: detail panel
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_child(right_scroll)

	detail_panel = VBoxContainer.new()
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(detail_panel)

	detail_name = Label.new()
	detail_name.add_theme_font_size_override("font_size", 20)
	detail_panel.add_child(detail_name)

	detail_desc = RichTextLabel.new()
	detail_desc.bbcode_enabled = true
	detail_desc.custom_minimum_size = Vector2(0, 80)
	detail_desc.fit_content = true
	detail_panel.add_child(detail_desc)

	detail_objectives = VBoxContainer.new()
	detail_panel.add_child(detail_objectives)

	detail_rewards = Label.new()
	detail_rewards.add_theme_font_size_override("font_size", 14)
	detail_rewards.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	detail_panel.add_child(detail_rewards)

	action_button = Button.new()
	action_button.text = "Track Quest"
	action_button.pressed.connect(_on_action_pressed)
	action_button.visible = false
	detail_panel.add_child(action_button)

func activate() -> void:
	_showing_npc_quests = false
	_npc_quests.clear()
	_refresh()

func deactivate() -> void:
	pass

func _on_tab_changed(tab: int) -> void:
	_current_tab = tab
	_showing_npc_quests = false
	_refresh()

func _refresh() -> void:
	for child in quest_list.get_children():
		child.queue_free()
	_clear_detail()

	if _showing_npc_quests:
		_refresh_npc_quests()
		return

	DataRegistry.ensure_loaded()

	match _current_tab:
		0:
			for quest_id in PlayerData.active_quests:
				var qdef = DataRegistry.get_quest(quest_id)
				if qdef and qdef.category != "main_story":
					_add_quest_button(quest_id, qdef, true)
		1:
			for quest_id in PlayerData.completed_quests:
				var qdef = DataRegistry.get_quest(quest_id)
				if qdef:
					_add_quest_button(quest_id, qdef, false)
		2:
			for quest_id in PlayerData.active_quests:
				var qdef = DataRegistry.get_quest(quest_id)
				if qdef and qdef.category == "main_story":
					_add_quest_button(quest_id, qdef, true)
			for quest_id in PlayerData.completed_quests:
				var qdef = DataRegistry.get_quest(quest_id)
				if qdef and qdef.category == "main_story":
					_add_quest_button(quest_id, qdef, false)

func _add_quest_button(quest_id: String, qdef: Resource, is_active: bool) -> void:
	var btn := Button.new()
	var prefix = ""
	if quest_id == tracked_quest_id:
		prefix = "> "
	if is_active:
		btn.text = prefix + qdef.display_name
	else:
		btn.text = prefix + qdef.display_name + " [Done]"
	btn.pressed.connect(_show_quest_detail.bind(quest_id, is_active))
	quest_list.add_child(btn)

func _clear_detail() -> void:
	detail_name.text = ""
	detail_desc.text = ""
	detail_rewards.text = ""
	action_button.visible = false
	for child in detail_objectives.get_children():
		child.queue_free()

func _show_quest_detail(quest_id: String, is_active: bool) -> void:
	DataRegistry.ensure_loaded()
	var qdef = DataRegistry.get_quest(quest_id)
	if qdef == null:
		return

	_clear_detail()
	detail_name.text = qdef.display_name
	detail_desc.text = qdef.description

	var quest_state = PlayerData.active_quests.get(quest_id, {})
	var obj_states = quest_state.get("objectives", [])
	for i in range(qdef.objectives.size()):
		var obj = qdef.objectives[i]
		var desc = str(obj.get("description", "Objective " + str(i + 1)))
		var target_count = int(obj.get("target_count", 1))
		var progress = 0
		if i < obj_states.size():
			progress = int(obj_states[i].get("progress", 0))

		var obj_label := Label.new()
		if is_active:
			var check = "[x] " if progress >= target_count else "[ ] "
			obj_label.text = check + desc + " (" + str(progress) + "/" + str(target_count) + ")"
			if progress >= target_count:
				obj_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		else:
			obj_label.text = "[x] " + desc
			obj_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		detail_objectives.add_child(obj_label)

	var reward_parts: Array = []
	if qdef.reward_money > 0:
		reward_parts.append("$" + str(qdef.reward_money))
	for item_id in qdef.reward_items:
		var info = DataRegistry.get_item_display_info(item_id)
		reward_parts.append(str(qdef.reward_items[item_id]) + "x " + info.get("display_name", item_id))
	if not reward_parts.is_empty():
		detail_rewards.text = "Rewards: " + ", ".join(reward_parts)

	if is_active:
		if qdef.category != "main_story":
			action_button.text = "Abandon Quest"
			action_button.visible = true
			if action_button.pressed.is_connected(_on_action_pressed):
				action_button.pressed.disconnect(_on_action_pressed)
			action_button.pressed.connect(_on_abandon.bind(quest_id))
		else:
			action_button.visible = false

func _on_action_pressed() -> void:
	pass

func _on_abandon(quest_id: String) -> void:
	var quest_mgr = get_node_or_null("/root/Main/GameWorld/QuestManager")
	if quest_mgr:
		quest_mgr.request_abandon_quest.rpc_id(1, quest_id)
	_refresh()

# === NPC Quest Interactions ===

func show_npc_quests(quests_data: Array) -> void:
	_npc_quests = quests_data
	_showing_npc_quests = true
	# Tell the pause menu to open to this tab
	var pause_menu = get_node_or_null("/root/Main/GameWorld/UI/PauseMenu")
	if pause_menu and not pause_menu.is_open:
		pause_menu.open_to_tab("Quests")
	_refresh_npc_quests()

func _refresh_npc_quests() -> void:
	for child in quest_list.get_children():
		child.queue_free()
	_clear_detail()

	for quest_data in _npc_quests:
		var btn := Button.new()
		var status = str(quest_data.get("status", ""))
		var name_text = str(quest_data.get("display_name", ""))
		match status:
			"available":
				btn.text = "! " + name_text
			"completable":
				btn.text = "? " + name_text + " [Turn In]"
			"in_progress":
				btn.text = "... " + name_text
		btn.pressed.connect(_show_npc_quest_detail.bind(quest_data))
		quest_list.add_child(btn)

	if _npc_quests.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No quests available."
		quest_list.add_child(empty_label)

func _show_npc_quest_detail(quest_data: Dictionary) -> void:
	_clear_detail()
	var status = str(quest_data.get("status", ""))
	detail_name.text = str(quest_data.get("display_name", ""))

	match status:
		"available":
			var dialogue = str(quest_data.get("offer_dialogue", ""))
			if dialogue != "":
				detail_desc.text = dialogue + "\n\n" + str(quest_data.get("description", ""))
			else:
				detail_desc.text = str(quest_data.get("description", ""))
			var objectives = quest_data.get("objectives", [])
			for i in range(objectives.size()):
				var obj = objectives[i]
				var obj_label := Label.new()
				obj_label.text = "[ ] " + str(obj.get("description", "Objective " + str(i + 1)))
				detail_objectives.add_child(obj_label)
			var reward_parts: Array = []
			var money = int(quest_data.get("reward_money", 0))
			if money > 0:
				reward_parts.append("$" + str(money))
			var items = quest_data.get("reward_items", {})
			for item_id in items:
				var info = DataRegistry.get_item_display_info(item_id)
				reward_parts.append(str(items[item_id]) + "x " + info.get("display_name", item_id))
			if not reward_parts.is_empty():
				detail_rewards.text = "Rewards: " + ", ".join(reward_parts)
			action_button.text = "Accept Quest"
			action_button.visible = true
			if action_button.pressed.is_connected(_on_action_pressed):
				action_button.pressed.disconnect(_on_action_pressed)
			for conn in action_button.pressed.get_connections():
				action_button.pressed.disconnect(conn.callable)
			action_button.pressed.connect(_on_accept_quest.bind(str(quest_data.get("quest_id", ""))))

		"completable":
			var dialogue = str(quest_data.get("completion_dialogue", ""))
			detail_desc.text = dialogue if dialogue != "" else "Quest complete! Turn in for rewards."
			action_button.text = "Complete Quest"
			action_button.visible = true
			for conn in action_button.pressed.get_connections():
				action_button.pressed.disconnect(conn.callable)
			action_button.pressed.connect(_on_complete_quest.bind(str(quest_data.get("quest_id", ""))))

		"in_progress":
			var dialogue = str(quest_data.get("in_progress_dialogue", ""))
			detail_desc.text = dialogue if dialogue != "" else "Quest in progress..."
			action_button.visible = false

func _on_accept_quest(quest_id: String) -> void:
	var quest_mgr = get_node_or_null("/root/Main/GameWorld/QuestManager")
	if quest_mgr:
		quest_mgr.request_accept_quest.rpc_id(1, quest_id)
	# Close the pause menu after accepting
	var pause_menu = get_node_or_null("/root/Main/GameWorld/UI/PauseMenu")
	if pause_menu:
		pause_menu.close()

func _on_complete_quest(quest_id: String) -> void:
	var quest_mgr = get_node_or_null("/root/Main/GameWorld/QuestManager")
	if quest_mgr:
		quest_mgr.request_complete_quest.rpc_id(1, quest_id)
	var pause_menu = get_node_or_null("/root/Main/GameWorld/UI/PauseMenu")
	if pause_menu:
		pause_menu.close()

func show_next_quest_offer(quest_id: String, _npc_id: String, _dialogue: String, quest_data: Dictionary) -> void:
	quest_data["status"] = "available"
	quest_data["offer_dialogue"] = _dialogue
	show_npc_quests([quest_data])

# === HUD Tracker ===

func get_tracked_quest_info() -> Dictionary:
	if tracked_quest_id == "" or tracked_quest_id not in PlayerData.active_quests:
		return {}
	DataRegistry.ensure_loaded()
	var qdef = DataRegistry.get_quest(tracked_quest_id)
	if qdef == null:
		return {}
	var state = PlayerData.active_quests[tracked_quest_id]
	return {"quest_id": tracked_quest_id, "display_name": qdef.display_name, "objectives": qdef.objectives, "state": state}
