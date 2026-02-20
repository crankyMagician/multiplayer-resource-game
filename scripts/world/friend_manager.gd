extends Node

## Server-authoritative friend list + party system.
## Child of GameWorld. No class_name (follows SocialManager/QuestManager pattern).

# === Constants ===
const MAX_PENDING_REQUESTS = 20
const MAX_FRIENDS = 100
const MAX_BLOCKED = 50
const PARTY_INVITE_TTL_SEC = 60
const MAX_PARTY_SIZE = 4

# === Party Runtime State (server-only, NOT persisted) ===
var parties: Dictionary = {}           # party_id -> {party_id, leader_id, members: [player_ids], invites: {player_id -> {invited_at}}}
var player_party_map: Dictionary = {}  # player_id -> party_id
var _next_party_id: int = 1

# === Pair-lock for friend mutations ===
var _friend_locks: Dictionary = {}

func _pair_key(a: String, b: String) -> String:
	return a + ":" + b if a < b else b + ":" + a

func _acquire_lock(key: String) -> bool:
	if _friend_locks.has(key):
		return false
	_friend_locks[key] = true
	return true

func _release_lock(key: String) -> void:
	_friend_locks.erase(key)

# === Helpers ===

func _get_nm() -> Node:
	return get_node_or_null("/root/NetworkManager")

func _get_social(peer_id: int) -> Dictionary:
	var nm = _get_nm()
	if nm == null or peer_id not in nm.player_data_store:
		return {}
	var data = nm.player_data_store[peer_id]
	if not data.has("social"):
		data["social"] = {"friends": [], "blocked": [], "incoming_requests": [], "outgoing_requests": []}
	var social = data["social"]
	# Ensure all expected keys exist (guards against partial saves from MongoDB)
	if not social.has("friends"):
		social["friends"] = []
	if not social.has("blocked"):
		social["blocked"] = []
	if not social.has("incoming_requests"):
		social["incoming_requests"] = []
	if not social.has("outgoing_requests"):
		social["outgoing_requests"] = []
	return social

func _get_player_id(peer_id: int) -> String:
	var nm = _get_nm()
	if nm == null:
		return ""
	return nm.get_player_id_for_peer(peer_id)

func _get_player_name_for_peer(peer_id: int) -> String:
	var nm = _get_nm()
	if nm == null or peer_id not in nm.player_data_store:
		return ""
	return str(nm.player_data_store[peer_id].get("player_name", ""))

func _is_blocked(social_a: Dictionary, player_id_b: String) -> bool:
	return player_id_b in social_a.get("blocked", [])

func _are_friends(social: Dictionary, player_id: String) -> bool:
	return player_id in social.get("friends", [])

func _has_outgoing_to(social: Dictionary, to_id: String) -> bool:
	for req in social.get("outgoing_requests", []):
		if str(req.get("to_id", "")) == to_id:
			return true
	return false

func _has_incoming_from(social: Dictionary, from_id: String) -> bool:
	for req in social.get("incoming_requests", []):
		if str(req.get("from_id", "")) == from_id:
			return true
	return false

func _save_peer(peer_id: int) -> void:
	var nm = _get_nm()
	if nm == null or peer_id not in nm.player_data_store:
		return
	SaveManager.save_player(nm.player_data_store[peer_id])

## Push updated social data to a client so their PlayerData stays in sync.
func _push_sync_to_peer(peer_id: int) -> void:
	var nm = _get_nm()
	if nm == null or peer_id not in nm.player_data_store:
		return
	var social = _get_social(peer_id)
	if social.is_empty():
		return
	nm._prune_expired_requests(nm.player_data_store[peer_id])
	var friends_out: Array = []
	for friend_id in social.get("friends", []):
		var f_peer = nm.get_peer_for_player_id(str(friend_id))
		var f_name = ""
		if f_peer > 0:
			f_name = _get_player_name_for_peer(f_peer)
		friends_out.append({"player_id": str(friend_id), "player_name": f_name, "online": f_peer > 0})
	_sync_friends_list.rpc_id(peer_id, friends_out, social.get("incoming_requests", []), social.get("outgoing_requests", []), social.get("blocked", []))

func _patch_offline(player_id: String, ops: Dictionary) -> void:
	SaveManager.update_player_social(player_id, ops)

# === Disconnect Handler ===

func handle_disconnect(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	var player_id = _get_player_id(peer_id)
	if player_id == "":
		return
	# Handle party disconnect
	if player_id in player_party_map:
		var party_id = player_party_map[player_id]
		var party = parties.get(party_id)
		if party != null:
			var members: Array = party["members"]
			members.erase(player_id)
			# Remove any invites from this player
			party["invites"].erase(player_id)
			if members.is_empty():
				# Disband
				parties.erase(party_id)
			elif str(party["leader_id"]) == player_id:
				# Transfer leadership
				party["leader_id"] = members[0]
				_sync_party_to_all(party_id, "Leader disconnected.")
			else:
				_sync_party_to_all(party_id)
		player_party_map.erase(player_id)
	# Clean up pending invites to this player in all parties
	for pid in parties:
		parties[pid]["invites"].erase(player_id)

# ========================================
# === FRIEND RPCs: Client -> Server ===
# ========================================

@rpc("any_peer", "reliable")
func request_send_friend_request(target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	var sender_name = _get_player_name_for_peer(sender_peer)
	if sender_id == "" or sender_name == "":
		return
	var sender_social = _get_social(sender_peer)
	if sender_social.is_empty():
		return
	# Self-check
	if target_name == sender_name:
		_friend_action_result.rpc_id(sender_peer, "send_request", false, "Cannot send request to yourself.")
		return
	# Pending cap
	if sender_social.get("outgoing_requests", []).size() >= MAX_PENDING_REQUESTS:
		_friend_action_result.rpc_id(sender_peer, "send_request", false, "Too many pending requests.")
		return
	# Resolve target: try online first
	var target_peer = 0
	var target_id = ""
	for p_name in nm.active_player_names:
		if p_name == target_name:
			target_peer = nm.active_player_names[p_name]
			target_id = _get_player_id(target_peer)
			break
	# Offline lookup via SaveManager if not online
	if target_id == "":
		# We need async lookup — use signal
		SaveManager.player_loaded.connect(_on_friend_request_target_loaded.bind(sender_peer, sender_id, sender_name, target_name), CONNECT_ONE_SHOT)
		SaveManager.load_player_async(target_name)
		return
	# Online target — process directly
	_process_friend_request(sender_peer, sender_id, sender_name, target_peer, target_id, target_name)

func _on_friend_request_target_loaded(loaded_name: String, data: Dictionary, sender_peer: int, sender_id: String, sender_name: String, target_name: String) -> void:
	if loaded_name != target_name:
		return
	if data.is_empty():
		_friend_action_result.rpc_id(sender_peer, "send_request", false, "Player '" + target_name + "' not found.")
		return
	var target_id = str(data.get("player_id", ""))
	if target_id == "":
		_friend_action_result.rpc_id(sender_peer, "send_request", false, "Player '" + target_name + "' has no ID.")
		return
	_process_friend_request(sender_peer, sender_id, sender_name, 0, target_id, target_name)

func _process_friend_request(sender_peer: int, sender_id: String, sender_name: String, target_peer: int, target_id: String, target_name: String) -> void:
	var sender_social = _get_social(sender_peer)
	# Block checks (both directions)
	if _is_blocked(sender_social, target_id):
		_friend_action_result.rpc_id(sender_peer, "send_request", false, "Cannot send request to this player.")
		return
	if target_peer > 0:
		var target_social = _get_social(target_peer)
		if _is_blocked(target_social, sender_id):
			_friend_action_result.rpc_id(sender_peer, "send_request", false, "Cannot send request to this player.")
			return
	# Already friends?
	if _are_friends(sender_social, target_id):
		_friend_action_result.rpc_id(sender_peer, "send_request", false, "Already friends with " + target_name + ".")
		return
	# Duplicate request?
	if _has_outgoing_to(sender_social, target_id):
		_friend_action_result.rpc_id(sender_peer, "send_request", false, "Request already sent to " + target_name + ".")
		return
	# Cross-request check: if target has an outgoing to sender, auto-accept
	if target_peer > 0:
		var target_social = _get_social(target_peer)
		if _has_outgoing_to(target_social, sender_id):
			# Auto-accept
			_do_accept_friend(sender_peer, sender_id, sender_name, target_peer, target_id, target_name)
			return
	# Check if target has pending incoming from sender already (shouldn't happen, but guard)
	var now = Time.get_unix_time_from_system()
	# Add outgoing to sender
	sender_social.get("outgoing_requests", []).append({"to_id": target_id, "to_name": target_name, "sent_at": now})
	# Add incoming to target
	if target_peer > 0:
		var target_social = _get_social(target_peer)
		target_social.get("incoming_requests", []).append({"from_id": sender_id, "from_name": sender_name, "sent_at": now})
		_save_peer(target_peer)
		_notify_friend_request.rpc_id(target_peer, sender_name, sender_id)
		_push_sync_to_peer(target_peer)
	else:
		# Offline target — PATCH MongoDB
		_patch_offline(target_id, {"add_incoming_request": {"from_id": sender_id, "from_name": sender_name, "sent_at": now}})
	_save_peer(sender_peer)
	_friend_action_result.rpc_id(sender_peer, "send_request", true, "Friend request sent to " + target_name + ".")
	_push_sync_to_peer(sender_peer)

@rpc("any_peer", "reliable")
func request_accept_friend_request(from_player_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	var sender_name = _get_player_name_for_peer(sender_peer)
	var sender_social = _get_social(sender_peer)
	if sender_id == "" or sender_social.is_empty():
		return
	# Find the request
	if not _has_incoming_from(sender_social, from_player_id):
		_friend_action_result.rpc_id(sender_peer, "accept", false, "No request from that player.")
		return
	# Block check
	if _is_blocked(sender_social, from_player_id):
		_friend_action_result.rpc_id(sender_peer, "accept", false, "Cannot accept — player is blocked.")
		return
	# Max friends check
	if sender_social.get("friends", []).size() >= MAX_FRIENDS:
		_friend_action_result.rpc_id(sender_peer, "accept", false, "Friend list is full.")
		return
	# Resolve from_player name from request
	var from_name = ""
	for req in sender_social.get("incoming_requests", []):
		if str(req.get("from_id", "")) == from_player_id:
			from_name = str(req.get("from_name", ""))
			break
	var from_peer = nm.get_peer_for_player_id(from_player_id)
	_do_accept_friend(sender_peer, sender_id, sender_name, from_peer, from_player_id, from_name)

func _do_accept_friend(acceptor_peer: int, acceptor_id: String, acceptor_name: String, requester_peer: int, requester_id: String, requester_name: String) -> void:
	var lock_key = _pair_key(acceptor_id, requester_id)
	if not _acquire_lock(lock_key):
		_friend_action_result.rpc_id(acceptor_peer, "accept", false, "Please wait and try again.")
		return
	# Add to both friends lists
	var acceptor_social = _get_social(acceptor_peer)
	if requester_id not in acceptor_social.get("friends", []):
		acceptor_social["friends"].append(requester_id)
	# Remove requests from both sides
	_remove_incoming_from(acceptor_social, requester_id)
	_remove_outgoing_to(acceptor_social, requester_id)
	_save_peer(acceptor_peer)
	if requester_peer > 0:
		var requester_social = _get_social(requester_peer)
		if acceptor_id not in requester_social.get("friends", []):
			requester_social["friends"].append(acceptor_id)
		_remove_incoming_from(requester_social, acceptor_id)
		_remove_outgoing_to(requester_social, acceptor_id)
		_save_peer(requester_peer)
		_notify_friend_added.rpc_id(requester_peer, acceptor_name, acceptor_id)
		_push_sync_to_peer(requester_peer)
	else:
		# Offline: PATCH
		_patch_offline(requester_id, {
			"add_friend": acceptor_id,
			"remove_outgoing_request_to": acceptor_id,
			"remove_incoming_request_from": acceptor_id,
		})
	_notify_friend_added.rpc_id(acceptor_peer, requester_name, requester_id)
	_friend_action_result.rpc_id(acceptor_peer, "accept", true, "Now friends with " + requester_name + "!")
	_push_sync_to_peer(acceptor_peer)
	_release_lock(lock_key)

@rpc("any_peer", "reliable")
func request_decline_friend_request(from_player_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	var sender_social = _get_social(sender_peer)
	if sender_id == "" or sender_social.is_empty():
		return
	if not _has_incoming_from(sender_social, from_player_id):
		return
	_remove_incoming_from(sender_social, from_player_id)
	_save_peer(sender_peer)
	# Remove outgoing from requester
	var from_peer = nm.get_peer_for_player_id(from_player_id)
	if from_peer > 0:
		var from_social = _get_social(from_peer)
		_remove_outgoing_to(from_social, sender_id)
		_save_peer(from_peer)
	else:
		_patch_offline(from_player_id, {"remove_outgoing_request_to": sender_id})
	_friend_action_result.rpc_id(sender_peer, "decline", true, "Request declined.")
	_push_sync_to_peer(sender_peer)
	if from_peer > 0:
		_push_sync_to_peer(from_peer)

@rpc("any_peer", "reliable")
func request_cancel_friend_request(to_player_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	var sender_social = _get_social(sender_peer)
	if sender_id == "" or sender_social.is_empty():
		return
	if not _has_outgoing_to(sender_social, to_player_id):
		return
	_remove_outgoing_to(sender_social, to_player_id)
	_save_peer(sender_peer)
	# Remove incoming from target
	var to_peer = nm.get_peer_for_player_id(to_player_id)
	if to_peer > 0:
		var to_social = _get_social(to_peer)
		_remove_incoming_from(to_social, sender_id)
		_save_peer(to_peer)
	else:
		_patch_offline(to_player_id, {"remove_incoming_request_from": sender_id})
	_friend_action_result.rpc_id(sender_peer, "cancel", true, "Request cancelled.")
	_push_sync_to_peer(sender_peer)
	if to_peer > 0:
		_push_sync_to_peer(to_peer)

@rpc("any_peer", "reliable")
func request_remove_friend(target_player_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	var sender_social = _get_social(sender_peer)
	if sender_id == "" or sender_social.is_empty():
		return
	if not _are_friends(sender_social, target_player_id):
		_friend_action_result.rpc_id(sender_peer, "remove", false, "Not friends with this player.")
		return
	var lock_key = _pair_key(sender_id, target_player_id)
	if not _acquire_lock(lock_key):
		return
	# Remove from both
	sender_social["friends"].erase(target_player_id)
	_save_peer(sender_peer)
	var target_peer = nm.get_peer_for_player_id(target_player_id)
	if target_peer > 0:
		var target_social = _get_social(target_peer)
		target_social["friends"].erase(sender_id)
		_save_peer(target_peer)
		_notify_friend_removed.rpc_id(target_peer, sender_id)
		# Auto-kick from party
		_kick_from_shared_party(sender_id, target_player_id)
	else:
		_patch_offline(target_player_id, {"remove_friend": sender_id})
	_friend_action_result.rpc_id(sender_peer, "remove", true, "Friend removed.")
	_push_sync_to_peer(sender_peer)
	if target_peer > 0:
		_push_sync_to_peer(target_peer)
	_release_lock(lock_key)

@rpc("any_peer", "reliable")
func request_block_player(target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	var sender_social = _get_social(sender_peer)
	if sender_id == "" or sender_social.is_empty():
		return
	if sender_social.get("blocked", []).size() >= MAX_BLOCKED:
		_friend_action_result.rpc_id(sender_peer, "block", false, "Block list is full.")
		return
	# Resolve target name to ID
	var target_peer = 0
	var target_id = ""
	for p_name in nm.active_player_names:
		if p_name == target_name:
			target_peer = nm.active_player_names[p_name]
			target_id = _get_player_id(target_peer)
			break
	if target_id == "":
		# Try offline lookup
		SaveManager.player_loaded.connect(_on_block_target_loaded.bind(sender_peer, sender_id, target_name), CONNECT_ONE_SHOT)
		SaveManager.load_player_async(target_name)
		return
	_process_block(sender_peer, sender_id, target_peer, target_id, target_name)

func _on_block_target_loaded(loaded_name: String, data: Dictionary, sender_peer: int, sender_id: String, target_name: String) -> void:
	if loaded_name != target_name:
		return
	if data.is_empty():
		_friend_action_result.rpc_id(sender_peer, "block", false, "Player not found.")
		return
	var target_id = str(data.get("player_id", ""))
	if target_id == "":
		return
	_process_block(sender_peer, sender_id, 0, target_id, target_name)

func _process_block(sender_peer: int, sender_id: String, target_peer: int, target_id: String, target_name: String) -> void:
	if sender_id == target_id:
		_friend_action_result.rpc_id(sender_peer, "block", false, "Cannot block yourself.")
		return
	var sender_social = _get_social(sender_peer)
	if _is_blocked(sender_social, target_id):
		_friend_action_result.rpc_id(sender_peer, "block", false, "Already blocked.")
		return
	# Add to blocked
	sender_social.get("blocked", []).append(target_id)
	# Remove friendship (both sides)
	var was_friend = _are_friends(sender_social, target_id)
	sender_social["friends"].erase(target_id)
	# Remove all pending requests (both directions)
	_remove_incoming_from(sender_social, target_id)
	_remove_outgoing_to(sender_social, target_id)
	_save_peer(sender_peer)
	var nm = _get_nm()
	if was_friend:
		if target_peer > 0:
			var target_social = _get_social(target_peer)
			target_social["friends"].erase(sender_id)
			_remove_incoming_from(target_social, sender_id)
			_remove_outgoing_to(target_social, sender_id)
			_save_peer(target_peer)
			_notify_friend_removed.rpc_id(target_peer, sender_id)
		else:
			_patch_offline(target_id, {"remove_friend": sender_id, "remove_incoming_request_from": sender_id, "remove_outgoing_request_to": sender_id})
	else:
		# Still remove any pending requests from target side
		if target_peer > 0:
			var target_social = _get_social(target_peer)
			_remove_incoming_from(target_social, sender_id)
			_remove_outgoing_to(target_social, sender_id)
			_save_peer(target_peer)
		else:
			_patch_offline(target_id, {"remove_incoming_request_from": sender_id, "remove_outgoing_request_to": sender_id})
	# Auto-kick from party
	_kick_from_shared_party(sender_id, target_id)
	_friend_action_result.rpc_id(sender_peer, "block", true, target_name + " has been blocked.")
	_push_sync_to_peer(sender_peer)
	if target_peer > 0:
		_push_sync_to_peer(target_peer)

@rpc("any_peer", "reliable")
func request_unblock_player(target_player_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_social = _get_social(sender_peer)
	if not _is_blocked(sender_social, target_player_id):
		_friend_action_result.rpc_id(sender_peer, "unblock", false, "Player is not blocked.")
		return
	sender_social["blocked"].erase(target_player_id)
	_save_peer(sender_peer)
	_friend_action_result.rpc_id(sender_peer, "unblock", true, "Player unblocked.")
	_push_sync_to_peer(sender_peer)

@rpc("any_peer", "reliable")
func request_friends_sync() -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	_push_sync_to_peer(sender_peer)

# === Request Array Helpers ===

func _remove_incoming_from(social: Dictionary, from_id: String) -> void:
	var reqs = social.get("incoming_requests", [])
	var i = reqs.size() - 1
	while i >= 0:
		if str(reqs[i].get("from_id", "")) == from_id:
			reqs.remove_at(i)
		i -= 1

func _remove_outgoing_to(social: Dictionary, to_id: String) -> void:
	var reqs = social.get("outgoing_requests", [])
	var i = reqs.size() - 1
	while i >= 0:
		if str(reqs[i].get("to_id", "")) == to_id:
			reqs.remove_at(i)
		i -= 1

func _kick_from_shared_party(player_id_a: String, player_id_b: String) -> void:
	# If both are in the same party, kick player_id_b
	if player_id_a not in player_party_map:
		return
	if player_id_b not in player_party_map:
		return
	if player_party_map[player_id_a] != player_party_map[player_id_b]:
		return
	var party_id = player_party_map[player_id_a]
	_remove_from_party(player_id_b, party_id, "Removed from party (no longer friends).")

# ========================================
# === PARTY RPCs: Client -> Server ===
# ========================================

@rpc("any_peer", "reliable")
func request_create_party() -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	if sender_id == "":
		return
	if sender_id in player_party_map:
		_friend_action_result.rpc_id(sender_peer, "create_party", false, "Already in a party.")
		return
	var party_id = _next_party_id
	_next_party_id += 1
	parties[party_id] = {
		"party_id": party_id,
		"leader_id": sender_id,
		"members": [sender_id],
		"invites": {},
	}
	player_party_map[sender_id] = party_id
	_sync_party_to_all(party_id)
	_friend_action_result.rpc_id(sender_peer, "create_party", true, "Party created!")

@rpc("any_peer", "reliable")
func request_invite_to_party(target_player_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	if sender_id == "":
		return
	if sender_id not in player_party_map:
		_friend_action_result.rpc_id(sender_peer, "invite", false, "Not in a party.")
		return
	var party_id = player_party_map[sender_id]
	var party = parties.get(party_id)
	if party == null:
		return
	if str(party["leader_id"]) != sender_id:
		_friend_action_result.rpc_id(sender_peer, "invite", false, "Only the leader can invite.")
		return
	if party["members"].size() >= MAX_PARTY_SIZE:
		_friend_action_result.rpc_id(sender_peer, "invite", false, "Party is full.")
		return
	# Must be friends
	var sender_social = _get_social(sender_peer)
	if not _are_friends(sender_social, target_player_id):
		_friend_action_result.rpc_id(sender_peer, "invite", false, "Must be friends to invite.")
		return
	# Block check
	if _is_blocked(sender_social, target_player_id):
		_friend_action_result.rpc_id(sender_peer, "invite", false, "Cannot invite this player.")
		return
	# Target must be online
	var target_peer = nm.get_peer_for_player_id(target_player_id)
	if target_peer <= 0:
		_friend_action_result.rpc_id(sender_peer, "invite", false, "Player is not online.")
		return
	# Check target not blocked sender
	var target_social = _get_social(target_peer)
	if _is_blocked(target_social, sender_id):
		_friend_action_result.rpc_id(sender_peer, "invite", false, "Cannot invite this player.")
		return
	# Already in party?
	if target_player_id in player_party_map:
		_friend_action_result.rpc_id(sender_peer, "invite", false, "Player is already in a party.")
		return
	# Already invited?
	if target_player_id in party["invites"]:
		_friend_action_result.rpc_id(sender_peer, "invite", false, "Already invited.")
		return
	# Send invite
	party["invites"][target_player_id] = {"invited_at": Time.get_unix_time_from_system()}
	var sender_name = _get_player_name_for_peer(sender_peer)
	_notify_party_invite.rpc_id(target_peer, sender_name, party_id)
	_friend_action_result.rpc_id(sender_peer, "invite", true, "Invite sent!")

@rpc("any_peer", "reliable")
func request_accept_party_invite(party_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	if sender_id == "":
		return
	if sender_id in player_party_map:
		_friend_action_result.rpc_id(sender_peer, "join_party", false, "Already in a party.")
		return
	var party = parties.get(party_id)
	if party == null:
		_friend_action_result.rpc_id(sender_peer, "join_party", false, "Party no longer exists.")
		return
	if sender_id not in party["invites"]:
		_friend_action_result.rpc_id(sender_peer, "join_party", false, "No invite for this party.")
		return
	# Check TTL
	var invite = party["invites"][sender_id]
	var elapsed = Time.get_unix_time_from_system() - float(invite.get("invited_at", 0))
	if elapsed > PARTY_INVITE_TTL_SEC:
		party["invites"].erase(sender_id)
		_friend_action_result.rpc_id(sender_peer, "join_party", false, "Invite has expired.")
		return
	if party["members"].size() >= MAX_PARTY_SIZE:
		_friend_action_result.rpc_id(sender_peer, "join_party", false, "Party is full.")
		return
	# Join
	party["invites"].erase(sender_id)
	party["members"].append(sender_id)
	player_party_map[sender_id] = party_id
	party_member_added.emit(party_id, sender_id)
	_sync_party_to_all(party_id)

@rpc("any_peer", "reliable")
func request_decline_party_invite(party_id: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	var party = parties.get(party_id)
	if party != null:
		party["invites"].erase(sender_id)

@rpc("any_peer", "reliable")
func request_leave_party() -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	if sender_id == "" or sender_id not in player_party_map:
		return
	var party_id = player_party_map[sender_id]
	_remove_from_party(sender_id, party_id, "You left the party.")

@rpc("any_peer", "reliable")
func request_kick_from_party(target_player_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	if sender_id == "" or sender_id not in player_party_map:
		return
	var party_id = player_party_map[sender_id]
	var party = parties.get(party_id)
	if party == null:
		return
	if str(party["leader_id"]) != sender_id:
		_friend_action_result.rpc_id(sender_peer, "kick", false, "Only the leader can kick.")
		return
	if target_player_id not in party["members"]:
		return
	_remove_from_party(target_player_id, party_id, "You were kicked from the party.")

@rpc("any_peer", "reliable")
func request_transfer_leadership(target_player_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_peer = multiplayer.get_remote_sender_id()
	var nm = _get_nm()
	if nm == null or not nm._check_rate_limit(sender_peer):
		return
	var sender_id = _get_player_id(sender_peer)
	if sender_id == "" or sender_id not in player_party_map:
		return
	var party_id = player_party_map[sender_id]
	var party = parties.get(party_id)
	if party == null:
		return
	if str(party["leader_id"]) != sender_id:
		_friend_action_result.rpc_id(sender_peer, "transfer", false, "Only the leader can transfer.")
		return
	if target_player_id not in party["members"]:
		return
	party["leader_id"] = target_player_id
	_sync_party_to_all(party_id)
	_friend_action_result.rpc_id(sender_peer, "transfer", true, "Leadership transferred.")

# === Party Helpers ===

func _remove_from_party(player_id: String, party_id: int, reason: String) -> void:
	var party = parties.get(party_id)
	if party == null:
		return
	var nm = _get_nm()
	# Notify the removed player
	if nm != null:
		var removed_peer = nm.get_peer_for_player_id(player_id)
		if removed_peer > 0:
			_notify_party_disbanded.rpc_id(removed_peer, reason)
	party["members"].erase(player_id)
	player_party_map.erase(player_id)
	party_member_removed.emit(party_id, player_id, reason)
	if party["members"].is_empty():
		parties.erase(party_id)
		return
	# Transfer leader if needed
	if str(party["leader_id"]) == player_id:
		party["leader_id"] = party["members"][0]
	_sync_party_to_all(party_id)

func _sync_party_to_all(party_id: int, extra_msg: String = "") -> void:
	var party = parties.get(party_id)
	if party == null:
		return
	var nm = _get_nm()
	if nm == null:
		return
	# Build member list with names
	var member_list: Array = []
	for mid in party["members"]:
		var m_peer = nm.get_peer_for_player_id(str(mid))
		var m_name = ""
		if m_peer > 0:
			m_name = _get_player_name_for_peer(m_peer)
		member_list.append({"player_id": str(mid), "player_name": m_name, "online": m_peer > 0})
	var party_data = {
		"party_id": party_id,
		"leader_id": str(party["leader_id"]),
		"members": member_list,
	}
	for mid in party["members"]:
		var m_peer = nm.get_peer_for_player_id(str(mid))
		if m_peer > 0:
			_sync_party_state.rpc_id(m_peer, party_data)

# ========================================
# === Server -> Client RPCs ===
# ========================================

@rpc("authority", "reliable")
func _sync_friends_list(friends_arr: Array, incoming: Array, outgoing: Array, blocked: Array) -> void:
	print("[FM-DEBUG-CLIENT] _sync_friends_list received: friends=", friends_arr.size(), " incoming=", incoming.size(), " outgoing=", outgoing.size(), " blocked=", blocked.size())
	PlayerData.friends = friends_arr.duplicate(true)
	PlayerData.incoming_friend_requests = incoming.duplicate(true)
	PlayerData.outgoing_friend_requests = outgoing.duplicate(true)
	PlayerData.blocked_players = blocked.duplicate()
	PlayerData.player_friends_changed.emit()

@rpc("authority", "reliable")
func _notify_friend_request(from_name: String, _from_id: String) -> void:
	print("[FM-DEBUG-CLIENT] _notify_friend_request from '", from_name, "'")
	# Show HUD toast
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		hud.show_toast("Friend request from " + from_name)
	PlayerData.player_friends_changed.emit()

@rpc("authority", "reliable")
func _notify_friend_added(player_name: String, _player_id: String) -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		hud.show_toast("Now friends with " + player_name + "!")
	PlayerData.player_friends_changed.emit()

@rpc("authority", "reliable")
func _notify_friend_removed(_player_id: String) -> void:
	PlayerData.player_friends_changed.emit()

@rpc("authority", "reliable")
func _friend_action_result(action: String, success: bool, message: String) -> void:
	print("[FM-DEBUG-CLIENT] _friend_action_result: action='", action, "' success=", success, " msg='", message, "'")
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		hud.show_toast(message)
	if success:
		PlayerData.player_friends_changed.emit()

@rpc("authority", "reliable")
func _sync_party_state(party_data: Dictionary) -> void:
	PlayerData.group_party_id = int(party_data.get("party_id", -1))
	PlayerData.group_party_leader_id = str(party_data.get("leader_id", ""))
	PlayerData.group_party_members = party_data.get("members", []).duplicate(true)
	PlayerData.player_party_updated.emit()

@rpc("authority", "reliable")
func _notify_party_invite(from_name: String, party_id: int) -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		hud.show_toast("Party invite from " + from_name)
	# Signal the UI to show invite popup
	party_invite_received.emit(from_name, party_id)

@rpc("authority", "reliable")
func _notify_party_disbanded(reason: String) -> void:
	PlayerData.group_party_id = -1
	PlayerData.group_party_leader_id = ""
	PlayerData.group_party_members.clear()
	PlayerData.player_party_updated.emit()
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		hud.show_toast(reason)

# === Server-side signals (for ExcursionManager) ===
signal party_member_removed(party_id: int, player_id: String, reason: String)
signal party_member_added(party_id: int, player_id: String)

# === Client-side signals (for UI) ===
signal party_invite_received(from_name: String, party_id: int)
