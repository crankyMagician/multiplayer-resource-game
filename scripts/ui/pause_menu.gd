extends CanvasLayer

# Unified pause menu with tabbed sidebar. Consolidates Map, Inventory, Party,
# Quests, Compendium, Friends, and Settings into one overlay.
# Hotkeys: M/Esc=Map, I=Inventory, P=Party, J=Quests, K=Compendium, F=Friends.

var is_open: bool = false

# UI structure
var bg: ColorRect
var sidebar: VBoxContainer
var content_container: Control
var tab_buttons: Array[Button] = []
var active_tab_index: int = 0

# Tab content nodes
var tabs: Array[Control] = []

# Party invite popup (always-visible, outside content container)
var invite_popup: PanelContainer
var invite_label: Label
var invite_accept_btn: Button
var invite_decline_btn: Button
var _pending_invite_party_id: int = -1

# Tab definitions: [name, hotkey_action, script_path]
const TAB_DEFS: Array = [
	["Map", "open_map", "res://scripts/ui/tabs/map_tab.gd"],
	["Inventory", "open_inventory", "res://scripts/ui/tabs/inventory_tab.gd"],
	["Party", "open_party", "res://scripts/ui/tabs/party_tab.gd"],
	["Quests", "quest_log", "res://scripts/ui/tabs/quest_tab.gd"],
	["Compendium", "compendium", "res://scripts/ui/tabs/compendium_tab.gd"],
	["Friends", "friend_list", "res://scripts/ui/tabs/friend_tab.gd"],
	["Settings", "", "res://scripts/ui/tabs/settings_tab.gd"],
]

const SIDEBAR_WIDTH := 120
const BLOCKING_UIS := ["BattleUI", "CraftingUI", "StorageUI", "ShopUI", "TradeUI", "DialogueUI", "CalendarUI", "CreatureDestinationUI"]

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_build_invite_popup()
	_set_visible(false)
	# Connect party invite signal (deferred so FriendManager exists)
	_connect_invite_signal.call_deferred()

func _connect_invite_signal() -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm and fm.has_signal("party_invite_received"):
		fm.party_invite_received.connect(_on_party_invite)

func _build_ui() -> void:
	# Dark semi-transparent background
	bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Sidebar panel (left side)
	var sidebar_bg := PanelContainer.new()
	sidebar_bg.anchor_left = 0.0
	sidebar_bg.anchor_top = 0.0
	sidebar_bg.anchor_right = 0.0
	sidebar_bg.anchor_bottom = 1.0
	sidebar_bg.offset_right = SIDEBAR_WIDTH
	add_child(sidebar_bg)

	sidebar = VBoxContainer.new()
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sidebar_bg.add_child(sidebar)

	# Title
	var title := Label.new()
	title.text = "MENU"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sidebar.add_child(title)

	var sep := HSeparator.new()
	sidebar.add_child(sep)

	# Tab buttons
	for i in range(TAB_DEFS.size()):
		var def = TAB_DEFS[i]
		var btn := Button.new()
		btn.text = def[0]
		btn.custom_minimum_size.y = 32
		btn.pressed.connect(_on_tab_button_pressed.bind(i))
		sidebar.add_child(btn)
		tab_buttons.append(btn)

	# Spacer
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(spacer)

	# Bottom buttons
	var sep2 := HSeparator.new()
	sidebar.add_child(sep2)

	var menu_btn := Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size.y = 32
	menu_btn.pressed.connect(_on_return_to_menu)
	sidebar.add_child(menu_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size.y = 32
	quit_btn.pressed.connect(_on_quit)
	sidebar.add_child(quit_btn)

	# Content area (right of sidebar)
	content_container = Control.new()
	content_container.anchor_left = 0.0
	content_container.anchor_top = 0.0
	content_container.anchor_right = 1.0
	content_container.anchor_bottom = 1.0
	content_container.offset_left = SIDEBAR_WIDTH + 10
	content_container.offset_top = 10
	content_container.offset_right = -10
	content_container.offset_bottom = -10
	add_child(content_container)

	# Create tab content controls
	for i in range(TAB_DEFS.size()):
		var def = TAB_DEFS[i]
		var tab_control := Control.new()
		tab_control.set_script(load(def[2]))
		tab_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tab_control.visible = false
		content_container.add_child(tab_control)
		tabs.append(tab_control)

func _build_invite_popup() -> void:
	invite_popup = PanelContainer.new()
	invite_popup.anchor_left = 0.3
	invite_popup.anchor_right = 0.7
	invite_popup.anchor_top = 0.35
	invite_popup.anchor_bottom = 0.5
	invite_popup.visible = false
	add_child(invite_popup)

	var vbox := VBoxContainer.new()
	invite_popup.add_child(vbox)

	invite_label = Label.new()
	invite_label.text = "Party invite from ..."
	invite_label.add_theme_font_size_override("font_size", 18)
	invite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(invite_label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	invite_accept_btn = Button.new()
	invite_accept_btn.text = "Accept"
	invite_accept_btn.pressed.connect(_on_invite_accept)
	hbox.add_child(invite_accept_btn)

	invite_decline_btn = Button.new()
	invite_decline_btn.text = "Decline"
	invite_decline_btn.pressed.connect(_on_invite_decline)
	hbox.add_child(invite_decline_btn)

func _input(event: InputEvent) -> void:
	if not _is_local_client():
		return

	# Check hotkeys
	if event.is_action_pressed("open_map"):
		_handle_hotkey(0)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("open_inventory"):
		_handle_hotkey(1)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("open_party"):
		_handle_hotkey(2)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("quest_log"):
		_handle_hotkey(3)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("compendium"):
		_handle_hotkey(4)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("friend_list"):
		_handle_hotkey(5)
		get_viewport().set_input_as_handled()
		return

	# Esc closes when open
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return

func _handle_hotkey(tab_index: int) -> void:
	if is_open:
		if active_tab_index == tab_index:
			close()
		else:
			_switch_tab(tab_index)
	else:
		if _is_other_ui_open():
			return
		_open(tab_index)

func open_to_tab(tab_name: String) -> void:
	for i in range(TAB_DEFS.size()):
		if TAB_DEFS[i][0] == tab_name:
			if is_open:
				_switch_tab(i)
			else:
				if not _is_other_ui_open():
					_open(i)
			return

func _open(tab_index: int = 0) -> void:
	is_open = true
	_switch_tab(tab_index)
	_set_visible(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if multiplayer.multiplayer_peer != null:
		NetworkManager.request_set_busy.rpc_id(1, true)

func close() -> void:
	if not is_open:
		return
	is_open = false
	# Deactivate current tab
	if active_tab_index < tabs.size():
		tabs[active_tab_index].visible = false
		if tabs[active_tab_index].has_method("deactivate"):
			tabs[active_tab_index].deactivate()
	_set_visible(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if multiplayer.multiplayer_peer != null:
		NetworkManager.request_set_busy.rpc_id(1, false)

func _switch_tab(tab_index: int) -> void:
	# Deactivate old tab
	if active_tab_index < tabs.size():
		tabs[active_tab_index].visible = false
		if tabs[active_tab_index].has_method("deactivate"):
			tabs[active_tab_index].deactivate()
	active_tab_index = tab_index
	# Activate new tab
	if active_tab_index < tabs.size():
		tabs[active_tab_index].visible = true
		if tabs[active_tab_index].has_method("activate"):
			tabs[active_tab_index].activate()
	# Update sidebar button highlights
	_update_sidebar_highlights()

func _update_sidebar_highlights() -> void:
	for i in range(tab_buttons.size()):
		if i == active_tab_index:
			tab_buttons[i].add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		else:
			tab_buttons[i].remove_theme_color_override("font_color")

func _on_tab_button_pressed(index: int) -> void:
	_switch_tab(index)

func _set_visible(v: bool) -> void:
	# CanvasLayer visible=false does NOT propagate to children.
	# Explicitly toggle each child.
	bg.visible = v
	sidebar.get_parent().visible = v # The PanelContainer
	content_container.visible = v
	if not v:
		for tab in tabs:
			tab.visible = false

func _is_other_ui_open() -> bool:
	var ui_node = get_node_or_null("/root/Main/GameWorld/UI")
	if ui_node == null:
		return false
	for ui_name in BLOCKING_UIS:
		var child = ui_node.get_node_or_null(ui_name)
		if child == null:
			continue
		if child is CanvasLayer:
			if not child.visible:
				continue
			for sub in child.get_children():
				if sub is Control and sub.visible:
					return true
		elif child is Control and child.visible:
			for sub in child.get_children():
				if sub is Control and sub.visible:
					return true
	return false

func _is_local_client() -> bool:
	if multiplayer.multiplayer_peer == null:
		return true
	return not multiplayer.is_server()

# === Delegate properties for external callers ===

var tracked_quest_id: String:
	get:
		var qt = _get_quest_tab()
		if qt:
			return qt.tracked_quest_id
		return ""
	set(value):
		var qt = _get_quest_tab()
		if qt:
			qt.tracked_quest_id = value

func show_npc_quests(quests_data: Array) -> void:
	var quest_tab = _get_quest_tab()
	if quest_tab:
		quest_tab.show_npc_quests(quests_data)

func show_next_quest_offer(quest_id: String, npc_id: String, dialogue: String, quest_data: Dictionary) -> void:
	var quest_tab = _get_quest_tab()
	if quest_tab:
		quest_tab.show_next_quest_offer(quest_id, npc_id, dialogue, quest_data)

func get_tracked_quest_info() -> Dictionary:
	var quest_tab = _get_quest_tab()
	if quest_tab and quest_tab.has_method("get_tracked_quest_info"):
		return quest_tab.get_tracked_quest_info()
	return {}

func _get_quest_tab() -> Control:
	# Quest tab is at index 3
	if tabs.size() > 3:
		return tabs[3]
	return null

# === Return to Menu / Quit ===

func _on_return_to_menu() -> void:
	close()
	# Disconnect from server
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	get_tree().change_scene_to_file("res://scenes/ui/connect_ui.tscn")

func _on_quit() -> void:
	get_tree().quit()

# === Party Invite Popup ===

func _on_party_invite(from_name: String, party_id: int) -> void:
	_pending_invite_party_id = party_id
	invite_label.text = "Party invite from " + from_name
	invite_popup.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_invite_accept() -> void:
	if _pending_invite_party_id >= 0:
		var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
		if fm:
			fm.request_accept_party_invite.rpc_id(1, _pending_invite_party_id)
	invite_popup.visible = false
	_pending_invite_party_id = -1

func _on_invite_decline() -> void:
	if _pending_invite_party_id >= 0:
		var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
		if fm:
			fm.request_decline_party_invite.rpc_id(1, _pending_invite_party_id)
	invite_popup.visible = false
	_pending_invite_party_id = -1
