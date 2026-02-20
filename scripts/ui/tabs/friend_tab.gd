extends Control

# Friends & party tab content for PauseMenu. Ported from friend_list_ui.gd.
const UITokens = preload("res://scripts/ui/ui_tokens.gd")

var tab_bar: TabBar
var content_scroll: ScrollContainer
var content_list: VBoxContainer
var search_bar: LineEdit
var send_request_btn: Button
var _current_tab: int = 0

func _ready() -> void:
	UITheme.init()
	_build_ui()
	PlayerData.player_friends_changed.connect(_refresh)
	PlayerData.player_party_updated.connect(_refresh)

func _build_ui() -> void:
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_vbox)

	# Tab bar
	tab_bar = TabBar.new()
	tab_bar.add_tab("Friends")
	tab_bar.add_tab("Requests")
	tab_bar.add_tab("Party")
	tab_bar.add_tab("Blocked")
	tab_bar.tab_changed.connect(_on_tab_changed)
	main_vbox.add_child(tab_bar)

	# Content
	content_scroll = ScrollContainer.new()
	content_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(content_scroll)

	content_list = VBoxContainer.new()
	content_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_scroll.add_child(content_list)

	# Bottom bar: search + send request
	var bottom := HBoxContainer.new()
	main_vbox.add_child(bottom)

	search_bar = LineEdit.new()
	search_bar.placeholder_text = "Player name..."
	search_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	UITheme.style_input(search_bar)
	bottom.add_child(search_bar)

	send_request_btn = Button.new()
	send_request_btn.text = "Send Request"
	UITheme.style_button(send_request_btn, "secondary")
	send_request_btn.pressed.connect(_on_send_request)
	bottom.add_child(send_request_btn)

func activate() -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	print("[FM-DEBUG-UI] activate: fm=", fm, " friends=", PlayerData.friends.size(), " incoming=", PlayerData.incoming_friend_requests.size(), " outgoing=", PlayerData.outgoing_friend_requests.size())
	if fm:
		fm.request_friends_sync.rpc_id(1)
	_refresh()

func deactivate() -> void:
	pass

func _on_tab_changed(idx: int) -> void:
	_current_tab = idx
	_refresh()

func _refresh() -> void:
	for child in content_list.get_children():
		child.queue_free()
	match _current_tab:
		0: _build_friends_tab()
		1: _build_requests_tab()
		2: _build_party_tab()
		3: _build_blocked_tab()

# === Friends Tab ===

func _build_friends_tab() -> void:
	if PlayerData.friends.is_empty():
		_add_label("No friends yet. Send a request below!")
		return
	for friend in PlayerData.friends:
		var hbox := HBoxContainer.new()
		content_list.add_child(hbox)
		var name_str = str(friend.get("player_name", "Unknown"))
		var online = friend.get("online", false)
		if name_str == "":
			name_str = str(friend.get("player_id", "???")).substr(0, 8)
		var status_icon = "[ON] " if online else "[OFF] "
		var lbl := Label.new()
		lbl.text = status_icon + name_str
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if online:
			lbl.add_theme_color_override("font_color", UITokens.TEXT_SUCCESS)
		else:
			lbl.add_theme_color_override("font_color", UITokens.TEXT_MUTED)
		UITheme.style_small(lbl)
		hbox.add_child(lbl)
		var friend_id = str(friend.get("player_id", ""))
		if online and PlayerData.group_party_id >= 0 and PlayerData.group_party_leader_id == _get_my_player_id():
			var invite_btn := Button.new()
			invite_btn.text = "Invite"
			UITheme.style_button(invite_btn, "secondary")
			invite_btn.pressed.connect(_on_invite_friend.bind(friend_id))
			hbox.add_child(invite_btn)
		var remove_btn := Button.new()
		remove_btn.text = "Remove"
		UITheme.style_button(remove_btn, "danger")
		remove_btn.pressed.connect(_on_remove_friend.bind(friend_id))
		hbox.add_child(remove_btn)
		var block_btn := Button.new()
		block_btn.text = "Block"
		UITheme.style_button(block_btn, "danger")
		block_btn.pressed.connect(_on_block_player.bind(name_str))
		hbox.add_child(block_btn)

# === Requests Tab ===

func _build_requests_tab() -> void:
	if not PlayerData.incoming_friend_requests.is_empty():
		_add_label("Incoming Requests:")
		for req in PlayerData.incoming_friend_requests:
			var hbox := HBoxContainer.new()
			content_list.add_child(hbox)
			var lbl := Label.new()
			lbl.text = str(req.get("from_name", "Unknown"))
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UITheme.style_small(lbl)
			hbox.add_child(lbl)
			var from_id = str(req.get("from_id", ""))
			var accept_btn := Button.new()
			accept_btn.text = "Accept"
			UITheme.style_button(accept_btn, "primary")
			accept_btn.pressed.connect(_on_accept_request.bind(from_id))
			hbox.add_child(accept_btn)
			var decline_btn := Button.new()
			decline_btn.text = "Decline"
			UITheme.style_button(decline_btn, "danger")
			decline_btn.pressed.connect(_on_decline_request.bind(from_id))
			hbox.add_child(decline_btn)

	if not PlayerData.outgoing_friend_requests.is_empty():
		_add_label("Outgoing Requests:")
		for req in PlayerData.outgoing_friend_requests:
			var hbox := HBoxContainer.new()
			content_list.add_child(hbox)
			var lbl := Label.new()
			lbl.text = str(req.get("to_name", "Unknown")) + " (pending)"
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			UITheme.style_small(lbl)
			lbl.add_theme_color_override("font_color", UITokens.TEXT_WARNING)
			hbox.add_child(lbl)
			var to_id = str(req.get("to_id", ""))
			var cancel_btn := Button.new()
			cancel_btn.text = "Cancel"
			UITheme.style_button(cancel_btn, "danger")
			cancel_btn.pressed.connect(_on_cancel_request.bind(to_id))
			hbox.add_child(cancel_btn)

	if PlayerData.incoming_friend_requests.is_empty() and PlayerData.outgoing_friend_requests.is_empty():
		_add_label("No pending requests.")

# === Party Tab ===

func _build_party_tab() -> void:
	var my_id = _get_my_player_id()
	if PlayerData.group_party_id < 0:
		_add_label("Not in a party.")
		var create_btn := Button.new()
		create_btn.text = "Create Party"
		UITheme.style_button(create_btn, "primary")
		create_btn.pressed.connect(_on_create_party)
		content_list.add_child(create_btn)
		return
	_add_label("Party (ID: " + str(PlayerData.group_party_id) + ")")
	for member in PlayerData.group_party_members:
		var hbox := HBoxContainer.new()
		content_list.add_child(hbox)
		var name_str = str(member.get("player_name", "Unknown"))
		var mid = str(member.get("player_id", ""))
		var is_leader = mid == PlayerData.group_party_leader_id
		var prefix = "[Leader] " if is_leader else ""
		var online = member.get("online", false)
		var status = " (online)" if online else " (offline)"
		var lbl := Label.new()
		lbl.text = prefix + name_str + status
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_leader:
			lbl.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
		elif online:
			lbl.add_theme_color_override("font_color", UITokens.TEXT_SUCCESS)
		UITheme.style_small(lbl)
		hbox.add_child(lbl)
		if my_id == PlayerData.group_party_leader_id and mid != my_id:
			var kick_btn := Button.new()
			kick_btn.text = "Kick"
			UITheme.style_button(kick_btn, "danger")
			kick_btn.pressed.connect(_on_kick_member.bind(mid))
			hbox.add_child(kick_btn)
			var transfer_btn := Button.new()
			transfer_btn.text = "Promote"
			UITheme.style_button(transfer_btn, "secondary")
			transfer_btn.pressed.connect(_on_transfer_leader.bind(mid))
			hbox.add_child(transfer_btn)
		var leave_btn := Button.new()
		leave_btn.text = "Leave Party"
		UITheme.style_button(leave_btn, "danger")
		leave_btn.pressed.connect(_on_leave_party)
		content_list.add_child(leave_btn)

# === Blocked Tab ===

func _build_blocked_tab() -> void:
	if PlayerData.blocked_players.is_empty():
		_add_label("No blocked players.")
		return
	for entry in PlayerData.blocked_players:
		var hbox := HBoxContainer.new()
		content_list.add_child(hbox)
		var lbl := Label.new()
		# Support both new dict format {player_id, player_name} and old plain string format
		var blocked_id := ""
		var display_name := ""
		if entry is Dictionary:
			blocked_id = str(entry.get("player_id", ""))
			display_name = str(entry.get("player_name", ""))
		else:
			blocked_id = str(entry)
		if display_name == "":
			display_name = blocked_id.substr(0, 8) + "..."
		lbl.text = display_name
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		UITheme.style_small(lbl)
		hbox.add_child(lbl)
		var unblock_btn := Button.new()
		unblock_btn.text = "Unblock"
		UITheme.style_button(unblock_btn, "secondary")
		unblock_btn.pressed.connect(_on_unblock.bind(blocked_id))
		hbox.add_child(unblock_btn)

# === Helper ===

func _add_label(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	UITheme.style_small(lbl)
	content_list.add_child(lbl)

func _get_my_player_id() -> String:
	return PlayerData.player_id

# === Button Callbacks ===

func _on_send_request() -> void:
	var target = search_bar.text.strip_edges()
	print("[FM-DEBUG-UI] _on_send_request: target='", target, "'")
	if target == "":
		return
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	print("[FM-DEBUG-UI]   fm=", fm, " path_exists=", fm != null)
	if fm:
		fm.request_send_friend_request.rpc_id(1, target)
		print("[FM-DEBUG-UI]   RPC sent to server")
	search_bar.text = ""

func _on_accept_request(from_id: String) -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_accept_friend_request.rpc_id(1, from_id)

func _on_decline_request(from_id: String) -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_decline_friend_request.rpc_id(1, from_id)

func _on_cancel_request(to_id: String) -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_cancel_friend_request.rpc_id(1, to_id)

func _on_remove_friend(friend_id: String) -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_remove_friend.rpc_id(1, friend_id)

func _on_block_player(player_name: String) -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_block_player.rpc_id(1, player_name)

func _on_unblock(player_id: String) -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_unblock_player.rpc_id(1, player_id)

func _on_invite_friend(friend_id: String) -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_invite_to_party.rpc_id(1, friend_id)

func _on_create_party() -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_create_party.rpc_id(1)

func _on_leave_party() -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_leave_party.rpc_id(1)

func _on_kick_member(player_id: String) -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_kick_from_party.rpc_id(1, player_id)

func _on_transfer_leader(player_id: String) -> void:
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_transfer_leadership.rpc_id(1, player_id)
