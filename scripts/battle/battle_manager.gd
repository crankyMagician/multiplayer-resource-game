extends Node

# BattleCalculator, StatusEffects, FieldEffects available via class_name

signal battle_started()
signal battle_ended(victory: bool)
signal turn_result_received(results: Array)
signal xp_result_received(results: Dictionary)
signal move_learn_prompt(creature_idx: int, new_move_id: String)
signal evolution_occurred(creature_idx: int, new_species_id: String)
signal pvp_challenge_received(challenger_name: String, challenger_peer: int)
signal trainer_dialogue(trainer_name: String, text: String, is_before: bool)
signal battle_state_updated()
signal battle_rewards_received(drops: Dictionary)
signal trainer_rewards_received(money: int, ingredients: Dictionary)
signal pvp_loss_received(lost_items: Dictionary)
signal defeat_penalty_received(money_lost: int)

# === Battle Mode System ===
enum BattleMode { WILD, TRAINER, PVP }

# Server state
var next_battle_id: int = 1
var battles: Dictionary = {} # battle_id -> BattleState dict
var player_battle_map: Dictionary = {} # peer_id -> battle_id
var pending_challenges: Dictionary = {} # challenger_peer -> {target_peer, timestamp}

# Client state
var in_battle: bool = false
var client_enemy: Dictionary = {}
var client_active_creature_idx: int = 0
var awaiting_action: bool = false
var client_battle_mode: int = 0 # BattleMode enum value
var client_weather: String = ""
var client_weather_turns: int = 0
var client_player_hazards: Array = []
var client_enemy_hazards: Array = []
var client_player_stat_stages: Dictionary = {}
var client_enemy_stat_stages: Dictionary = {}
var client_player_status_turns: int = 0
var client_enemy_status_turns: int = 0

# Summary accumulation (client-side)
var summary_xp_results: Array = []
var summary_drops: Dictionary = {}
var summary_trainer_money: int = 0
var summary_trainer_ingredients: Dictionary = {}
var summary_defeat_penalty: int = 0
var summary_pvp_loss: Dictionary = {}
var summary_evolutions: Array = [] # [{creature_idx, new_species_id}]
var summary_new_moves: Array = [] # [{creature_idx, move_id, auto}]

# Battle state structure (server-side):
# {
#   "battle_id": int,
#   "mode": BattleMode,
#   "state": "waiting_action" | "waiting_both" | "processing" | "waiting_switch" |
#            "waiting_move_learn" | "ended",
#   "side_a_peer": int (player peer_id),
#   "side_a_party": Array of creature dicts,
#   "side_a_active_idx": int,
#   "side_a_action": null or {type, data},
#   "side_b_peer": int (0 for AI, peer_id for PvP),
#   "side_b_party": Array of creature dicts,
#   "side_b_active_idx": int,
#   "side_b_action": null or {type, data},
#   "turn": int,
#   "trainer_id": String,
#   "weather": String,
#   "weather_turns": int,
#   "side_a_hazards": Array,
#   "side_b_hazards": Array,
#   "participants_a": Array (creature indices that entered),
#   "participants_b": Array,
#   "timeout_timer": float,
# }

func _ready() -> void:
	pass

func _process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	# PvP turn timeout
	for battle_id in battles:
		var battle = battles[battle_id]
		if battle.mode == BattleMode.PVP and battle.state == "waiting_both":
			battle.timeout_timer -= delta
			if battle.timeout_timer <= 0:
				_handle_pvp_timeout(battle_id)

# === HELPER: Create Battle ===

func _create_battle(mode: int, side_a_peer: int, side_b_peer: int = 0, trainer_id: String = "") -> int:
	var battle_id = next_battle_id
	next_battle_id += 1
	battles[battle_id] = {
		"battle_id": battle_id,
		"mode": mode,
		"state": "waiting_action",
		"side_a_peer": side_a_peer,
		"side_a_party": [],
		"side_a_active_idx": 0,
		"side_a_action": null,
		"side_b_peer": side_b_peer,
		"side_b_party": [],
		"side_b_active_idx": 0,
		"side_b_action": null,
		"turn": 0,
		"trainer_id": trainer_id,
		"weather": "",
		"weather_turns": 0,
		"side_a_hazards": [],
		"side_b_hazards": [],
		"participants_a": [0],
		"participants_b": [0],
		"timeout_timer": 30.0,
	}
	player_battle_map[side_a_peer] = battle_id
	if side_b_peer > 0:
		player_battle_map[side_b_peer] = battle_id
	return battle_id

func _get_battle_for_peer(peer_id: int):
	var battle_id = player_battle_map.get(peer_id, -1)
	if battle_id < 0:
		return null
	return battles.get(battle_id)

func _get_side(battle: Dictionary, peer_id: int) -> String:
	if battle.side_a_peer == peer_id:
		return "a"
	if battle.side_b_peer == peer_id:
		return "b"
	return ""

func _build_battle_state_for_peer(battle: Dictionary, peer_id: int) -> Dictionary:
	var side = _get_side(battle, peer_id)
	var my_side = "a" if side == "a" else "b"
	var opp_side = "b" if side == "a" else "a"
	var my_creature = battle["side_" + my_side + "_party"][battle["side_" + my_side + "_active_idx"]]
	var opp_creature = battle["side_" + opp_side + "_party"][battle["side_" + opp_side + "_active_idx"]]
	var my_hazards_key = "side_" + my_side + "_hazards"
	var opp_hazards_key = "side_" + opp_side + "_hazards"

	var opp_species = DataRegistry.get_species(opp_creature.get("species_id", ""))
	var opp_types: Array = []
	if opp_species:
		opp_types = Array(opp_species.types)

	return {
		"weather": battle.get("weather", ""),
		"weather_turns": battle.get("weather_turns", 0),
		"player_hazards": battle[my_hazards_key].duplicate(),
		"enemy_hazards": battle[opp_hazards_key].duplicate(),
		"player_stat_stages": {
			"attack": my_creature.get("attack_stage", 0),
			"defense": my_creature.get("defense_stage", 0),
			"sp_attack": my_creature.get("sp_attack_stage", 0),
			"sp_defense": my_creature.get("sp_defense_stage", 0),
			"speed": my_creature.get("speed_stage", 0),
			"accuracy": my_creature.get("accuracy_stage", 0),
			"evasion": my_creature.get("evasion_stage", 0),
		},
		"enemy_stat_stages": {
			"attack": opp_creature.get("attack_stage", 0),
			"defense": opp_creature.get("defense_stage", 0),
			"sp_attack": opp_creature.get("sp_attack_stage", 0),
			"sp_defense": opp_creature.get("sp_defense_stage", 0),
			"speed": opp_creature.get("speed_stage", 0),
			"accuracy": opp_creature.get("accuracy_stage", 0),
			"evasion": opp_creature.get("evasion_stage", 0),
		},
		"enemy_creature": {
			"nickname": opp_creature.get("nickname", "???"),
			"level": opp_creature.get("level", 1),
			"hp": opp_creature.get("hp", 0),
			"max_hp": opp_creature.get("max_hp", 1),
			"species_id": opp_creature.get("species_id", ""),
			"types": opp_types,
			"status": opp_creature.get("status", ""),
			"status_turns": opp_creature.get("status_turns", 0),
		},
		"player_status": my_creature.get("status", ""),
		"player_status_turns": my_creature.get("status_turns", 0),
		"enemy_status": opp_creature.get("status", ""),
		"enemy_status_turns": opp_creature.get("status_turns", 0),
	}

func _send_state_to_peer(battle: Dictionary, peer_id: int) -> void:
	var state = _build_battle_state_for_peer(battle, peer_id)
	_receive_battle_state.rpc_id(peer_id, state)

func _init_creature_battle_state(creature: Dictionary) -> void:
	creature["attack_stage"] = 0
	creature["defense_stage"] = 0
	creature["sp_attack_stage"] = 0
	creature["sp_defense_stage"] = 0
	creature["speed_stage"] = 0
	creature["accuracy_stage"] = 0
	creature["evasion_stage"] = 0
	creature["status"] = creature.get("status", "")
	creature["status_turns"] = creature.get("status_turns", 0)
	creature["is_protecting"] = false
	creature["protect_count"] = 0
	creature["is_charging"] = false
	creature["charged_move_id"] = ""

# === SERVER SIDE — Build party from authoritative store ===

func _build_party_from_store(peer_id: int) -> Array:
	if peer_id not in NetworkManager.player_data_store:
		return []
	var store_party = NetworkManager.player_data_store[peer_id].get("party", [])
	var battle_party: Array = []
	for creature in store_party:
		var c = creature.duplicate(true)
		_init_creature_battle_state(c)
		battle_party.append(c)
	return battle_party

# === SERVER SIDE — Wild Battles ===

func server_start_battle(peer_id: int, enemy_data: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	if peer_id in player_battle_map:
		print("[BattleManager] server_start_battle: peer ", peer_id, " already in battle, skipping")
		return
	print("[BattleManager] server_start_battle for peer ", peer_id)
	var battle_id = _create_battle(BattleMode.WILD, peer_id)
	var battle = battles[battle_id]
	var enemy = enemy_data.duplicate(true)
	_init_creature_battle_state(enemy)
	battle.side_b_party = [enemy]
	battle.side_b_active_idx = 0
	# Build party from server-authoritative store (no client trust)
	var player_party = _build_party_from_store(peer_id)
	if player_party.is_empty():
		print("[BattleManager] server_start_battle: no party for peer ", peer_id)
		player_battle_map.erase(peer_id)
		battles.erase(battle_id)
		return
	battle.side_a_party = player_party
	# Send battle start to client
	var enemy_active = battle.side_b_party[battle.side_b_active_idx]
	print("[BattleManager] Sending _start_battle_client to peer ", peer_id, " mode=", battle.mode)
	_start_battle_client.rpc_id(peer_id, enemy_active, battle.mode, "")
	# Fire on_enter abilities for both sides at battle start
	var player_active = battle.side_a_party[battle.side_a_active_idx]
	var initial_log: Array = []
	var p_enter_msgs = AbilityEffects.on_enter(player_active, enemy_active, battle)
	for msg in p_enter_msgs:
		initial_log.append({"type": "ability_trigger", "actor": "player", "message": msg.get("message", "")})
	var e_enter_msgs = AbilityEffects.on_enter(enemy_active, player_active, battle)
	for msg in e_enter_msgs:
		initial_log.append({"type": "ability_trigger", "actor": "enemy", "message": msg.get("message", "")})
	if initial_log.size() > 0:
		_send_turn_result.rpc_id(peer_id, initial_log, player_active.hp, player_active.get("pp", []), enemy_active.hp)
	_send_state_to_peer(battle, peer_id)

# === SERVER SIDE — Trainer Battles ===

func server_start_trainer_battle(peer_id: int, trainer_id: String) -> void:
	if not multiplayer.is_server():
		return
	if peer_id in player_battle_map:
		print("[BattleManager] server_start_trainer_battle: peer ", peer_id, " already in battle, skipping")
		return
	print("[BattleManager] server_start_trainer_battle for peer ", peer_id, " trainer=", trainer_id)
	DataRegistry.ensure_loaded()
	var trainer = DataRegistry.get_trainer(trainer_id)
	if trainer == null:
		return
	# Cooldown is now checked by trainer_npc.gd request_challenge()
	var battle_id = _create_battle(BattleMode.TRAINER, peer_id, 0, trainer_id)
	var battle = battles[battle_id]
	# Build trainer party from species+level
	var trainer_party = []
	for entry in trainer.party:
		var species = DataRegistry.get_species(entry.get("species_id", ""))
		if species == null:
			continue
		var lvl = int(entry.get("level", 5))
		var inst = CreatureInstance.create_from_species(species, lvl)
		var creature_dict = inst.to_dict()
		_init_creature_battle_state(creature_dict)
		trainer_party.append(creature_dict)
	battle.side_b_party = trainer_party
	battle.side_b_active_idx = 0
	battle.participants_b = []
	for i in range(trainer_party.size()):
		battle.participants_b.append(i)
	# Build party from server-authoritative store (no client trust)
	var player_party = _build_party_from_store(peer_id)
	if player_party.is_empty():
		print("[BattleManager] server_start_trainer_battle: no party for peer ", peer_id)
		player_battle_map.erase(peer_id)
		battles.erase(battle_id)
		return
	battle.side_a_party = player_party
	# Send dialogue then start
	_trainer_dialogue_client.rpc_id(peer_id, trainer.display_name, trainer.dialogue_before, true)
	var enemy_active = battle.side_b_party[battle.side_b_active_idx]
	print("[BattleManager] Sending _start_battle_client to peer ", peer_id, " mode=", battle.mode)
	_start_battle_client.rpc_id(peer_id, enemy_active, battle.mode, trainer.display_name)
	# Fire on_enter abilities
	var player_active = battle.side_a_party[battle.side_a_active_idx]
	var initial_log: Array = []
	var p_enter_msgs = AbilityEffects.on_enter(player_active, enemy_active, battle)
	for msg in p_enter_msgs:
		initial_log.append({"type": "ability_trigger", "actor": "player", "message": msg.get("message", "")})
	var e_enter_msgs = AbilityEffects.on_enter(enemy_active, player_active, battle)
	for msg in e_enter_msgs:
		initial_log.append({"type": "ability_trigger", "actor": "enemy", "message": msg.get("message", "")})
	if initial_log.size() > 0:
		_send_turn_result.rpc_id(peer_id, initial_log, player_active.hp, player_active.get("pp", []), enemy_active.hp)
	_send_state_to_peer(battle, peer_id)

# === SERVER SIDE — PvP Battles ===

@rpc("any_peer", "reliable")
func request_pvp_challenge(target_peer: int) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if sender == target_peer:
		return
	# Check neither is in battle
	if sender in player_battle_map or target_peer in player_battle_map:
		return
	# Check proximity (< 5 units)
	var sender_node = NetworkManager._get_player_node(sender)
	var target_node = NetworkManager._get_player_node(target_peer)
	if sender_node == null or target_node == null:
		return
	if sender_node.position.distance_to(target_node.position) > 5.0:
		return
	# Store pending challenge
	pending_challenges[sender] = {"target_peer": target_peer, "timestamp": Time.get_unix_time_from_system()}
	# Notify target
	var sender_name = NetworkManager.players.get(sender, {}).get("name", "Player")
	_pvp_challenge_received.rpc_id(target_peer, sender_name, sender)

@rpc("any_peer", "reliable")
func respond_pvp_challenge(challenger_peer: int, accepted: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	if challenger_peer not in pending_challenges:
		return
	if pending_challenges[challenger_peer].target_peer != sender:
		return
	pending_challenges.erase(challenger_peer)
	if not accepted:
		return
	# Create PvP battle
	var battle_id = _create_battle(BattleMode.PVP, challenger_peer, sender)
	var battle = battles[battle_id]
	# Build both parties from server-authoritative store
	battle.side_a_party = _build_party_from_store(challenger_peer)
	battle.side_b_party = _build_party_from_store(sender)
	if battle.side_a_party.is_empty() or battle.side_b_party.is_empty():
		print("[BattleManager] PvP: missing party data, aborting")
		player_battle_map.erase(challenger_peer)
		player_battle_map.erase(sender)
		battles.erase(battle_id)
		return
	_start_pvp_battle(battle)

func _start_pvp_battle(battle: Dictionary) -> void:
	battle.state = "waiting_both"
	battle.timeout_timer = 30.0
	# Send each player's enemy data
	var a_active = battle.side_a_party[battle.side_a_active_idx]
	var b_active = battle.side_b_party[battle.side_b_active_idx]
	var a_name = NetworkManager.players.get(battle.side_a_peer, {}).get("name", "Player")
	var b_name = NetworkManager.players.get(battle.side_b_peer, {}).get("name", "Player")
	_start_battle_client.rpc_id(battle.side_a_peer, b_active, BattleMode.PVP, b_name)
	_start_battle_client.rpc_id(battle.side_b_peer, a_active, BattleMode.PVP, a_name)
	# Fire on_enter abilities for both sides
	var a_log: Array = []
	var b_log: Array = []
	var a_enter_msgs = AbilityEffects.on_enter(a_active, b_active, battle)
	for msg in a_enter_msgs:
		a_log.append({"type": "ability_trigger", "actor": "player", "message": msg.get("message", "")})
		b_log.append({"type": "ability_trigger", "actor": "enemy", "message": msg.get("message", "")})
	var b_enter_msgs = AbilityEffects.on_enter(b_active, a_active, battle)
	for msg in b_enter_msgs:
		b_log.append({"type": "ability_trigger", "actor": "player", "message": msg.get("message", "")})
		a_log.append({"type": "ability_trigger", "actor": "enemy", "message": msg.get("message", "")})
	if a_log.size() > 0:
		_send_turn_result.rpc_id(battle.side_a_peer, a_log, a_active.hp, a_active.get("pp", []), b_active.hp)
	if b_log.size() > 0:
		_send_turn_result.rpc_id(battle.side_b_peer, b_log, b_active.hp, b_active.get("pp", []), a_active.hp)
	_send_state_to_peer(battle, battle.side_a_peer)
	_send_state_to_peer(battle, battle.side_b_peer)

# === ACTION HANDLING ===

@rpc("any_peer", "reliable")
func request_battle_action(action_type: String, action_data: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	var battle = _get_battle_for_peer(sender)
	if battle == null:
		return
	var side = _get_side(battle, sender)
	if side == "":
		return
	DataRegistry.ensure_loaded()

	# Validate actions against server-side party data
	if action_type == "move":
		var active_key = "side_" + side + "_active_idx"
		var party_key = "side_" + side + "_party"
		var creature = battle[party_key][battle[active_key]]
		var creature_moves = creature.get("moves", [])
		if action_data not in creature_moves:
			print("[BattleManager] Rejected move '", action_data, "' — not in creature's moveset for peer ", sender)
			return
	elif action_type == "switch":
		var party_key = "side_" + side + "_party"
		var switch_idx = action_data.to_int()
		if switch_idx < 0 or switch_idx >= battle[party_key].size():
			print("[BattleManager] Rejected switch to idx ", switch_idx, " — out of bounds for peer ", sender)
			return

	if battle.mode == BattleMode.PVP:
		_handle_pvp_action(battle, side, action_type, action_data)
	else:
		# Wild / Trainer — only side_a submits actions
		if side != "a":
			return
		if battle.state != "waiting_action":
			return
		battle.state = "processing"
		match action_type:
			"move":
				_process_move_turn(battle, action_type, action_data)
			"switch":
				_process_switch(battle, "a", action_data.to_int())
			"flee":
				_process_flee(battle)

func _handle_pvp_action(battle: Dictionary, side: String, action_type: String, action_data: String) -> void:
	if battle.state != "waiting_both":
		return
	var action = {"type": action_type, "data": action_data}
	if side == "a":
		battle.side_a_action = action
	else:
		battle.side_b_action = action
	# Check if both submitted
	if battle.side_a_action != null and battle.side_b_action != null:
		battle.state = "processing"
		_resolve_pvp_turn(battle)

func _handle_pvp_timeout(battle_id: int) -> void:
	var battle = battles.get(battle_id)
	if battle == null:
		return
	# Whoever didn't submit forfeits
	if battle.side_a_action == null and battle.side_b_action == null:
		# Both timed out — draw, no rewards
		_end_battle_full(battle, "draw")
	elif battle.side_a_action == null:
		_end_battle_full(battle, "b_wins")
	else:
		_end_battle_full(battle, "a_wins")

# === MOVE TURN PROCESSING (Wild/Trainer) ===

func _process_move_turn(battle: Dictionary, _action_type: String, move_id: String) -> void:
	var player_creature = battle.side_a_party[battle.side_a_active_idx]
	var enemy = battle.side_b_party[battle.side_b_active_idx]
	var turn_log = []
	var _peer_id = battle.side_a_peer

	# Clear protection flags at turn start
	player_creature["is_protecting"] = false
	enemy["is_protecting"] = false

	# Check if player is charging — force the charged move
	if player_creature.get("is_charging", false):
		move_id = player_creature.get("charged_move_id", move_id)
		player_creature["is_charging"] = false
		player_creature["charged_move_id"] = ""

	# Validate move
	var player_move = DataRegistry.get_move(move_id)
	if player_move == null:
		battle.state = "waiting_action"
		return

	# Check PP (skip for charged moves which already deducted)
	if not player_creature.get("_pp_already_deducted", false):
		var move_idx = _find_move_index(player_creature, move_id)
		if move_idx == -1:
			battle.state = "waiting_action"
			return
		var pp_arr = player_creature.get("pp", [])
		if move_idx < pp_arr.size() and pp_arr[move_idx] <= 0:
			battle.state = "waiting_action"
			return
		if move_idx < pp_arr.size():
			pp_arr[move_idx] -= 1
	player_creature.erase("_pp_already_deducted")

	# Pick enemy move (AI)
	var enemy_move_id: String
	var enemy_move
	if enemy.get("is_charging", false):
		enemy_move_id = enemy.get("charged_move_id", "")
		enemy["is_charging"] = false
		enemy["charged_move_id"] = ""
	else:
		enemy_move_id = BattleAI.pick_move(battle, "b") if battle.mode == BattleMode.TRAINER else _pick_enemy_move(enemy)
	enemy_move = DataRegistry.get_move(enemy_move_id)

	# Determine turn order
	var player_priority = player_move.priority if player_move else 0
	var enemy_priority = enemy_move.priority if enemy_move else 0
	var player_speed = BattleCalculator.get_speed(player_creature)
	var enemy_speed = BattleCalculator.get_speed(enemy)
	var player_first = _determine_order(player_priority, enemy_priority, player_speed, enemy_speed)

	# Execute turns
	if player_first:
		var r1 = _execute_action(player_creature, enemy, player_move, "player", battle)
		turn_log.append(r1)
		if enemy.hp > 0:
			var r2 = _execute_action(enemy, player_creature, enemy_move, "enemy", battle)
			turn_log.append(r2)
	else:
		var r1 = _execute_action(enemy, player_creature, enemy_move, "enemy", battle)
		turn_log.append(r1)
		if player_creature.hp > 0:
			var r2 = _execute_action(player_creature, enemy, player_move, "player", battle)
			turn_log.append(r2)

	# End of turn effects
	_apply_end_of_turn(battle, turn_log)
	battle.turn += 1

	# Check outcomes
	_check_battle_outcome(battle, turn_log)

func _determine_order(pri_a: int, pri_b: int, spd_a: int, spd_b: int) -> bool:
	if pri_a != pri_b:
		return pri_a > pri_b
	if spd_a != spd_b:
		return spd_a > spd_b
	return randf() > 0.5

# === EXECUTE ACTION (core battle pipeline) ===

func _execute_action(attacker: Dictionary, defender: Dictionary, move, actor: String, battle: Dictionary) -> Dictionary:
	var result = {
		"actor": actor,
		"move": move.display_name if move else "Struggle",
		"move_type": move.type if move else "",
		"type": "move"
	}

	if move == null:
		return result

	# Check if can act (status effects)
	if not BattleCalculator.can_act(attacker):
		result["skipped"] = true
		result["message"] = "can't move!"
		return result

	# Protection move
	if move.is_protection:
		var success_chance = pow(1.0 / 3.0, attacker.get("protect_count", 0))
		if randf() < success_chance:
			attacker["is_protecting"] = true
			attacker["protect_count"] = attacker.get("protect_count", 0) + 1
			result["protecting"] = true
			result["message"] = "protected itself!"
		else:
			attacker["protect_count"] = 0
			result["message"] = "protection failed!"
		return result

	# Reset protect count when using non-protect move
	attacker["protect_count"] = 0

	# Charging move — first turn sets charge, second turn executes
	if move.is_charging and not attacker.get("_executing_charge", false):
		attacker["is_charging"] = true
		attacker["charged_move_id"] = move.move_id
		# Deduct PP now
		var midx = _find_move_index(attacker, move.move_id)
		if midx >= 0:
			var pp_arr = attacker.get("pp", [])
			if midx < pp_arr.size() and pp_arr[midx] > 0:
				pp_arr[midx] -= 1
		attacker["_pp_already_deducted"] = true
		result["charging"] = true
		result["message"] = move.charge_message if move.charge_message != "" else "is charging up!"
		return result

	attacker.erase("_executing_charge")

	# Check protection on defender
	if defender.get("is_protecting", false) and move.power > 0:
		result["blocked"] = true
		result["message"] = "was blocked by protection!"
		return result

	# Check accuracy
	if not BattleCalculator.check_accuracy(move, attacker, defender):
		result["missed"] = true
		return result

	# Determine hit count
	var hit_count = 1
	if move.multi_hit_min > 0 and move.multi_hit_max > 0:
		hit_count = randi_range(move.multi_hit_min, move.multi_hit_max)
		result["hit_count"] = hit_count

	var total_damage = 0
	var weather = battle.get("weather", "")

	# For each hit
	if move.power > 0:
		for _hit in range(hit_count):
			if defender.get("hp", 0) <= 0:
				break
			var dmg_result = BattleCalculator.calculate_damage(attacker, defender, move, attacker.get("level", 5), weather)

			# Ability hooks — on_attack and on_defend
			var dmg = dmg_result.damage
			var atk_ability_result = AbilityEffects.on_attack(attacker, move, dmg)
			dmg = atk_ability_result.damage
			if atk_ability_result.has("message"):
				if not result.has("ability_messages"):
					result["ability_messages"] = []
				result["ability_messages"].append(atk_ability_result.message)

			var def_ability_result = AbilityEffects.on_defend(defender, move, dmg)
			dmg = def_ability_result.damage
			if def_ability_result.has("message"):
				if not result.has("ability_messages"):
					result["ability_messages"] = []
				result["ability_messages"].append(def_ability_result.message)
			if def_ability_result.has("heal"):
				result["ability_heal"] = def_ability_result.heal

			# Held item hooks — on_damage_calc and on_damage_received
			var atk_item_result = HeldItemEffects.on_damage_calc(attacker.get("held_item_id", ""), move, dmg)
			dmg = atk_item_result.damage
			if atk_item_result.has("message"):
				if not result.has("item_messages"):
					result["item_messages"] = []
				result["item_messages"].append(atk_item_result.message)

			var def_item_result = HeldItemEffects.on_damage_received(defender.get("held_item_id", ""), move, dmg)
			dmg = def_item_result.damage
			if def_item_result.has("message"):
				if not result.has("item_messages"):
					result["item_messages"] = []
				result["item_messages"].append(def_item_result.message)

			defender["hp"] = max(0, defender.get("hp", 0) - dmg)
			total_damage += dmg

			if _hit == 0:
				result["effectiveness"] = BattleCalculator.get_effectiveness_text(dmg_result.effectiveness)
				result["critical"] = dmg_result.critical

		result["damage"] = total_damage

		# Recoil
		if move.recoil_percent > 0 and total_damage > 0:
			var recoil = max(1, int(total_damage * move.recoil_percent))
			attacker["hp"] = max(0, attacker.get("hp", 0) - recoil)
			result["recoil"] = recoil

		# Drain healing
		if move.drain_percent > 0 and total_damage > 0:
			var heal = int(total_damage * move.drain_percent)
			attacker["hp"] = min(attacker.get("max_hp", 40), attacker.get("hp", 0) + heal)
			result["drain_heal"] = heal

	# Healing
	if move.heal_percent > 0:
		var heal = int(attacker.get("max_hp", 40) * move.heal_percent)
		attacker["hp"] = min(attacker.get("max_hp", 40), attacker.get("hp", 0) + heal)
		result["heal"] = heal

	# Status effect on defender
	if move.status_effect != "" and defender.get("hp", 0) > 0:
		var status_block = AbilityEffects.on_status_attempt(defender, move.status_effect)
		if not status_block.blocked:
			var applied = StatusEffects.try_apply_status(defender, move.status_effect, move.status_chance)
			if applied:
				result["status_applied"] = move.status_effect
				# Held item: Ginger Root cures status on apply
				var item_status_result = HeldItemEffects.on_status_applied(defender)
				if item_status_result.has("message"):
					if not result.has("item_messages"):
						result["item_messages"] = []
					result["item_messages"].append(item_status_result.message)
		elif status_block.has("message"):
			if not result.has("ability_messages"):
				result["ability_messages"] = []
			result["ability_messages"].append(status_block.message)

	# Stat changes (self-targeting)
	if move.stat_changes.size() > 0:
		var changes = BattleCalculator.apply_stat_changes(attacker, move.stat_changes)
		result["stat_changes"] = changes

	# Target stat changes
	if move.target_stat_changes.size() > 0 and defender.get("hp", 0) > 0:
		var stat_block = AbilityEffects.on_status_attempt(defender, "stat_drop")
		if not stat_block.blocked:
			var changes = BattleCalculator.apply_stat_changes(defender, move.target_stat_changes)
			result["target_stat_changes"] = changes
		elif stat_block.has("message"):
			if not result.has("ability_messages"):
				result["ability_messages"] = []
			result["ability_messages"].append(stat_block.message)

	# Weather setting
	if move.weather_set != "":
		battle["weather"] = move.weather_set
		battle["weather_turns"] = FieldEffects.WEATHER_DURATION
		result["weather_set"] = move.weather_set

	# Hazard setting
	if move.hazard_type != "":
		var hazard_side = "side_a_hazards" if actor == "enemy" else "side_b_hazards"
		if move.hazard_type not in battle[hazard_side]:
			battle[hazard_side].append(move.hazard_type)
		result["hazard_set"] = move.hazard_type

	# Clear hazards
	if move.clears_hazards:
		var clear_side = "side_a_hazards" if actor == "player" else "side_b_hazards"
		var cleared = battle[clear_side].duplicate()
		battle[clear_side].clear()
		if cleared.size() > 0:
			result["hazards_cleared"] = cleared

	# Check held item HP thresholds after damage
	if defender.get("hp", 0) > 0:
		var item_result = HeldItemEffects.on_hp_threshold(defender)
		if item_result.size() > 0:
			result["defender_item_trigger"] = item_result
	if attacker.get("hp", 0) > 0:
		var item_result = HeldItemEffects.on_hp_threshold(attacker)
		if item_result.size() > 0:
			result["attacker_item_trigger"] = item_result

	return result

# === END OF TURN ===

func _apply_end_of_turn(battle: Dictionary, turn_log: Array) -> void:
	var a_creature = battle.side_a_party[battle.side_a_active_idx]
	var b_creature = battle.side_b_party[battle.side_b_active_idx]
	var weather = battle.get("weather", "")

	# Status damage
	if a_creature.get("hp", 0) > 0:
		var status_result = StatusEffects.apply_end_of_turn(a_creature)
		if status_result.damage > 0:
			turn_log.append({"actor": "player", "type": "status_damage", "damage": status_result.damage, "message": status_result.message})

	if b_creature.get("hp", 0) > 0:
		var status_result = StatusEffects.apply_end_of_turn(b_creature)
		if status_result.damage > 0:
			turn_log.append({"actor": "enemy", "type": "status_damage", "damage": status_result.damage, "message": status_result.message})

	# Ability end-of-turn effects
	if a_creature.get("hp", 0) > 0:
		var heal = AbilityEffects.end_of_turn(a_creature, weather)
		if heal > 0:
			turn_log.append({"actor": "player", "type": "ability_heal", "heal": heal, "message": "healed by its ability!"})

	if b_creature.get("hp", 0) > 0:
		var heal = AbilityEffects.end_of_turn(b_creature, weather)
		if heal > 0:
			turn_log.append({"actor": "enemy", "type": "ability_heal", "heal": heal, "message": "healed by its ability!"})

	# Held item end-of-turn effects
	if a_creature.get("hp", 0) > 0:
		var heal = HeldItemEffects.end_of_turn(a_creature)
		if heal > 0:
			turn_log.append({"actor": "player", "type": "item_heal", "heal": heal, "message": "healed by its held item!"})

	if b_creature.get("hp", 0) > 0:
		var heal = HeldItemEffects.end_of_turn(b_creature)
		if heal > 0:
			turn_log.append({"actor": "enemy", "type": "item_heal", "heal": heal, "message": "healed by its held item!"})

	# Weather countdown
	if battle.weather != "":
		battle.weather_turns -= 1
		if battle.weather_turns <= 0:
			turn_log.append({"type": "weather_cleared", "weather": battle.weather})
			battle.weather = ""
			battle.weather_turns = 0

# === OUTCOME CHECKING ===

func _check_battle_outcome(battle: Dictionary, turn_log: Array) -> void:
	var peer_id = battle.side_a_peer
	var player_creature = battle.side_a_party[battle.side_a_active_idx]
	var enemy = battle.side_b_party[battle.side_b_active_idx]

	if enemy.hp <= 0:
		# Check if trainer has more creatures
		if battle.mode == BattleMode.TRAINER:
			var next_idx = _find_alive_creature(battle.side_b_party, battle.side_b_active_idx)
			if next_idx != -1:
				battle.side_b_active_idx = next_idx
				var new_enemy = battle.side_b_party[next_idx]
				# Apply entry hazards
				var hazard_results = FieldEffects.apply_hazards_on_switch(new_enemy, battle.side_b_hazards)
				for hr in hazard_results:
					hr["actor"] = "enemy"
					turn_log.append(hr)
				# Ability on_enter
				var a_active = battle.side_a_party[battle.side_a_active_idx]
				var enter_msgs = AbilityEffects.on_enter(new_enemy, a_active, battle)
				turn_log.append({"type": "trainer_switch", "actor": "enemy", "to": next_idx})
				for emsg in enter_msgs:
					turn_log.append({"type": "ability_trigger", "actor": "enemy", "message": emsg.get("message", "")})
				# Grant XP for the defeated enemy
				_grant_xp_for_defeat(battle, enemy, turn_log)
				# Accumulate drops from defeated creature (deferred)
				var mid_drops = _calculate_drops(enemy)
				if not battle.has("pending_drops"):
					battle["pending_drops"] = {}
				for item_id in mid_drops:
					battle["pending_drops"][item_id] = battle["pending_drops"].get(item_id, 0) + mid_drops[item_id]
				_send_turn_result.rpc_id(peer_id, turn_log, player_creature.hp, player_creature.get("pp", []), new_enemy.hp)
				_send_state_to_peer(battle, peer_id)
				battle.state = "waiting_action"
				return

		# Victory!
		_grant_xp_for_defeat(battle, enemy, turn_log)
		# Collect all pending drops + final creature drops
		var all_drops: Dictionary = battle.get("pending_drops", {}).duplicate()
		var final_drops = _calculate_drops(enemy)
		for item_id in final_drops:
			all_drops[item_id] = all_drops.get(item_id, 0) + final_drops[item_id]
		turn_log.append({"type": "victory", "drops": all_drops})
		_send_turn_result.rpc_id(peer_id, turn_log, player_creature.hp, player_creature.get("pp", []), enemy.hp)
		_send_state_to_peer(battle, peer_id)
		_grant_battle_rewards.rpc_id(peer_id, all_drops)
		for item_id in all_drops:
			NetworkManager.server_add_inventory(peer_id, item_id, all_drops[item_id])
			# Check for fragment auto-combine
			if item_id.begins_with("fragment_"):
				NetworkManager._check_fragment_combine(peer_id, item_id)

		# Trainer rewards
		if battle.mode == BattleMode.TRAINER and battle.trainer_id != "":
			var trainer = DataRegistry.get_trainer(battle.trainer_id)
			if trainer:
				NetworkManager.server_add_money(peer_id, trainer.reward_money)
				for ing_id in trainer.reward_ingredients:
					NetworkManager.server_add_inventory(peer_id, ing_id, trainer.reward_ingredients[ing_id])
				_grant_trainer_rewards_client.rpc_id(peer_id, trainer.reward_money, trainer.reward_ingredients)
				# Check for first-defeat recipe scroll reward
				var is_first_defeat = true
				if peer_id in NetworkManager.player_data_store:
					var pdata = NetworkManager.player_data_store[peer_id]
					var defeated = pdata.get("defeated_trainers", {})
					if battle.trainer_id in defeated:
						is_first_defeat = false
				if is_first_defeat and trainer.reward_recipe_scroll_id != "":
					NetworkManager.server_add_inventory(peer_id, trainer.reward_recipe_scroll_id, 1)
					NetworkManager._sync_inventory_full.rpc_id(peer_id, NetworkManager.player_data_store[peer_id].get("inventory", {}))
					var scroll = DataRegistry.get_recipe_scroll(trainer.reward_recipe_scroll_id)
					var scroll_name = scroll.display_name if scroll else trainer.reward_recipe_scroll_id
					NetworkManager._notify_recipe_unlocked.rpc_id(peer_id, "", "Received " + scroll_name + "!")
					print("[Trainer] ", peer_id, " received recipe scroll: ", scroll_name)
				# Record defeat
				if peer_id in NetworkManager.player_data_store:
					var pdata = NetworkManager.player_data_store[peer_id]
					if not pdata.has("defeated_trainers"):
						pdata["defeated_trainers"] = {}
					pdata["defeated_trainers"][battle.trainer_id] = int(Time.get_unix_time_from_system())
				# Notify gatekeeper NPCs that gate is now open
				for npc in get_tree().get_nodes_in_group("trainer_npc"):
					if npc.trainer_id == battle.trainer_id and npc.is_gatekeeper:
						npc.update_gate_for_peer(peer_id)
				# Send post-battle dialogue
				_trainer_dialogue_client.rpc_id(peer_id, trainer.display_name, trainer.dialogue_after, false)

		_end_battle_for_peer(battle, peer_id, true)
		return

	if player_creature.hp <= 0:
		var alive_idx = _find_alive_creature(battle.side_a_party, battle.side_a_active_idx)
		if alive_idx == -1:
			turn_log.append({"type": "defeat"})
			_send_turn_result.rpc_id(peer_id, turn_log, 0, player_creature.get("pp", []), enemy.hp)
			_send_state_to_peer(battle, peer_id)
			# Loss penalty: lose 50% money + teleport to spawn
			_apply_defeat_penalty(battle, peer_id)
			_end_battle_for_peer(battle, peer_id, false)
			return
		else:
			turn_log.append({"type": "fainted", "need_switch": true})
			_send_turn_result.rpc_id(peer_id, turn_log, player_creature.hp, player_creature.get("pp", []), enemy.hp)
			_send_state_to_peer(battle, peer_id)
			battle.state = "waiting_action"
			return

	_send_turn_result.rpc_id(peer_id, turn_log, player_creature.hp, player_creature.get("pp", []), enemy.hp)
	_send_state_to_peer(battle, peer_id)
	battle.state = "waiting_action"

# === XP / LEVELING / EVOLUTION ===

func _grant_xp_for_defeat(battle: Dictionary, defeated_enemy: Dictionary, _turn_log: Array) -> void:
	DataRegistry.ensure_loaded()
	var species = DataRegistry.get_species(defeated_enemy.get("species_id", ""))
	if species == null:
		return

	var base_xp = species.base_xp_yield
	var enemy_level = defeated_enemy.get("level", 5)
	var raw_xp = int(base_xp * enemy_level / 5.0)

	# Mode multiplier
	var xp_mult = 1.0
	match battle.mode:
		BattleMode.TRAINER:
			xp_mult = 1.5
		BattleMode.PVP:
			xp_mult = 1.25

	# Grant XP to all party members (participants=full, bench=50%)
	var peer_id = battle.side_a_peer

	# Buff multiplier (XP multiplier food buff)
	var buff_mult = NetworkManager.server_get_buff_value(peer_id, "xp_multiplier")
	if buff_mult > 0.0:
		xp_mult *= buff_mult

	var xp_amount = int(raw_xp * xp_mult)
	var participants = battle.get("participants_a", [0])
	var xp_results = []

	for idx in range(battle.side_a_party.size()):
		var creature = battle.side_a_party[idx]
		if creature.get("hp", 0) <= 0 and idx != battle.side_a_active_idx:
			continue # Dead non-active creatures don't get XP

		var is_participant = idx in participants
		var this_xp = xp_amount if is_participant else int(xp_amount * 0.5)

		# Grant EVs (only participants)
		if is_participant:
			for stat in species.ev_yield:
				var ev_val = int(species.ev_yield[stat])
				if not creature.has("evs"):
					creature["evs"] = {}
				var total_evs = _count_total_evs(creature.get("evs", {}))
				if total_evs < 510:
					creature["evs"][stat] = creature["evs"].get(stat, 0) + ev_val

		# Grant XP
		var _old_level = creature.get("level", 1)
		creature["xp"] = creature.get("xp", 0) + this_xp
		var xp_to_next = creature.get("xp_to_next", 100)

		var level_ups = []
		var new_moves_learned = []
		var evolved = false
		var new_species_id = ""

		# Check for level-up(s)
		while creature["xp"] >= xp_to_next:
			creature["xp"] -= xp_to_next
			creature["level"] += 1
			var new_level = creature["level"]
			xp_to_next = CreatureInstance._calc_xp_to_next(new_level)
			creature["xp_to_next"] = xp_to_next

			# Recalculate stats
			_recalc_stats(creature)
			level_ups.append(new_level)

			# Check learnset
			var c_species = DataRegistry.get_species(creature.get("species_id", ""))
			if c_species and c_species.learnset.has(new_level):
				var new_move = c_species.learnset[new_level]
				var current_moves = creature.get("moves", [])
				if new_move not in current_moves:
					if current_moves.size() < 4:
						if current_moves is PackedStringArray:
							current_moves = Array(current_moves)
							current_moves.append(new_move)
							creature["moves"] = PackedStringArray(current_moves)
						else:
							current_moves.append(new_move)
						# Set PP for new move
						var move_def = DataRegistry.get_move(new_move)
						var pp_arr = creature.get("pp", [])
						if pp_arr is PackedInt32Array:
							pp_arr = Array(pp_arr)
							pp_arr.append(move_def.pp if move_def else 10)
							creature["pp"] = PackedInt32Array(pp_arr)
						else:
							pp_arr.append(move_def.pp if move_def else 10)
						new_moves_learned.append({"move_id": new_move, "auto": true})
					else:
						new_moves_learned.append({"move_id": new_move, "auto": false})

			# Check evolution
			if c_species and c_species.evolves_to != "" and new_level >= c_species.evolution_level:
				var evo_species = DataRegistry.get_species(c_species.evolves_to)
				if evo_species:
					evolved = true
					new_species_id = c_species.evolves_to
					creature["species_id"] = new_species_id
					creature["nickname"] = evo_species.display_name
					creature["types"] = Array(evo_species.types)
					_recalc_stats(creature)
					# Learn evolution move
					if c_species.evolution_move != "":
						var evo_move = c_species.evolution_move
						var emoves = creature.get("moves", [])
						if evo_move not in emoves:
							if emoves.size() < 4:
								if emoves is PackedStringArray:
									emoves = Array(emoves)
									emoves.append(evo_move)
									creature["moves"] = PackedStringArray(emoves)
								else:
									emoves.append(evo_move)
								var move_def = DataRegistry.get_move(evo_move)
								var epp = creature.get("pp", [])
								if epp is PackedInt32Array:
									epp = Array(epp)
									epp.append(move_def.pp if move_def else 10)
									creature["pp"] = PackedInt32Array(epp)
								else:
									epp.append(move_def.pp if move_def else 10)
								new_moves_learned.append({"move_id": evo_move, "auto": true})
							else:
								new_moves_learned.append({"move_id": evo_move, "auto": false})

		xp_results.append({
			"creature_idx": idx,
			"xp_gained": this_xp,
			"level_ups": level_ups,
			"new_moves": new_moves_learned,
			"evolved": evolved,
			"new_species_id": new_species_id,
		})

	if xp_results.size() > 0:
		_send_xp_result.rpc_id(peer_id, {"results": xp_results})

func _recalc_stats(creature: Dictionary) -> void:
	var species = DataRegistry.get_species(creature.get("species_id", ""))
	if species == null:
		return
	var lvl = creature.get("level", 1)
	var mult = 1.0 + (lvl - 1) * 0.1
	var evs = creature.get("evs", {})
	var old_max_hp = creature.get("max_hp", 1)
	creature["max_hp"] = int(species.base_hp * mult) + int(evs.get("hp", 0) / 4.0)
	creature["attack"] = int(species.base_attack * mult) + int(evs.get("attack", 0) / 4.0)
	creature["defense"] = int(species.base_defense * mult) + int(evs.get("defense", 0) / 4.0)
	creature["sp_attack"] = int(species.base_sp_attack * mult) + int(evs.get("sp_attack", 0) / 4.0)
	creature["sp_defense"] = int(species.base_sp_defense * mult) + int(evs.get("sp_defense", 0) / 4.0)
	creature["speed"] = int(species.base_speed * mult) + int(evs.get("speed", 0) / 4.0)
	# Heal the difference in max HP
	var hp_gain = creature["max_hp"] - old_max_hp
	if hp_gain > 0:
		creature["hp"] = min(creature["max_hp"], creature.get("hp", 0) + hp_gain)

func _count_total_evs(evs: Dictionary) -> int:
	var total = 0
	for key in evs:
		total += int(evs[key])
	return total

# === PVP TURN RESOLUTION ===

func _resolve_pvp_turn(battle: Dictionary) -> void:
	var a_creature = battle.side_a_party[battle.side_a_active_idx]
	var b_creature = battle.side_b_party[battle.side_b_active_idx]
	var a_log = []
	var b_log = []

	# Clear protection
	a_creature["is_protecting"] = false
	b_creature["is_protecting"] = false

	var a_action = battle.side_a_action
	var b_action = battle.side_b_action
	battle.side_a_action = null
	battle.side_b_action = null

	# Handle switches first
	if a_action.type == "switch":
		_process_switch(battle, "a", int(a_action.data))
	if b_action.type == "switch":
		_process_switch(battle, "b", int(b_action.data))

	# Get fresh references after switches
	a_creature = battle.side_a_party[battle.side_a_active_idx]
	b_creature = battle.side_b_party[battle.side_b_active_idx]

	# Handle moves
	if a_action.type == "move" and b_action.type == "move":
		var a_move = DataRegistry.get_move(a_action.data)
		var b_move = DataRegistry.get_move(b_action.data)
		var a_pri = a_move.priority if a_move else 0
		var b_pri = b_move.priority if b_move else 0
		var a_spd = BattleCalculator.get_speed(a_creature)
		var b_spd = BattleCalculator.get_speed(b_creature)
		var a_first = _determine_order(a_pri, b_pri, a_spd, b_spd)

		if a_first:
			var r1 = _execute_action(a_creature, b_creature, a_move, "player", battle)
			a_log.append(r1)
			b_log.append(_swap_actor(r1))
			if b_creature.hp > 0:
				var r2 = _execute_action(b_creature, a_creature, b_move, "player", battle)
				b_log.append(r2)
				a_log.append(_swap_actor(r2))
		else:
			var r1 = _execute_action(b_creature, a_creature, b_move, "player", battle)
			b_log.append(r1)
			a_log.append(_swap_actor(r1))
			if a_creature.hp > 0:
				var r2 = _execute_action(a_creature, b_creature, a_move, "player", battle)
				a_log.append(r2)
				b_log.append(_swap_actor(r2))
	elif a_action.type == "move":
		var a_move = DataRegistry.get_move(a_action.data)
		var r = _execute_action(a_creature, b_creature, a_move, "player", battle)
		a_log.append(r)
		b_log.append(_swap_actor(r))
	elif b_action.type == "move":
		var b_move = DataRegistry.get_move(b_action.data)
		var r = _execute_action(b_creature, a_creature, b_move, "player", battle)
		b_log.append(r)
		a_log.append(_swap_actor(r))

	# End of turn — collect entries and add perspective-swapped copies to both logs
	var eot_log: Array = []
	_apply_end_of_turn(battle, eot_log)
	for entry in eot_log:
		a_log.append(entry)
		b_log.append(_swap_actor(entry))
	battle.turn += 1

	# Check outcomes
	if b_creature.hp <= 0:
		var next = _find_alive_creature(battle.side_b_party, battle.side_b_active_idx)
		if next == -1:
			a_log.append({"type": "victory", "drops": {}})
			b_log.append({"type": "defeat"})
			_send_turn_result.rpc_id(battle.side_a_peer, a_log, a_creature.hp, a_creature.get("pp", []), 0)
			_send_turn_result.rpc_id(battle.side_b_peer, b_log, b_creature.hp, b_creature.get("pp", []), a_creature.hp)
			_send_state_to_peer(battle, battle.side_a_peer)
			_send_state_to_peer(battle, battle.side_b_peer)
			_handle_pvp_end(battle, "a_wins")
			return

	if a_creature.hp <= 0:
		var next = _find_alive_creature(battle.side_a_party, battle.side_a_active_idx)
		if next == -1:
			b_log.append({"type": "victory", "drops": {}})
			a_log.append({"type": "defeat"})
			_send_turn_result.rpc_id(battle.side_a_peer, a_log, 0, a_creature.get("pp", []), b_creature.hp)
			_send_turn_result.rpc_id(battle.side_b_peer, b_log, b_creature.hp, b_creature.get("pp", []), 0)
			_send_state_to_peer(battle, battle.side_a_peer)
			_send_state_to_peer(battle, battle.side_b_peer)
			_handle_pvp_end(battle, "b_wins")
			return

	# Send results to both players
	_send_turn_result.rpc_id(battle.side_a_peer, a_log, a_creature.hp, a_creature.get("pp", []), b_creature.hp)
	_send_turn_result.rpc_id(battle.side_b_peer, b_log, b_creature.hp, b_creature.get("pp", []), a_creature.hp)
	_send_state_to_peer(battle, battle.side_a_peer)
	_send_state_to_peer(battle, battle.side_b_peer)
	battle.state = "waiting_both"
	battle.timeout_timer = 30.0

func _swap_actor(result: Dictionary) -> Dictionary:
	var swapped = result.duplicate(true)
	if swapped.get("actor", "") == "player":
		swapped["actor"] = "enemy"
	elif swapped.get("actor", "") == "enemy":
		swapped["actor"] = "player"
	return swapped

func _handle_pvp_end(battle: Dictionary, winner: String) -> void:
	var winner_peer = battle.side_a_peer if winner == "a_wins" else battle.side_b_peer
	var loser_peer = battle.side_b_peer if winner == "a_wins" else battle.side_a_peer

	# PvP rewards: winner gets 25% of each ingredient stack from loser
	if loser_peer in NetworkManager.player_data_store:
		var loser_data = NetworkManager.player_data_store[loser_peer]
		var loser_inv = loser_data.get("inventory", {})
		var transfer = {}
		for item_id in loser_inv:
			var amount = max(1, int(loser_inv[item_id] * 0.25))
			transfer[item_id] = amount
		for item_id in transfer:
			NetworkManager.server_remove_inventory(loser_peer, item_id, transfer[item_id])
			NetworkManager.server_add_inventory(winner_peer, item_id, transfer[item_id])
		_grant_battle_rewards.rpc_id(winner_peer, transfer)
		_pvp_loss_notify.rpc_id(loser_peer, transfer)

	# Heal loser's party
	if loser_peer in NetworkManager.player_data_store:
		var party = NetworkManager.player_data_store[loser_peer].get("party", [])
		for c in party:
			c["hp"] = c.get("max_hp", 40)

	# XP for winner
	var _winner_battle_side = "a" if winner == "a_wins" else "b"
	var loser_side = "b" if winner == "a_wins" else "a"
	var loser_active = battle["side_" + loser_side + "_party"][battle["side_" + loser_side + "_active_idx"]]
	# Grant XP using a temporary override
	var saved_peer = battle.side_a_peer
	var saved_participants = battle.participants_a
	if winner == "b_wins":
		battle.side_a_peer = battle.side_b_peer
		battle.participants_a = battle.participants_b
		battle.side_a_party = battle.side_b_party
	_grant_xp_for_defeat(battle, loser_active, [])
	if winner == "b_wins":
		battle.side_a_peer = saved_peer
		battle.participants_a = saved_participants

	_end_battle_full(battle, winner)

# === SWITCH ===

func _process_switch(battle: Dictionary, side: String, new_idx: int) -> void:
	var party = battle["side_" + side + "_party"]
	var active_key = "side_" + side + "_active_idx"
	if new_idx < 0 or new_idx >= party.size():
		if battle.mode != BattleMode.PVP:
			battle.state = "waiting_action"
		return
	if party[new_idx].get("hp", 0) <= 0:
		if battle.mode != BattleMode.PVP:
			battle.state = "waiting_action"
		return

	var old_idx = battle[active_key]
	battle[active_key] = new_idx

	# Track participant
	var participants_key = "participants_" + side
	if new_idx not in battle[participants_key]:
		battle[participants_key].append(new_idx)

	var new_creature = party[new_idx]

	# Apply entry hazards
	var hazard_key = "side_" + side + "_hazards"
	var hazard_results = FieldEffects.apply_hazards_on_switch(new_creature, battle[hazard_key])

	# Ability on_enter
	var opponent_side = "b" if side == "a" else "a"
	var opponent = battle["side_" + opponent_side + "_party"][battle["side_" + opponent_side + "_active_idx"]]
	var switch_enter_msgs = AbilityEffects.on_enter(new_creature, opponent, battle)

	# For non-PvP, send switch result and enemy attacks
	if battle.mode != BattleMode.PVP:
		var peer_id = battle["side_" + side + "_peer"]
		var actor = "player" if side == "a" else "enemy"
		var switch_log: Array = [{"type": "switch", "actor": actor, "from": old_idx, "to": new_idx}]
		for emsg in switch_enter_msgs:
			switch_log.append({"type": "ability_trigger", "actor": actor, "message": emsg.get("message", "")})
		for hr in hazard_results:
			hr["actor"] = actor
			switch_log.append(hr)

		# Enemy attacks after switch (unless old creature fainted)
		if party[old_idx].get("hp", 0) > 0 and side == "a":
			var enemy = battle.side_b_party[battle.side_b_active_idx]
			var enemy_move_id: String
			if battle.mode == BattleMode.TRAINER:
				enemy_move_id = BattleAI.pick_move(battle, "b")
			else:
				enemy_move_id = _pick_enemy_move(enemy)
			var enemy_move = DataRegistry.get_move(enemy_move_id)
			if enemy_move:
				var r = _execute_action(enemy, new_creature, enemy_move, "enemy", battle)
				switch_log.append(r)

		var active = party[battle[active_key]]
		var opp = battle["side_" + opponent_side + "_party"][battle["side_" + opponent_side + "_active_idx"]]
		_send_turn_result.rpc_id(peer_id, switch_log, active.hp, active.get("pp", []), opp.hp)
		_send_state_to_peer(battle, peer_id)
		battle.state = "waiting_action"

# === FLEE ===

func _process_flee(battle: Dictionary) -> void:
	var peer_id = battle.side_a_peer
	# Can't flee trainer or PvP battles
	if battle.mode == BattleMode.TRAINER or battle.mode == BattleMode.PVP:
		battle.state = "waiting_action"
		return

	var player_creature = battle.side_a_party[battle.side_a_active_idx]
	var enemy = battle.side_b_party[battle.side_b_active_idx]
	var player_speed = BattleCalculator.get_speed(player_creature)
	var enemy_speed = BattleCalculator.get_speed(enemy)
	var flee_chance = 0.5 + 0.2 * (float(player_speed) / max(1, float(enemy_speed)) - 1.0)
	flee_chance = clampf(flee_chance, 0.2, 0.9)

	if randf() < flee_chance:
		_send_turn_result.rpc_id(peer_id, [{"type": "fled"}], 0, [], 0)
		_end_battle_for_peer(battle, peer_id, false)
	else:
		var enemy_move_id = _pick_enemy_move(enemy)
		var enemy_move = DataRegistry.get_move(enemy_move_id)
		var flee_log: Array = [{"type": "flee_failed"}]
		if enemy_move:
			var r = _execute_action(enemy, player_creature, enemy_move, "enemy", battle)
			flee_log.append(r)
		_send_turn_result.rpc_id(peer_id, flee_log, player_creature.hp, player_creature.get("pp", []), enemy.hp)
		_send_state_to_peer(battle, peer_id)
		battle.state = "waiting_action"

# === AI ===

func _pick_enemy_move(enemy: Dictionary) -> String:
	var moves = enemy.get("moves", [])
	var pp = enemy.get("pp", [])
	var available = []
	for i in range(moves.size()):
		if i < pp.size() and pp[i] > 0:
			available.append(i)
		elif i >= pp.size():
			available.append(i)
	if available.size() == 0:
		return "quick_bite"
	var idx = available[randi() % available.size()]
	if idx < pp.size():
		pp[idx] -= 1
	return moves[idx]

# === UTILITY ===

func _find_alive_creature(party: Array, exclude_idx: int) -> int:
	for i in range(party.size()):
		if i != exclude_idx and party[i].get("hp", 0) > 0:
			return i
	return -1

func _find_move_index(creature: Dictionary, move_id: String) -> int:
	var moves_arr = creature.get("moves", [])
	for i in range(moves_arr.size()):
		if moves_arr[i] == move_id:
			return i
	return -1

func _calculate_drops(enemy: Dictionary) -> Dictionary:
	var species = DataRegistry.get_species(enemy.get("species_id", ""))
	if species == null:
		return {}
	var drops = {}
	for drop_id in species.drop_ingredient_ids:
		var amount = randi_range(species.drop_min, species.drop_max)
		drops[drop_id] = amount
	# Recipe fragment drops
	if species.drop_fragment_id != "" and species.drop_fragment_chance > 0.0:
		if randf() < species.drop_fragment_chance:
			var frag_id = "fragment_" + species.drop_fragment_id
			drops[frag_id] = drops.get(frag_id, 0) + 1
	return drops

# === BATTLE END ===

func _end_battle_for_peer(battle: Dictionary, peer_id: int, victory: bool) -> void:
	print("[BattleManager] _end_battle_for_peer: peer=", peer_id, " battle_id=", battle.battle_id, " victory=", victory)
	# Save party state
	if peer_id == battle.side_a_peer and battle.side_a_party.size() > 0:
		NetworkManager.server_update_party(peer_id, battle.side_a_party)
	elif peer_id == battle.side_b_peer and battle.side_b_party.size() > 0:
		NetworkManager.server_update_party(peer_id, battle.side_b_party)

	# Clean up maps
	player_battle_map.erase(peer_id)
	# If single-player battle, clean up entirely
	if battle.side_b_peer == 0:
		battles.erase(battle.battle_id)

	var encounter_mgr = get_node_or_null("/root/Main/GameWorld/EncounterManager")
	if encounter_mgr:
		encounter_mgr.end_encounter(peer_id)

	_battle_ended_client.rpc_id(peer_id, victory)

func _end_battle_full(battle: Dictionary, result: String) -> void:
	# Save both sides
	if battle.side_a_party.size() > 0:
		NetworkManager.server_update_party(battle.side_a_peer, battle.side_a_party)
	if battle.side_b_peer > 0 and battle.side_b_party.size() > 0:
		NetworkManager.server_update_party(battle.side_b_peer, battle.side_b_party)

	player_battle_map.erase(battle.side_a_peer)
	if battle.side_b_peer > 0:
		player_battle_map.erase(battle.side_b_peer)
	battles.erase(battle.battle_id)

	var encounter_mgr = get_node_or_null("/root/Main/GameWorld/EncounterManager")
	if encounter_mgr:
		encounter_mgr.end_encounter(battle.side_a_peer)
		if battle.side_b_peer > 0:
			encounter_mgr.end_encounter(battle.side_b_peer)

	match result:
		"a_wins":
			_battle_ended_client.rpc_id(battle.side_a_peer, true)
			if battle.side_b_peer > 0:
				_battle_ended_client.rpc_id(battle.side_b_peer, false)
		"b_wins":
			_battle_ended_client.rpc_id(battle.side_a_peer, false)
			if battle.side_b_peer > 0:
				_battle_ended_client.rpc_id(battle.side_b_peer, true)
		"draw":
			_battle_ended_client.rpc_id(battle.side_a_peer, false)
			if battle.side_b_peer > 0:
				_battle_ended_client.rpc_id(battle.side_b_peer, false)

func _apply_defeat_penalty(_battle: Dictionary, peer_id: int) -> void:
	if peer_id not in NetworkManager.player_data_store:
		return
	var pdata = NetworkManager.player_data_store[peer_id]
	var current_money = int(pdata.get("money", 0))
	var penalty = int(floor(current_money * 0.5))
	if penalty > 0:
		NetworkManager.server_remove_money(peer_id, penalty)
	# Reset position to spawn
	pdata["position"] = {"x": 0.0, "y": 1.0, "z": 3.0}
	# Teleport the player node server-side (position syncs via StateSync)
	var player_node = NetworkManager._get_player_node(peer_id)
	if player_node:
		player_node.position = Vector3(0.0, 1.0, 3.0)
	# Notify client
	_battle_defeat_penalty.rpc_id(peer_id, penalty)

@rpc("authority", "reliable")
func _battle_defeat_penalty(money_lost: int) -> void:
	PlayerData.money = max(0, PlayerData.money - money_lost)
	defeat_penalty_received.emit(money_lost)

# Called when a player disconnects mid-battle
func handle_player_disconnect(peer_id: int) -> void:
	var battle = _get_battle_for_peer(peer_id)
	if battle == null:
		return
	if battle.mode == BattleMode.PVP:
		var winner = "b_wins" if peer_id == battle.side_a_peer else "a_wins"
		_handle_pvp_end(battle, winner)
	else:
		player_battle_map.erase(peer_id)
		battles.erase(battle.battle_id)

# === CLIENT RPCs ===

@rpc("authority", "reliable")
func _start_battle_client(enemy_data: Dictionary, battle_mode: int, opponent_name: String = "") -> void:
	start_battle_client(enemy_data, battle_mode, opponent_name)

@rpc("authority", "reliable")
func _send_turn_result(turn_log: Array, player_hp: int, player_pp: Array, enemy_hp: int) -> void:
	turn_result_received.emit(turn_log)
	if client_active_creature_idx < PlayerData.party.size():
		PlayerData.party[client_active_creature_idx]["hp"] = player_hp
		if player_pp.size() > 0:
			PlayerData.party[client_active_creature_idx]["pp"] = player_pp
	client_enemy["hp"] = enemy_hp
	awaiting_action = true

@rpc("authority", "reliable")
func _grant_battle_rewards(drops: Dictionary) -> void:
	for item_id in drops:
		PlayerData.add_to_inventory(item_id, drops[item_id])
	battle_rewards_received.emit(drops)

@rpc("authority", "reliable")
func _grant_trainer_rewards_client(money: int, ingredients: Dictionary) -> void:
	PlayerData.money += money
	for item_id in ingredients:
		PlayerData.add_to_inventory(item_id, ingredients[item_id])
	trainer_rewards_received.emit(money, ingredients)

@rpc("authority", "reliable")
func _send_xp_result(results: Dictionary) -> void:
	xp_result_received.emit(results)
	# Update local party data with XP/level changes
	for r in results.get("results", []):
		var idx = r.get("creature_idx", 0)
		if idx < PlayerData.party.size():
			var c = PlayerData.party[idx]
			c["xp"] = c.get("xp", 0) + r.get("xp_gained", 0)
			for lvl in r.get("level_ups", []):
				c["level"] = lvl
			if r.get("evolved", false):
				c["species_id"] = r.get("new_species_id", c["species_id"])
	PlayerData.party_changed.emit()

@rpc("authority", "reliable")
func _battle_ended_client(victory: bool) -> void:
	in_battle = false
	awaiting_action = false
	battle_ended.emit(victory)
	if not victory:
		PlayerData.heal_all_creatures()

@rpc("authority", "reliable")
func _receive_battle_state(state: Dictionary) -> void:
	_apply_battle_state(state)

func _apply_battle_state(state: Dictionary) -> void:
	client_weather = state.get("weather", "")
	client_weather_turns = state.get("weather_turns", 0)
	client_player_hazards = state.get("player_hazards", [])
	client_enemy_hazards = state.get("enemy_hazards", [])
	client_player_stat_stages = state.get("player_stat_stages", {})
	client_enemy_stat_stages = state.get("enemy_stat_stages", {})
	client_player_status_turns = state.get("player_status_turns", 0)
	client_enemy_status_turns = state.get("enemy_status_turns", 0)
	# Update enemy creature data from state
	var ec = state.get("enemy_creature", {})
	if not ec.is_empty():
		client_enemy["nickname"] = ec.get("nickname", client_enemy.get("nickname", "???"))
		client_enemy["level"] = ec.get("level", client_enemy.get("level", 1))
		client_enemy["hp"] = ec.get("hp", client_enemy.get("hp", 0))
		client_enemy["max_hp"] = ec.get("max_hp", client_enemy.get("max_hp", 1))
		client_enemy["species_id"] = ec.get("species_id", client_enemy.get("species_id", ""))
		client_enemy["types"] = ec.get("types", [])
		client_enemy["status"] = ec.get("status", "")
		client_enemy["status_turns"] = ec.get("status_turns", 0)
	battle_state_updated.emit()

@rpc("authority", "reliable")
func _pvp_challenge_received(challenger_name: String, challenger_peer: int) -> void:
	pvp_challenge_received.emit(challenger_name, challenger_peer)

@rpc("authority", "reliable")
func _pvp_loss_notify(lost_items: Dictionary) -> void:
	for item_id in lost_items:
		PlayerData.remove_from_inventory(item_id, lost_items[item_id])
	pvp_loss_received.emit(lost_items)

@rpc("authority", "reliable")
func _trainer_dialogue_client(trainer_name: String, text: String, is_before: bool) -> void:
	trainer_dialogue.emit(trainer_name, text, is_before)

# === Move Learn RPCs ===

@rpc("any_peer", "reliable")
func request_move_replace(creature_idx: int, old_move_idx: int, new_move_id: String) -> void:
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	var battle = _get_battle_for_peer(sender)
	if battle == null:
		return
	if creature_idx >= battle.side_a_party.size():
		return
	var creature = battle.side_a_party[creature_idx]
	var moves = creature.get("moves", [])
	if old_move_idx < 0 or old_move_idx >= moves.size():
		return
	# Replace the move
	if moves is PackedStringArray:
		moves = Array(moves)
	moves[old_move_idx] = new_move_id
	creature["moves"] = moves
	# Set PP
	var pp_arr = creature.get("pp", [])
	if pp_arr is PackedInt32Array:
		pp_arr = Array(pp_arr)
	var move_def = DataRegistry.get_move(new_move_id)
	if old_move_idx < pp_arr.size():
		pp_arr[old_move_idx] = move_def.pp if move_def else 10
	creature["pp"] = pp_arr

@rpc("any_peer", "reliable")
func skip_move_learn() -> void:
	pass # Client chose not to learn the move

# === CLIENT ACTIONS ===

func start_battle_client(enemy_data: Dictionary, battle_mode: int = BattleMode.WILD, _opponent_name: String = "") -> void:
	if in_battle:
		print("[BattleManager] Client: ignoring duplicate _start_battle_client (already in battle)")
		return
	in_battle = true
	client_enemy = enemy_data.duplicate(true)
	client_active_creature_idx = PlayerData.get_first_alive_creature()
	awaiting_action = true
	client_battle_mode = battle_mode
	# Reset client state
	client_weather = ""
	client_weather_turns = 0
	client_player_hazards = []
	client_enemy_hazards = []
	client_player_stat_stages = {}
	client_enemy_stat_stages = {}
	client_player_status_turns = 0
	client_enemy_status_turns = 0
	# Reset summary accumulators
	summary_xp_results = []
	summary_drops = {}
	summary_trainer_money = 0
	summary_trainer_ingredients = {}
	summary_defeat_penalty = 0
	summary_pvp_loss = {}
	summary_evolutions = []
	summary_new_moves = []
	battle_started.emit()

func send_move(move_id: String) -> void:
	if not awaiting_action:
		return
	awaiting_action = false
	request_battle_action.rpc_id(1, "move", move_id)

func send_switch(creature_idx: int) -> void:
	if not awaiting_action:
		return
	awaiting_action = false
	request_battle_action.rpc_id(1, "switch", str(creature_idx))

func send_flee() -> void:
	if not awaiting_action:
		return
	awaiting_action = false
	request_battle_action.rpc_id(1, "flee", "")

func send_pvp_challenge(target_peer: int) -> void:
	request_pvp_challenge.rpc_id(1, target_peer)

func respond_to_pvp_challenge(challenger_peer: int, accepted: bool) -> void:
	respond_pvp_challenge.rpc_id(1, challenger_peer, accepted)

# === Gatekeeper Decline ===

@rpc("any_peer", "reliable")
func _respond_gatekeeper_decline(trainer_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id = multiplayer.get_remote_sender_id()
	# Push player back to safe position (south of gate)
	for npc in get_tree().get_nodes_in_group("trainer_npc"):
		if npc.trainer_id == trainer_id and npc.is_gatekeeper:
			var gate_pos = npc.global_position
			var safe_pos = Vector3(gate_pos.x, 1.0, gate_pos.z + 6.0)
			var player_node = NetworkManager._get_player_node(peer_id)
			if player_node:
				player_node.position = safe_pos
			# Explicitly hide trainer prompt since body_exited may not fire from teleport
			npc._hide_trainer_prompt.rpc_id(peer_id)
			break
