extends CanvasLayer

## Friend list & party UI — toggled with F key.
## 4 tabs: Friends, Requests, Party, Blocked.

var panel: PanelContainer
var tab_bar: TabBar
var content_scroll: ScrollContainer
var content_list: VBoxContainer
var search_bar: LineEdit
var send_request_btn: Button
var close_button: Button
var _current_tab: int = 0

# Party invite popup
var invite_popup: PanelContainer
var invite_label: Label
var invite_accept_btn: Button
var invite_decline_btn: Button
var _pending_invite_party_id: int = -1

func _ready() -> void:
	layer = 10
	visible = false
	_build_ui()
	_build_invite_popup()
	PlayerData.player_friends_changed.connect(_refresh)
	PlayerData.player_party_updated.connect(_refresh)
	# Listen for party invites
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.party_invite_received.connect(_on_party_invite)

func _build_ui() -> void:
	panel = PanelContainer.new()
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.anchor_top = 0.05
	panel.anchor_bottom = 0.95

	var main_vbox = VBoxContainer.new()
	panel.add_child(main_vbox)

	# Header row
	var header = HBoxContainer.new()
	main_vbox.add_child(header)

	var title = Label.new()
	title.text = "Friends & Party"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	close_button = Button.new()
	close_button.text = "X"
	close_button.pressed.connect(close)
	header.add_child(close_button)

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
	var bottom = HBoxContainer.new()
	main_vbox.add_child(bottom)

	search_bar = LineEdit.new()
	search_bar.placeholder_text = "Player name..."
	search_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(search_bar)

	send_request_btn = Button.new()
	send_request_btn.text = "Send Request"
	send_request_btn.pressed.connect(_on_send_request)
	bottom.add_child(send_request_btn)

	add_child(panel)

func _build_invite_popup() -> void:
	invite_popup = PanelContainer.new()
	invite_popup.anchor_left = 0.3
	invite_popup.anchor_right = 0.7
	invite_popup.anchor_top = 0.35
	invite_popup.anchor_bottom = 0.5
	invite_popup.visible = false

	var vbox = VBoxContainer.new()
	invite_popup.add_child(vbox)

	invite_label = Label.new()
	invite_label.text = "Party invite from ..."
	invite_label.add_theme_font_size_override("font_size", 18)
	invite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(invite_label)

	var hbox = HBoxContainer.new()
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

	add_child(invite_popup)

func toggle() -> void:
	visible = !visible
	if visible:
		# Sync from server
		var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
		if fm:
			fm.request_friends_sync.rpc_id(1)
		NetworkManager.request_set_busy.rpc_id(1, true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_refresh()
	else:
		NetworkManager.request_set_busy.rpc_id(1, false)

func close() -> void:
	if visible:
		visible = false
		NetworkManager.request_set_busy.rpc_id(1, false)

func _on_tab_changed(idx: int) -> void:
	_current_tab = idx
	_refresh()

func _refresh() -> void:
	if not visible:
		return
	# Clear existing content
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
		var hbox = HBoxContainer.new()
		content_list.add_child(hbox)
		var name_str = str(friend.get("player_name", "Unknown"))
		var online = friend.get("online", false)
		if name_str == "":
			name_str = str(friend.get("player_id", "???")).substr(0, 8)
		var status_icon = "[ON] " if online else "[OFF] "
		var lbl = Label.new()
		lbl.text = status_icon + name_str
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if online:
			lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		else:
			lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		hbox.add_child(lbl)
		var friend_id = str(friend.get("player_id", ""))
		# Invite to party button (if we're party leader and friend is online)
		if online and PlayerData.group_party_id >= 0 and PlayerData.group_party_leader_id == _get_my_player_id():
			var invite_btn = Button.new()
			invite_btn.text = "Invite"
			invite_btn.pressed.connect(_on_invite_friend.bind(friend_id))
			hbox.add_child(invite_btn)
		var remove_btn = Button.new()
		remove_btn.text = "Remove"
		remove_btn.pressed.connect(_on_remove_friend.bind(friend_id))
		hbox.add_child(remove_btn)
		var block_btn = Button.new()
		block_btn.text = "Block"
		block_btn.pressed.connect(_on_block_player.bind(name_str))
		hbox.add_child(block_btn)

# === Requests Tab ===

func _build_requests_tab() -> void:
	if not PlayerData.incoming_friend_requests.is_empty():
		_add_label("Incoming Requests:")
		for req in PlayerData.incoming_friend_requests:
			var hbox = HBoxContainer.new()
			content_list.add_child(hbox)
			var lbl = Label.new()
			lbl.text = str(req.get("from_name", "Unknown"))
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(lbl)
			var from_id = str(req.get("from_id", ""))
			var accept_btn = Button.new()
			accept_btn.text = "Accept"
			accept_btn.pressed.connect(_on_accept_request.bind(from_id))
			hbox.add_child(accept_btn)
			var decline_btn = Button.new()
			decline_btn.text = "Decline"
			decline_btn.pressed.connect(_on_decline_request.bind(from_id))
			hbox.add_child(decline_btn)

	if not PlayerData.outgoing_friend_requests.is_empty():
		_add_label("Outgoing Requests:")
		for req in PlayerData.outgoing_friend_requests:
			var hbox = HBoxContainer.new()
			content_list.add_child(hbox)
			var lbl = Label.new()
			lbl.text = str(req.get("to_name", "Unknown")) + " (pending)"
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
			hbox.add_child(lbl)
			var to_id = str(req.get("to_id", ""))
			var cancel_btn = Button.new()
			cancel_btn.text = "Cancel"
			cancel_btn.pressed.connect(_on_cancel_request.bind(to_id))
			hbox.add_child(cancel_btn)

	if PlayerData.incoming_friend_requests.is_empty() and PlayerData.outgoing_friend_requests.is_empty():
		_add_label("No pending requests.")

# === Party Tab ===

func _build_party_tab() -> void:
	var my_id = _get_my_player_id()
	if PlayerData.group_party_id < 0:
		_add_label("Not in a party.")
		var create_btn = Button.new()
		create_btn.text = "Create Party"
		create_btn.pressed.connect(_on_create_party)
		content_list.add_child(create_btn)
		return
	_add_label("Party (ID: " + str(PlayerData.group_party_id) + ")")
	for member in PlayerData.group_party_members:
		var hbox = HBoxContainer.new()
		content_list.add_child(hbox)
		var name_str = str(member.get("player_name", "Unknown"))
		var mid = str(member.get("player_id", ""))
		var is_leader = mid == PlayerData.group_party_leader_id
		var prefix = "[Leader] " if is_leader else ""
		var online = member.get("online", false)
		var status = " (online)" if online else " (offline)"
		var lbl = Label.new()
		lbl.text = prefix + name_str + status
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if is_leader:
			lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		elif online:
			lbl.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
		hbox.add_child(lbl)
		# Leader actions on non-self members
		if my_id == PlayerData.group_party_leader_id and mid != my_id:
			var kick_btn = Button.new()
			kick_btn.text = "Kick"
			kick_btn.pressed.connect(_on_kick_member.bind(mid))
			hbox.add_child(kick_btn)
			var transfer_btn = Button.new()
			transfer_btn.text = "Promote"
			transfer_btn.pressed.connect(_on_transfer_leader.bind(mid))
			hbox.add_child(transfer_btn)
	# Leave button
	var leave_btn = Button.new()
	leave_btn.text = "Leave Party"
	leave_btn.pressed.connect(_on_leave_party)
	content_list.add_child(leave_btn)

# === Blocked Tab ===

func _build_blocked_tab() -> void:
	if PlayerData.blocked_players.is_empty():
		_add_label("No blocked players.")
		return
	for blocked_id in PlayerData.blocked_players:
		var hbox = HBoxContainer.new()
		content_list.add_child(hbox)
		var lbl = Label.new()
		lbl.text = str(blocked_id).substr(0, 12) + "..."
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(lbl)
		var unblock_btn = Button.new()
		unblock_btn.text = "Unblock"
		unblock_btn.pressed.connect(_on_unblock.bind(str(blocked_id)))
		hbox.add_child(unblock_btn)

# === Helper ===

func _add_label(text: String) -> void:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	content_list.add_child(lbl)

func _get_my_player_id() -> String:
	return PlayerData.player_id

# === Button Callbacks ===

func _on_send_request() -> void:
	var target = search_bar.text.strip_edges()
	if target == "":
		return
	var fm = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if fm:
		fm.request_send_friend_request.rpc_id(1, target)
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

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
