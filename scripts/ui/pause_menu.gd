extends CanvasLayer

# Unified pause menu with tabbed sidebar. Consolidates Map, Inventory, Party,
# Quests, Compendium, Friends, and Settings into one overlay.
# Hotkeys: M/Esc=Map, I=Inventory, P=Party, J=Quests, K=Compendium, F=Friends, N=NPCs.

var is_open: bool = false

# UI structure
var bg: ColorRect
var main_hbox: HBoxContainer
var sidebar: VBoxContainer
var content_container: Control
var tab_buttons: Array[Button] = []
var active_tab_index: int = 0

# Tab content nodes
var tabs: Array[Control] = []

# Status header
var status_header: PanelContainer = null
var status_name_label: Label = null
var status_money_label: Label = null
var status_season_label: Label = null
var status_buffs_label: Label = null

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
	["Fishing", "", "res://scripts/ui/tabs/fishing_tab.gd"],
	["Friends", "friend_list", "res://scripts/ui/tabs/friend_tab.gd"],
	["NPCs", "open_npcs", "res://scripts/ui/tabs/npc_tab.gd"],
	["Settings", "", "res://scripts/ui/tabs/settings_tab.gd"],
]

const SIDEBAR_WIDTH := 120
const BLOCKING_UIS := ["BattleUI", "CraftingUI", "StorageUI", "ShopUI", "TradeUI", "DialogueUI", "CalendarUI", "CreatureDestinationUI"]
const UITokens = preload("res://scripts/ui/ui_tokens.gd")

func _ready() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	UITheme.init()
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
	bg.color = UITokens.SCRIM
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Main layout container
	main_hbox = HBoxContainer.new()
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_hbox.add_theme_constant_override("separation", 0)
	add_child(main_hbox)

	# Sidebar panel (left side)
	var sidebar_w := UITheme.scaled(SIDEBAR_WIDTH)
	var sidebar_bg := PanelContainer.new()
	sidebar_bg.custom_minimum_size.x = sidebar_w
	sidebar_bg.size_flags_horizontal = Control.SIZE_FILL
	sidebar_bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar_bg.add_theme_stylebox_override("panel", UITheme.make_sidebar_style())
	main_hbox.add_child(sidebar_bg)

	sidebar = VBoxContainer.new()
	sidebar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sidebar_bg.add_child(sidebar)

	# Title
	var title := Label.new()
	title.text = "MENU"
	UITheme.style_subheading(title)
	title.add_theme_color_override("font_color", UITokens.SIDEBAR_TEXT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sidebar.add_child(title)

	var sep := HSeparator.new()
	sidebar.add_child(sep)

	# Tab buttons
	for i in range(TAB_DEFS.size()):
		var def = TAB_DEFS[i]
		var btn := Button.new()
		btn.text = def[0]
		btn.custom_minimum_size.y = UITheme.scaled(32)
		UITheme.style_sidebar_button(btn)
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
	menu_btn.custom_minimum_size.y = UITheme.scaled(32)
	UITheme.style_sidebar_button(menu_btn)
	menu_btn.pressed.connect(_on_return_to_menu)
	sidebar.add_child(menu_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Quit"
	quit_btn.custom_minimum_size.y = UITheme.scaled(32)
	UITheme.style_sidebar_button(quit_btn)
	quit_btn.add_theme_color_override("font_color", UITokens.ACCENT_TOMATO)
	quit_btn.pressed.connect(_on_quit)
	sidebar.add_child(quit_btn)

	# Content area (right of sidebar) — wrapped in a PanelContainer for paper background
	var content_panel := PanelContainer.new()
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	UITheme.style_card(content_panel)
	main_hbox.add_child(content_panel)

	var content_vbox := VBoxContainer.new()
	content_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_panel.add_child(content_vbox)

	# Status header bar (always visible across all tabs)
	_build_status_header(content_vbox)

	content_container = Control.new()
	content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(content_container)

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
	UITheme.apply_panel(invite_popup)
	add_child(invite_popup)

	var vbox := VBoxContainer.new()
	invite_popup.add_child(vbox)

	invite_label = Label.new()
	invite_label.text = "Party invite from ..."
	UITheme.style_subheading(invite_label)
	invite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(invite_label)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)

	invite_accept_btn = Button.new()
	invite_accept_btn.text = "Accept"
	UITheme.style_button(invite_accept_btn, "secondary")
	invite_accept_btn.pressed.connect(_on_invite_accept)
	hbox.add_child(invite_accept_btn)

	invite_decline_btn = Button.new()
	invite_decline_btn.text = "Decline"
	UITheme.style_button(invite_decline_btn, "danger")
	invite_decline_btn.pressed.connect(_on_invite_decline)
	hbox.add_child(invite_decline_btn)

func _build_status_header(parent: VBoxContainer) -> void:
	status_header = PanelContainer.new()
	status_header.custom_minimum_size.y = UITheme.scaled(36)
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = UITokens.PAPER_EDGE
	header_style.set_corner_radius_all(UITokens.CORNER_RADIUS_SM)
	header_style.content_margin_left = 10
	header_style.content_margin_right = 10
	header_style.content_margin_top = 4
	header_style.content_margin_bottom = 4
	status_header.add_theme_stylebox_override("panel", header_style)
	parent.add_child(status_header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	status_header.add_child(hbox)

	status_name_label = Label.new()
	status_name_label.text = ""
	UITheme.style_body(status_name_label)
	hbox.add_child(status_name_label)

	status_money_label = Label.new()
	status_money_label.text = "$0"
	UITheme.style_body(status_money_label)
	status_money_label.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
	hbox.add_child(status_money_label)

	var sep := VSeparator.new()
	hbox.add_child(sep)

	status_season_label = Label.new()
	status_season_label.text = ""
	UITheme.style_body(status_season_label)
	status_season_label.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
	hbox.add_child(status_season_label)

	var sep2 := VSeparator.new()
	hbox.add_child(sep2)

	status_buffs_label = Label.new()
	status_buffs_label.text = ""
	UITheme.style_caption(status_buffs_label)
	status_buffs_label.add_theme_color_override("font_color", UITokens.TEXT_INFO)
	status_buffs_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(status_buffs_label)

func _refresh_status_header() -> void:
	if status_name_label == null:
		return
	status_name_label.text = PlayerData.player_name
	status_money_label.text = "$%s" % _format_money(PlayerData.money)

	# Season/day from SeasonManager
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	if season_mgr:
		var season_name: String = season_mgr.get_season_name() if season_mgr.has_method("get_season_name") else "???"
		var month_day: int = ((season_mgr.total_day_count - 1) % 28) + 1
		status_season_label.text = "%s Day %d" % [season_name.capitalize(), month_day]
	else:
		status_season_label.text = ""

	# Active buffs
	if PlayerData.active_buffs.size() > 0:
		var buff_parts := []
		for buff in PlayerData.active_buffs:
			var btype: String = str(buff.get("buff_type", "")).replace("_", " ").capitalize()
			buff_parts.append(btype)
		status_buffs_label.text = "Buffs: " + ", ".join(buff_parts)
	else:
		status_buffs_label.text = ""

static func _format_money(amount: int) -> String:
	var s := str(amount)
	if amount < 1000:
		return s
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result

func _input(event: InputEvent) -> void:
	if not _is_local_client():
		return

	# Skip hotkeys when a text input has focus (e.g., friend search bar)
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
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
		_handle_hotkey(6)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("open_npcs"):
		_handle_hotkey(7)
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
	_refresh_status_header()
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
		UITheme.style_sidebar_button(tab_buttons[i], i == active_tab_index)

func _on_tab_button_pressed(index: int) -> void:
	_switch_tab(index)

func _set_visible(v: bool) -> void:
	# CanvasLayer visible=false does NOT propagate to children.
	# Explicitly toggle each child.
	bg.visible = v
	main_hbox.visible = v
	if status_header:
		status_header.visible = v
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
		else:
			# Plain Node (e.g. BattleArenaUI): check for visible CanvasLayer children
			for sub in child.get_children():
				if sub is CanvasLayer and sub.visible:
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
