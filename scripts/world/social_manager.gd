extends Node

# Server-side manager for NPC friendship, dialogue, gifts, and daily processing.

const TALK_BONUS: int = 2
const DAILY_DECAY: int = 1
const GIFT_POINTS = {
	"loved": 15,
	"liked": 8,
	"neutral": 3,
	"disliked": -8,
	"hated": -15,
}
const BIRTHDAY_MULTIPLIER: int = 3
const MIN_FRIENDSHIP: int = -100
const MAX_FRIENDSHIP: int = 100

const TIER_THRESHOLDS = {
	"hate": -60,
	"dislike": -20,
	"neutral": 20,
	"like": 60,
}

# Pending dialogue state: peer_id -> {npc_id, dialogue_node}
var pending_dialogue: Dictionary = {}

func _ready() -> void:
	if not multiplayer.is_server():
		return
	# Connect to SeasonManager day_changed signal (deferred to ensure node exists)
	_connect_season_manager.call_deferred()

func _connect_season_manager() -> void:
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	if season_mgr and season_mgr.has_signal("day_changed"):
		season_mgr.day_changed.connect(_on_day_changed)

# === Friendship Tier ===

static func get_friendship_tier(points: int) -> String:
	if points < TIER_THRESHOLDS["hate"]:
		return "hate"
	elif points < TIER_THRESHOLDS["dislike"]:
		return "dislike"
	elif points < TIER_THRESHOLDS["neutral"]:
		return "neutral"
	elif points < TIER_THRESHOLDS["like"]:
		return "like"
	else:
		return "love"

# === Talk System ===

func handle_talk_request(peer_id: int, npc_id: String) -> void:
	if not multiplayer.is_server():
		return
	if peer_id not in NetworkManager.player_data_store:
		return

	var data = NetworkManager.player_data_store[peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})

	# Initialize friendship entry if needed
	if npc_id not in friendships:
		friendships[npc_id] = _create_default_friendship()
		data["npc_friendships"] = friendships

	var fs: Dictionary = friendships[npc_id]
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	var current_day: int = season_mgr.total_day_count if season_mgr else 0

	# Apply talk bonus (once per NPC per day)
	if not fs.get("talked_today", false):
		fs["talked_today"] = true
		fs["last_interaction_day"] = current_day
		fs["points"] = clampi(int(fs["points"]) + TALK_BONUS, MIN_FRIENDSHIP, MAX_FRIENDSHIP)
	StatTracker.increment(peer_id, "npc_conversations")

	# Quest progress: talk_to
	var quest_mgr = get_node_or_null("/root/Main/GameWorld/QuestManager")
	if quest_mgr:
		quest_mgr.notify_progress(peer_id, "talk_to", npc_id)

	# Pick dialogue node based on friendship tier
	DataRegistry.ensure_loaded()
	var npc_def = DataRegistry.get_npc(npc_id)
	if npc_def == null:
		return

	var tier = get_friendship_tier(int(fs["points"]))

	# Check birthday
	var dialogue_tier = tier
	if _is_npc_birthday(npc_def, season_mgr):
		var birthday_dialogues: Array = npc_def.dialogues.get("birthday", [])
		if birthday_dialogues.size() > 0:
			dialogue_tier = "birthday"

	var dialogues: Array = npc_def.dialogues.get(dialogue_tier, [])
	if dialogues.is_empty():
		dialogues = npc_def.dialogues.get("neutral", [])
	if dialogues.is_empty():
		return

	# Pick random dialogue node
	var node_idx = randi() % dialogues.size()
	var dialogue_node: Dictionary = dialogues[node_idx]

	# Check for available creature trade offer
	var creature_trade: Dictionary = _get_available_creature_trade(peer_id, npc_id, npc_def)
	var creature_trade_choice_idx: int = -1

	# Store pending dialogue for choice validation
	pending_dialogue[peer_id] = {
		"npc_id": npc_id,
		"dialogue_node": dialogue_node,
		"creature_trade": creature_trade,
		"creature_trade_choice_idx": -1,
	}

	# Build choice labels, appending creature trade if available
	var choices: Array = dialogue_node.get("choices", [])
	var choice_labels: Array = []
	for c in choices:
		choice_labels.append(str(c.get("label", "")))

	if not creature_trade.is_empty():
		creature_trade_choice_idx = choice_labels.size()
		choice_labels.append(str(creature_trade.get("dialogue_accept_label", "Accept creature trade")))
		choice_labels.append(str(creature_trade.get("dialogue_decline_label", "Decline")))
		pending_dialogue[peer_id]["creature_trade_choice_idx"] = creature_trade_choice_idx

	_send_dialogue.rpc_id(peer_id, npc_id, str(dialogue_node.get("text", "")), choice_labels, int(fs["points"]), tier)

	# Sync friendships
	NetworkManager._sync_npc_friendships.rpc_id(peer_id, friendships)

func handle_dialogue_choice(peer_id: int, choice_idx: int) -> void:
	if not multiplayer.is_server():
		return
	if peer_id not in pending_dialogue:
		return

	var pending = pending_dialogue[peer_id]
	var npc_id: String = pending["npc_id"]
	var dialogue_node: Dictionary = pending["dialogue_node"]
	var choices: Array = dialogue_node.get("choices", [])
	var creature_trade: Dictionary = pending.get("creature_trade", {})
	var creature_trade_choice_idx: int = int(pending.get("creature_trade_choice_idx", -1))

	# Check if this is a creature trade accept
	if creature_trade_choice_idx >= 0 and choice_idx == creature_trade_choice_idx:
		_handle_creature_trade_accept(peer_id, npc_id, creature_trade)
		pending_dialogue.erase(peer_id)
		return

	# Check if this is the creature trade decline choice (the one right after accept)
	if creature_trade_choice_idx >= 0 and choice_idx == creature_trade_choice_idx + 1:
		var decline_text = str(creature_trade.get("dialogue_decline_label", "Maybe another time."))
		_dialogue_choice_result.rpc_id(peer_id, "\"" + decline_text + "\"", 0, "")
		pending_dialogue.erase(peer_id)
		return

	# Validate choice index (normal dialogue choices)
	if choice_idx < 0 or choice_idx >= choices.size():
		pending_dialogue.erase(peer_id)
		return

	var choice: Dictionary = choices[choice_idx]
	var points_change: int = int(choice.get("points", 0))
	var response: String = str(choice.get("response", ""))

	# Apply points
	if peer_id in NetworkManager.player_data_store:
		var data = NetworkManager.player_data_store[peer_id]
		var friendships: Dictionary = data.get("npc_friendships", {})
		if npc_id in friendships:
			var fs: Dictionary = friendships[npc_id]
			fs["points"] = clampi(int(fs["points"]) + points_change, MIN_FRIENDSHIP, MAX_FRIENDSHIP)

			var new_points: int = int(fs["points"])
			var new_tier: String = get_friendship_tier(new_points)

			_dialogue_choice_result.rpc_id(peer_id, response, new_points, new_tier)

			# Check NPC gift thresholds after point change
			_check_npc_gifts(peer_id, npc_id, new_points)

			# Sync friendships
			NetworkManager._sync_npc_friendships.rpc_id(peer_id, friendships)

	pending_dialogue.erase(peer_id)

func handle_cancel_dialogue(peer_id: int) -> void:
	pending_dialogue.erase(peer_id)

# === Gift System ===

func handle_gift_request(peer_id: int, npc_id: String, item_id: String) -> void:
	if not multiplayer.is_server():
		return
	if peer_id not in NetworkManager.player_data_store:
		return

	# Set busy state during gift processing
	var player_node = NetworkManager._get_player_node(peer_id)
	if player_node:
		player_node.is_busy = true

	var data = NetworkManager.player_data_store[peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})

	# Initialize if needed
	if npc_id not in friendships:
		friendships[npc_id] = _create_default_friendship()
		data["npc_friendships"] = friendships

	var fs: Dictionary = friendships[npc_id]

	# Check daily gift limit
	if fs.get("gifted_today", false):
		_gift_response.rpc_id(peer_id, npc_id, "You've already given a gift today.", 0)
		if player_node:
			player_node.is_busy = false
		return

	# Validate item in inventory
	if not NetworkManager.server_has_inventory(peer_id, item_id, 1):
		_gift_response.rpc_id(peer_id, npc_id, "You don't have that item.", 0)
		if player_node:
			player_node.is_busy = false
		return

	# Reject non-giftable items (tools, recipe scrolls, fragments)
	DataRegistry.ensure_loaded()
	if not DataRegistry.is_item_giftable(item_id):
		_gift_response.rpc_id(peer_id, npc_id, "That item can't be given as a gift.", 0)
		if player_node:
			player_node.is_busy = false
		return

	# Determine gift tier
	DataRegistry.ensure_loaded()
	var npc_def = DataRegistry.get_npc(npc_id)
	if npc_def == null:
		if player_node:
			player_node.is_busy = false
		return

	var gift_tier: String = _get_gift_tier(npc_def, item_id)
	var base_points: int = GIFT_POINTS.get(gift_tier, GIFT_POINTS["neutral"])

	# Birthday multiplier
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	var multiplier: int = 1
	if _is_npc_birthday(npc_def, season_mgr):
		multiplier = BIRTHDAY_MULTIPLIER

	var points_change: int = base_points * multiplier

	# Deduct item server-side
	NetworkManager.server_remove_inventory(peer_id, item_id, 1)

	# Update friendship
	fs["gifted_today"] = true
	var current_day: int = season_mgr.total_day_count if season_mgr else 0
	fs["last_interaction_day"] = current_day
	fs["points"] = clampi(int(fs["points"]) + points_change, MIN_FRIENDSHIP, MAX_FRIENDSHIP)

	# Record gift preference discovery
	if "gift_history" not in fs:
		fs["gift_history"] = {}
	fs["gift_history"][item_id] = gift_tier

	# Build response message
	var response_msg: String = _get_gift_response(npc_def, gift_tier)
	if multiplier > 1:
		response_msg += " (Birthday bonus!)"

	StatTracker.increment(peer_id, "gifts_given")
	# Sync inventory and friendships
	NetworkManager._sync_inventory_full.rpc_id(peer_id, data.get("inventory", {}))
	NetworkManager._sync_npc_friendships.rpc_id(peer_id, friendships)
	# Clear busy before sending response — client popup will handle its own close
	if player_node:
		player_node.is_busy = false
	_gift_response.rpc_id(peer_id, npc_id, response_msg, points_change)

	# Check NPC gift thresholds
	_check_npc_gifts(peer_id, npc_id, int(fs["points"]))

# === Daily Processing ===

func _on_day_changed() -> void:
	if not multiplayer.is_server():
		return
	for peer_id in NetworkManager.player_data_store:
		_process_daily_for_peer(peer_id)
	# Update NPC schedule positions
	_update_all_npc_schedules()

func _process_daily_for_peer(peer_id: int) -> void:
	var data = NetworkManager.player_data_store[peer_id]
	var friendships: Dictionary = data.get("npc_friendships", {})
	if friendships.is_empty():
		return

	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	var current_day: int = season_mgr.total_day_count if season_mgr else 0

	for npc_id in friendships:
		var fs: Dictionary = friendships[npc_id]
		var last_day: int = int(fs.get("last_interaction_day", 0))

		# Decay if not interacted today (floor at 0, no negative decay)
		if last_day < current_day and int(fs.get("points", 0)) > 0:
			fs["points"] = maxi(int(fs["points"]) - DAILY_DECAY, 0)

		# Reset daily flags
		fs["talked_today"] = false
		fs["gifted_today"] = false

	# Sync to client
	if multiplayer.get_peers().has(peer_id):
		NetworkManager._sync_npc_friendships.rpc_id(peer_id, friendships)

# === NPC Schedule Movement ===

func _update_all_npc_schedules() -> void:
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	if season_mgr == null:
		return

	var time_fraction: float = season_mgr.day_timer / season_mgr.DAY_DURATION if season_mgr.DAY_DURATION > 0 else 0.0
	var season_str: String = season_mgr.get_current_season()

	DataRegistry.ensure_loaded()
	for npc_node in get_tree().get_nodes_in_group("social_npc"):
		if npc_node is Area3D and npc_node.has_meta("npc_id") or "npc_id" in npc_node:
			var npc_id: String = npc_node.npc_id if "npc_id" in npc_node else ""
			var npc_def = DataRegistry.get_npc(npc_id)
			if npc_def == null:
				continue
			var new_pos = _resolve_schedule_position(npc_def, time_fraction, season_str)
			if new_pos != Vector3.ZERO:
				npc_node.global_position = new_pos

static func _resolve_schedule_position(npc_def: Resource, time_fraction: float, season: String) -> Vector3:
	for entry in npc_def.schedule:
		var t_start: float = float(entry.get("time_start", 0.0))
		var t_end: float = float(entry.get("time_end", 1.0))
		var seasons: Array = entry.get("seasons", [])
		if time_fraction >= t_start and time_fraction < t_end:
			if seasons.is_empty() or season in seasons:
				var pos_dict: Dictionary = entry.get("position", {})
				return Vector3(
					float(pos_dict.get("x", 0)),
					float(pos_dict.get("y", 1)),
					float(pos_dict.get("z", 0))
				)
	return Vector3.ZERO

# === NPC Creature Trade ===

func _get_available_creature_trade(peer_id: int, npc_id: String, npc_def: Resource) -> Dictionary:
	if npc_def.creature_trades.is_empty():
		return {}
	if peer_id not in NetworkManager.player_data_store:
		return {}

	var data = NetworkManager.player_data_store[peer_id]
	var fs: Dictionary = data.get("npc_friendships", {}).get(npc_id, {})
	var received: Array = fs.get("gifts_received", [])
	var completed_quests: Dictionary = data.get("quests", {}).get("completed", {})

	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	var current_season: String = season_mgr.get_current_season() if season_mgr else ""

	for trade in npc_def.creature_trades:
		# Check one_time
		var trade_key: String = "npc_creature_trade_" + npc_id + "_" + str(trade.get("creature_species_id", ""))
		if trade.get("one_time", false) and trade_key in received:
			continue
		# Check friendship tier
		var required_friendship: String = str(trade.get("required_friendship", ""))
		if required_friendship != "":
			var current_tier: String = get_friendship_tier(int(fs.get("points", 0)))
			if not _tier_meets_requirement(current_tier, required_friendship):
				continue
		# Check season
		var required_season: String = str(trade.get("required_season", ""))
		if required_season != "" and current_season != required_season:
			continue
		# Check quest
		var required_quest: String = str(trade.get("required_quest_id", ""))
		if required_quest != "" and required_quest not in completed_quests:
			continue
		return trade

	return {}

static func _tier_meets_requirement(current_tier: String, required_tier: String) -> bool:
	var tier_order: Array = ["hate", "dislike", "neutral", "like", "love"]
	var current_idx: int = tier_order.find(current_tier)
	var required_idx: int = tier_order.find(required_tier)
	if current_idx < 0 or required_idx < 0:
		return false
	return current_idx >= required_idx

func _handle_creature_trade_accept(peer_id: int, npc_id: String, trade: Dictionary) -> void:
	if peer_id not in NetworkManager.player_data_store:
		return

	# Re-validate conditions server-side
	DataRegistry.ensure_loaded()
	var npc_def = DataRegistry.get_npc(npc_id)
	if npc_def == null:
		_dialogue_choice_result.rpc_id(peer_id, "Something went wrong.", 0, "")
		return

	var recheck = _get_available_creature_trade(peer_id, npc_id, npc_def)
	if recheck.is_empty() or str(recheck.get("creature_species_id", "")) != str(trade.get("creature_species_id", "")):
		_dialogue_choice_result.rpc_id(peer_id, "This offer is no longer available.", 0, "")
		return

	# Validate cost
	var cost_items: Dictionary = trade.get("cost_items", {})
	var cost_money: int = int(trade.get("cost_money", 0))

	for item_id in cost_items:
		if not NetworkManager.server_has_inventory(peer_id, str(item_id), int(cost_items[item_id])):
			_dialogue_choice_result.rpc_id(peer_id, "You don't have the required items.", 0, "")
			return
	if cost_money > 0:
		var current_money: int = int(NetworkManager.player_data_store[peer_id].get("money", 0))
		if current_money < cost_money:
			_dialogue_choice_result.rpc_id(peer_id, "You don't have enough money.", 0, "")
			return

	# Deduct cost
	for item_id in cost_items:
		NetworkManager.server_remove_inventory(peer_id, str(item_id), int(cost_items[item_id]))
	if cost_money > 0:
		NetworkManager.server_remove_money(peer_id, cost_money)

	# Create creature
	var species_id: String = str(trade.get("creature_species_id", ""))
	var species = DataRegistry.get_species(species_id)
	if species == null:
		_dialogue_choice_result.rpc_id(peer_id, "Creature species not found.", 0, "")
		return
	var creature_level: int = int(trade.get("creature_level", 1))
	var creature = CreatureInstance.create_from_species(species, creature_level)
	var creature_data: Dictionary = creature.to_dict()
	creature_data["creature_id"] = NetworkManager._generate_uuid()
	var nickname: String = str(trade.get("creature_nickname", ""))
	if nickname != "":
		creature_data["nickname"] = nickname

	# Give creature via universal handler
	NetworkManager.server_give_creature(peer_id, creature_data, "npc_trade", npc_id)

	# Mark as received if one_time
	if trade.get("one_time", false):
		var data = NetworkManager.player_data_store[peer_id]
		var fs: Dictionary = data.get("npc_friendships", {}).get(npc_id, {})
		var gifts_received: Array = fs.get("gifts_received", [])
		var trade_key: String = "npc_creature_trade_" + npc_id + "_" + species_id
		gifts_received.append(trade_key)
		fs["gifts_received"] = gifts_received

	# Sync
	NetworkManager._sync_inventory_full.rpc_id(peer_id, NetworkManager.player_data_store[peer_id].get("inventory", {}))
	NetworkManager._sync_money.rpc_id(peer_id, int(NetworkManager.player_data_store[peer_id].get("money", 0)))

	var display_name: String = species.display_name
	_dialogue_choice_result.rpc_id(peer_id, "You received " + display_name + "!", 0, "")
	print("[NPC Trade] ", peer_id, " acquired ", species_id, " from ", npc_id)

# === NPC Gift Threshold Rewards ===

func _check_npc_gifts(peer_id: int, npc_id: String, current_points: int) -> void:
	DataRegistry.ensure_loaded()
	var npc_def = DataRegistry.get_npc(npc_id)
	if npc_def == null:
		return

	var data = NetworkManager.player_data_store[peer_id]
	var fs: Dictionary = data.get("npc_friendships", {}).get(npc_id, {})
	var received: Array = fs.get("gifts_received", [])

	for gift in npc_def.npc_gifts:
		var threshold: int = int(gift.get("threshold", 0))
		var message: String = str(gift.get("message", ""))
		var gift_key: String = "npc_gift_" + npc_id + "_" + str(threshold)

		if current_points >= threshold and gift_key not in received:
			received.append(gift_key)
			fs["gifts_received"] = received

			# Check if this is a creature gift
			var creature_species_id: String = str(gift.get("creature_species_id", ""))
			if creature_species_id != "":
				var species = DataRegistry.get_species(creature_species_id)
				if species:
					var creature_level: int = int(gift.get("creature_level", 1))
					var creature = CreatureInstance.create_from_species(species, creature_level)
					var creature_data: Dictionary = creature.to_dict()
					creature_data["creature_id"] = NetworkManager._generate_uuid()
					var nickname: String = str(gift.get("creature_nickname", ""))
					if nickname != "":
						creature_data["nickname"] = nickname
					NetworkManager.server_give_creature(peer_id, creature_data, "npc_gift", npc_id)
					_notify_npc_gift.rpc_id(peer_id, npc_id, creature_species_id, 1, message)
			else:
				# Normal item gift
				var gift_item: String = str(gift.get("item_id", ""))
				var quantity: int = int(gift.get("quantity", 1))
				NetworkManager.server_add_inventory(peer_id, gift_item, quantity)
				NetworkManager._sync_inventory_full.rpc_id(peer_id, data.get("inventory", {}))
				_notify_npc_gift.rpc_id(peer_id, npc_id, gift_item, quantity, message)

# === Helpers ===

static func _create_default_friendship() -> Dictionary:
	return {
		"points": 0,
		"talked_today": false,
		"gifted_today": false,
		"last_interaction_day": 0,
		"gifts_received": [],
		"gift_history": {},
	}

static func _get_gift_tier(npc_def: Resource, item_id: String) -> String:
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

static func _get_gift_response(npc_def: Resource, gift_tier: String) -> String:
	var name: String = npc_def.display_name
	match gift_tier:
		"loved":
			return name + " loves this! \"This is exactly what I wanted!\""
		"liked":
			return name + " seems happy. \"Oh, how thoughtful!\""
		"neutral":
			return name + " accepts the gift. \"Thanks, I appreciate it.\""
		"disliked":
			return name + " doesn't look pleased. \"This isn't really my thing...\""
		"hated":
			return name + " is upset. \"Why would you give me this?!\""
	return name + " accepts the gift."

func _is_npc_birthday(npc_def: Resource, season_mgr: Node) -> bool:
	if season_mgr == null:
		return false
	var birthday: Dictionary = npc_def.birthday
	if birthday.is_empty():
		return false
	# New format: {month: int, day: int}
	if birthday.has("month"):
		return int(birthday.get("month", 0)) == season_mgr.current_month and int(birthday.get("day", 0)) == season_mgr.day_in_month
	# Old format backward compat: {season: "spring", day: int}
	var old_season_to_months = {"spring": [3, 4, 5], "summer": [6, 7, 8], "autumn": [9, 10, 11], "winter": [12, 1, 2]}
	var season_str: String = str(birthday.get("season", ""))
	var months: Array = old_season_to_months.get(season_str, [])
	return season_mgr.current_month in months and int(birthday.get("day", 0)) == season_mgr.day_in_month

# === RPCs ===

@rpc("authority", "reliable")
func _send_dialogue(_npc_id: String, _text: String, _choices: Array, _friendship_points: int, _tier: String) -> void:
	# Client-side: forward to DialogueUI
	var dialogue_ui = get_node_or_null("/root/Main/GameWorld/UI/DialogueUI")
	if dialogue_ui and dialogue_ui.has_method("show_dialogue"):
		dialogue_ui.show_dialogue(_npc_id, _text, _choices, _friendship_points, _tier)

@rpc("authority", "reliable")
func _dialogue_choice_result(_response: String, _new_points: int, _new_tier: String) -> void:
	var dialogue_ui = get_node_or_null("/root/Main/GameWorld/UI/DialogueUI")
	if dialogue_ui and dialogue_ui.has_method("show_choice_result"):
		dialogue_ui.show_choice_result(_response, _new_points, _new_tier)

@rpc("authority", "reliable")
func _gift_response(_npc_id: String, _message: String, _points_change: int) -> void:
	var dialogue_ui = get_node_or_null("/root/Main/GameWorld/UI/DialogueUI")
	if dialogue_ui and dialogue_ui.has_method("show_gift_response"):
		dialogue_ui.show_gift_response(_npc_id, _message, _points_change)

@rpc("authority", "reliable")
func _notify_npc_gift(_npc_id: String, _item_id: String, _quantity: int, _message: String) -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		var item_info = DataRegistry.get_item_display_info(_item_id)
		var display = item_info.get("display_name", _item_id)
		hud.show_toast(_message + " (Received " + str(_quantity) + "x " + display + ")")

# === Client->Server RPCs (called from SocialNPC or DialogueUI) ===

@rpc("any_peer", "reliable")
func request_dialogue_choice(choice_idx: int) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	handle_dialogue_choice(peer_id, choice_idx)

@rpc("any_peer", "reliable")
func cancel_dialogue() -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	handle_cancel_dialogue(peer_id)
