extends Node

# Attached to each player - handles interactions with world objects
var peer_id: int = 0
var parent_body: CharacterBody3D = null
var _showing_restaurant_prompt: bool = false
var _showing_player_prompt: bool = false
var _showing_contextual_prompt: bool = false
var _last_contextual_text: String = ""
const RESTAURANT_DOOR_RANGE: float = 4.5
const PLAYER_INTERACT_RANGE: float = 5.0

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

# Seed picker UI
var _seed_picker: CanvasLayer = null

func _ready() -> void:
	parent_body = get_parent() as CharacterBody3D
	if parent_body:
		peer_id = parent_body.name.to_int()

func _input(event: InputEvent) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	if event.is_action_pressed("friend_list"):
		var target_name := _find_nearest_player_name()
		if target_name != "":
			var player = get_parent()
			if player and player.get("is_busy"):
				return
			_try_friend_request(target_name)
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if peer_id != multiplayer.get_unique_id():
		return
	# Update proximity prompts
	_update_restaurant_prompt()
	_update_player_proximity_prompt()
	_update_contextual_prompt()
	# Busy lock: block all interactions (defense-in-depth; server also validates)
	var player = get_parent()
	if player and player.get("is_busy"):
		return
	# Client-side fishing guard — is_busy has network latency, so also check FishingUI
	var fishing_ui = get_node_or_null("/root/Main/GameWorld/UI/FishingUI")
	if fishing_ui and fishing_ui.is_fishing():
		return
	if Input.is_action_just_pressed("interact"):
		_try_interact()
	# PvP challenge (V key)
	if Input.is_action_just_pressed("pvp_challenge"):
		_try_pvp_challenge()
	# Trade (T key)
	if Input.is_action_just_pressed("trade"):
		_try_trade()

func _try_interact() -> void:
	if parent_body == null:
		return
	var pos = parent_body.global_position
	# Check for calendar board proximity (E key to view)
	var calendar = _find_nearest_area("calendar_board", pos, 3.0)
	if calendar and calendar.has_method("request_open_calendar"):
		calendar.request_open_calendar.rpc_id(1)
		return
	# Check for social NPC proximity (E key to talk — gifts go through dialogue UI only)
	var social_npc = _find_nearest_area("social_npc", pos, 3.0)
	if social_npc:
		if social_npc.has_method("request_talk"):
			social_npc.request_talk.rpc_id(1)
			return
	# Check for shop NPC proximity (E key to open shop)
	var shop = _find_nearest_area("shop_npc", pos, 3.0)
	if shop and shop.has_method("request_open_shop"):
		shop.request_open_shop.rpc_id(1)
		return
	# Check for bank NPC proximity (E key to open bank)
	var bank = _find_nearest_area("bank_npc", pos, 3.0)
	if bank and bank.has_method("request_open_bank"):
		bank.request_open_bank.rpc_id(1)
		return
	# Check for trainer NPC proximity (E key to challenge)
	var trainer = _find_nearest_area("trainer_npc", pos, 4.0)
	if trainer and trainer.has_method("request_challenge"):
		trainer.request_challenge.rpc_id(1)
		return
	# Check for restaurant exit door (E key to leave restaurant)
	if PlayerData.current_zone == "restaurant":
		var exit_door = _find_nearest_area("restaurant_exit_door", pos, 3.0)
		if exit_door:
			var rm = get_node_or_null("/root/Main/GameWorld/RestaurantManager")
			if rm:
				rm.request_exit_restaurant.rpc_id(1)
			return
	# Check for restaurant door proximity (interact key as alternative to walk-over)
	var door = _find_nearest_in_group("restaurant_door", pos, RESTAURANT_DOOR_RANGE)
	if door:
		var door_owner = door.get_meta("owner_name", "") if door.has_meta("owner_name") else ""
		# Static door has empty owner_name — use local player's name (enters YOUR restaurant)
		if door_owner == "":
			door_owner = PlayerData.player_name
		if door_owner != "":
			var rm = get_node_or_null("/root/Main/GameWorld/RestaurantManager")
			if rm:
				rm.request_enter_restaurant.rpc_id(1, door_owner)
			return
	# Check for excursion portal proximity (E key to enter)
	var portal = _find_nearest_in_group("excursion_portal", pos, 4.0)
	if portal:
		var excursion_mgr = get_node_or_null("/root/Main/GameWorld/ExcursionManager")
		if excursion_mgr:
			var zone_type: String = portal.get_meta("zone_type", "default")
			excursion_mgr.request_enter_excursion.rpc_id(1, zone_type)
		return
	# Check for storage station proximity
	var storage = _find_nearest_area("storage_station", pos, 3.0)
	if storage:
		_open_storage_ui()
		return
	# Check for crafting station proximity
	var station = _find_nearest_crafting_station(pos, 3.0)
	if station:
		_open_crafting_ui(station)
		return
	# Check for dig spots — no client tool gate, server validates in dig_spot.gd
	var dig_spot = _find_nearest_area("dig_spot", pos, 3.0)
	if dig_spot and dig_spot.has_method("request_dig"):
		if not PlayerData.equipped_tools.has("shovel"):
			_show_toast("You need a shovel to dig here")
			return
		dig_spot.request_dig.rpc_id(1)
		return
	# Check for harvestable world objects (trees, rocks, bushes) — server validates tool
	var harvestable = _find_nearest_in_group("harvestable_object", pos, 3.5)
	if harvestable and not harvestable.get("is_harvested"):
		harvestable.request_harvest.rpc_id(1)
		return
	# Check for fishing spots — no client tool gate, server validates in fishing_manager.gd
	var fishing_spot = _find_nearest_in_group("fishing_spot", pos, 5.0)
	if fishing_spot:
		if not PlayerData.equipped_tools.has("fishing_rod"):
			_show_toast("You need a fishing rod to fish here")
			return
		var table_id: String = fishing_spot.get_meta("fishing_table_id", "pond") if fishing_spot.has_meta("fishing_table_id") else "pond"
		var fishing_mgr = get_node_or_null("/root/Main/GameWorld/FishingManager")
		if fishing_mgr:
			fishing_mgr.request_cast_line.rpc_id(1, table_id)
		return
	# Check for farm plots — contextual action based on plot state (must be above water source)
	var nearest_fm = _find_nearest_farm_manager(pos)
	if nearest_fm:
		var plot_idx = nearest_fm.get_nearest_plot(pos, 3.0)
		if plot_idx >= 0:
			_interact_with_plot(nearest_fm, plot_idx)
			return
	# Check for water source — find nearest FarmManager (works for both community and restaurant farms)
	var water_source = _find_nearest_area("water_source", pos, 3.0)
	if water_source:
		if nearest_fm == null:
			nearest_fm = _find_nearest_farm_manager(pos)
		if nearest_fm:
			nearest_fm._request_refill.rpc_id(1)
		return

# === CONTEXTUAL FARM INTERACTION ===

func _interact_with_plot(farm_mgr: Node, plot_idx: int) -> void:
	var plot = farm_mgr.get_plot(plot_idx)
	if plot == null:
		return
	var state: int = plot.plot_state
	# PlotState enum: WILD=0, CLEARED=1, TILLED=2, PLANTED=3, WATERED=4, GROWING=5, READY=6, WILTING=7, DEAD=8
	match state:
		0, 8: # WILD, DEAD — clear
			if not PlayerData.equipped_tools.has("axe"):
				_show_toast("You need an axe to clear this")
				return
			farm_mgr.request_farm_action.rpc_id(1, plot_idx, "clear", "")
		1: # CLEARED — till
			if not PlayerData.equipped_tools.has("hoe"):
				_show_toast("You need a hoe to till this soil")
				return
			farm_mgr.request_farm_action.rpc_id(1, plot_idx, "till", "")
		2: # TILLED — plant
			_try_plant_seed(farm_mgr, plot_idx)
		3, 5, 7: # PLANTED, GROWING, WILTING — water or uproot
			if PlayerData.equipped_tools.has("watering_can") and PlayerData.watering_can_current > 0:
				farm_mgr.request_farm_action.rpc_id(1, plot_idx, "water", "")
			elif PlayerData.equipped_tools.has("hoe"):
				farm_mgr.request_farm_action.rpc_id(1, plot_idx, "uproot", "")
			elif not PlayerData.equipped_tools.has("watering_can"):
				_show_toast("You need a watering can")
			else:
				_show_toast("Watering can empty — refill at a water source")
		4: # WATERED — no-op
			_show_toast("Already watered — check back later")
		6: # READY — harvest (no tool needed)
			farm_mgr.request_farm_action.rpc_id(1, plot_idx, "harvest", "")

func _try_plant_seed(farm_mgr: Node, plot_idx: int) -> void:
	_show_seed_picker(farm_mgr, plot_idx)

func _show_seed_picker(farm_mgr: Node, plot_idx: int) -> void:
	if _seed_picker and is_instance_valid(_seed_picker):
		_seed_picker.queue_free()
	DataRegistry.ensure_loaded()
	# Gather seeds from inventory
	var seeds: Array = []
	for item_id in PlayerData.inventory:
		if PlayerData.inventory[item_id] <= 0:
			continue
		if _is_seed_item(item_id):
			seeds.append(item_id)
	if seeds.is_empty():
		_show_toast("No seeds in inventory")
		return

	_seed_picker = CanvasLayer.new()
	_seed_picker.layer = 100

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.anchor_left = 0.15
	panel.anchor_right = 0.85
	panel.anchor_top = 0.1
	panel.anchor_bottom = 0.9
	UITheme.style_modal(panel)
	_seed_picker.add_child(panel)

	var margin := MarginContainer.new()
	var m_size: int = int(UITheme.scaled(20))
	margin.add_theme_constant_override("margin_left", m_size)
	margin.add_theme_constant_override("margin_right", m_size)
	margin.add_theme_constant_override("margin_top", m_size)
	margin.add_theme_constant_override("margin_bottom", m_size)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", int(UITheme.scaled(10)))
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "Choose a Seed"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UITheme.style_subheading(title)
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = UITheme.scaled(200)
	vbox.add_child(scroll)

	var seed_list := VBoxContainer.new()
	seed_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_list.add_theme_constant_override("separation", int(UITheme.scaled(6)))
	scroll.add_child(seed_list)

	for seed_id in seeds:
		var info = DataRegistry.get_item_display_info(seed_id)
		var ingredient = DataRegistry.get_ingredient(seed_id)
		var count: int = PlayerData.inventory[seed_id]
		var display_name: String = info.get("display_name", seed_id)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(UITheme.scaled(8)))
		seed_list.add_child(row)

		# Icon
		var icon := UITheme.create_item_icon(info, int(UITheme.scaled(32)))
		row.add_child(icon)

		# Name + subtitle
		var text_col := VBoxContainer.new()
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_col)

		var name_label := Label.new()
		name_label.text = display_name
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		name_label.clip_text = true
		UITheme.style_body(name_label)
		text_col.add_child(name_label)

		var subtitle := Label.new()
		var season_text: String = ingredient.season.capitalize() if ingredient and ingredient.season != "" else "All Seasons"
		var grow_minutes: String = "%dm grow" % max(1, int(ingredient.grow_time / 60.0)) if ingredient else ""
		subtitle.text = "%s · %s" % [season_text, grow_minutes] if grow_minutes != "" else season_text
		subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		subtitle.clip_text = true
		UITheme.style_caption(subtitle)
		text_col.add_child(subtitle)

		# Count
		var count_label := Label.new()
		count_label.text = "x%d" % count
		count_label.size_flags_horizontal = Control.SIZE_SHRINK_END
		UITheme.style_body(count_label)
		row.add_child(count_label)

		# Plant button
		var btn := Button.new()
		btn.text = "Plant"
		btn.custom_minimum_size = Vector2(UITheme.scaled(70), UITheme.scaled(32))
		UITheme.style_button(btn, "primary")
		var sid = seed_id
		var fm = farm_mgr
		var pidx = plot_idx
		btn.pressed.connect(func():
			fm.request_farm_action.rpc_id(1, pidx, "plant", sid)
			_close_seed_picker()
		)
		row.add_child(btn)

	# Cancel button
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.custom_minimum_size.y = UITheme.scaled(36)
	UITheme.style_button(cancel_btn, "secondary")
	cancel_btn.pressed.connect(_close_seed_picker)
	vbox.add_child(cancel_btn)

	get_tree().root.add_child(_seed_picker)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ScreenTransition.open(_seed_picker, "fade_scale")

func _close_seed_picker() -> void:
	if _seed_picker and is_instance_valid(_seed_picker):
		await ScreenTransition.close(_seed_picker, "fade_scale")
		_seed_picker.queue_free()
		_seed_picker = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _is_seed_item(item_id: String) -> bool:
	var ingredient = DataRegistry.get_ingredient(item_id)
	if ingredient == null:
		return false
	if ingredient.category == "farm_crop":
		return true
	if item_id.ends_with("_seed"):
		return true
	return ingredient.display_name.to_lower().ends_with(" seed")

# === CONTEXTUAL PROMPTS ===

func _update_contextual_prompt() -> void:
	if parent_body == null:
		return
	# Don't override restaurant or player prompts
	if _showing_restaurant_prompt or _showing_player_prompt:
		if _showing_contextual_prompt:
			_hide_contextual_prompt()
		return
	var player = get_parent()
	if player and player.get("is_busy"):
		if _showing_contextual_prompt:
			_hide_contextual_prompt()
		return
	var pos = parent_body.global_position
	var prompt_text := _get_contextual_prompt(pos)
	if prompt_text != "":
		var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
		if hud and hud.has_method("show_interaction_prompt"):
			hud.show_interaction_prompt(prompt_text, true)
		_showing_contextual_prompt = true
		_last_contextual_text = prompt_text
	elif _showing_contextual_prompt:
		_hide_contextual_prompt()

func _hide_contextual_prompt() -> void:
	_showing_contextual_prompt = false
	_last_contextual_text = ""
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("hide_trainer_prompt"):
		hud.hide_trainer_prompt()

func _get_contextual_prompt(pos: Vector3) -> String:
	# Farm plots
	var fm = _find_nearest_farm_manager(pos)
	if fm:
		var plot_idx = fm.get_nearest_plot(pos, 3.0)
		if plot_idx >= 0:
			var plot = fm.get_plot(plot_idx)
			if plot:
				var state: int = plot.plot_state
				var crop := _get_crop_context(plot)
				match state:
					0: # WILD
						if not PlayerData.equipped_tools.has("axe"):
							return "Overgrown (need axe)"
						return "E: Clear"
					1: # CLEARED
						if not PlayerData.equipped_tools.has("hoe"):
							return "Cleared (need hoe)"
						return "E: Till"
					2: # TILLED
						return "E: Plant"
					3: # PLANTED
						var water_hint := _get_water_hint()
						if water_hint == "":
							if crop != "":
								return "E: Water — %s (just planted)" % crop
							return "E: Water"
						elif PlayerData.equipped_tools.has("hoe"):
							if crop != "":
								return "E: Uproot — %s" % crop
							return "E: Uproot"
						else:
							if crop != "":
								return "%s (just planted) — %s" % [crop, water_hint]
							return "Just planted — %s" % water_hint
					4: # WATERED
						var pct := int(plot.growth_progress * 100) if plot.get("growth_progress") != null else 0
						if crop != "":
							return "%s — watered, %d%% grown" % [crop, pct]
						return "Already watered"
					5: # GROWING
						var pct := int(plot.growth_progress * 100) if plot.get("growth_progress") != null else 0
						var water_hint := _get_water_hint()
						if water_hint == "":
							if crop != "":
								return "E: Water — %s (%d%% grown)" % [crop, pct]
							return "E: Water"
						elif PlayerData.equipped_tools.has("hoe"):
							if crop != "":
								return "E: Uproot — %s (%d%% grown)" % [crop, pct]
							return "E: Uproot"
						else:
							if crop != "":
								return "%s (%d%% grown) — %s" % [crop, pct, water_hint]
							return "%d%% grown — %s" % [pct, water_hint]
					6: # READY
						if crop != "":
							return "E: Harvest — %s" % crop
						return "E: Harvest"
					7: # WILTING
						var water_hint := _get_water_hint()
						if water_hint == "":
							if crop != "":
								return "E: Water — %s (wilting!)" % crop
							return "E: Water"
						elif PlayerData.equipped_tools.has("hoe"):
							if crop != "":
								return "E: Uproot — %s (wilting!)" % crop
							return "E: Uproot"
						else:
							if crop != "":
								return "%s (wilting!) — %s" % [crop, water_hint]
							return "Wilting! — %s" % water_hint
					8: # DEAD
						if not PlayerData.equipped_tools.has("axe"):
							return "Dead crop (need axe)"
						return "E: Clear (dead crop)"
	# Dig spots
	var dig_spot = _find_nearest_area("dig_spot", pos, 3.0)
	if dig_spot:
		if not PlayerData.equipped_tools.has("shovel"):
			return "Dig spot (need shovel)"
		return "E: Dig"
	# Fishing spots
	var fishing_spot = _find_nearest_in_group("fishing_spot", pos, 5.0)
	if fishing_spot:
		if not PlayerData.equipped_tools.has("fishing_rod"):
			return "Fishing spot (need rod)"
		return "E: Fish"
	# Crafting stations
	var station = _find_nearest_crafting_station(pos, 3.0)
	if station:
		for stype in ["kitchen", "workbench", "cauldron"]:
			if station.is_in_group("crafting_" + stype):
				return "E: Craft (%s)" % stype.capitalize()
		return "E: Craft"
	# Storage
	var storage = _find_nearest_area("storage_station", pos, 3.0)
	if storage:
		return "E: Storage"
	# Harvestable objects
	var harvestable = _find_nearest_in_group("harvestable_object", pos, 3.5)
	if harvestable and not harvestable.get("is_harvested"):
		return "E: Harvest"
	# Water source
	var water_source = _find_nearest_area("water_source", pos, 3.0)
	if water_source:
		if PlayerData.equipped_tools.has("watering_can"):
			var cap := PlayerData.get_watering_can_capacity()
			return "E: Refill (%d/%d)" % [PlayerData.watering_can_current, cap]
		return "Water Source"
	# Excursion portal
	var portal = _find_nearest_in_group("excursion_portal", pos, 4.0)
	if portal:
		return "E: Enter Excursion"
	# Restaurant exit
	if PlayerData.current_zone == "restaurant":
		var exit_door = _find_nearest_area("restaurant_exit_door", pos, 3.0)
		if exit_door:
			return "E: Exit Restaurant"
	return ""

func _get_crop_context(plot: Node) -> String:
	var seed_id: String = plot.planted_seed_id if plot.get("planted_seed_id") != null else ""
	if seed_id == "":
		return ""
	DataRegistry.ensure_loaded()
	var ingredient = DataRegistry.get_ingredient(seed_id)
	return ingredient.display_name if ingredient else seed_id

func _get_water_hint() -> String:
	if not PlayerData.equipped_tools.has("watering_can"):
		return "need watering can"
	if PlayerData.watering_can_current <= 0:
		return "can empty, refill"
	return ""

# === TOAST HELPER ===

func _show_toast(message: String) -> void:
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("show_toast"):
		hud.show_toast(message)

# === PROXIMITY PROMPTS ===

func _update_restaurant_prompt() -> void:
	if parent_body == null:
		return
	# Only show prompt when in overworld (not already in a restaurant)
	if PlayerData.current_zone == "restaurant":
		if _showing_restaurant_prompt:
			_hide_restaurant_prompt()
		return
	var pos = parent_body.global_position
	var door = _find_nearest_in_group("restaurant_door", pos, RESTAURANT_DOOR_RANGE)
	if door:
		var door_owner = door.get_meta("owner_name", "") if door.has_meta("owner_name") else ""
		if not _showing_restaurant_prompt:
			var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
			if hud and hud.has_method("show_interaction_prompt"):
				var prompt_text: String
				if door_owner == "":
					prompt_text = "Press E to enter My Restaurant"
				else:
					prompt_text = "Press E to enter %s's Restaurant" % door_owner
				hud.show_interaction_prompt(prompt_text, true)
				_showing_restaurant_prompt = true
	elif _showing_restaurant_prompt:
		_hide_restaurant_prompt()

func _hide_restaurant_prompt() -> void:
	_showing_restaurant_prompt = false
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("hide_trainer_prompt"):
		hud.hide_trainer_prompt()

func _find_nearest_player_name() -> String:
	if parent_body == null:
		return ""
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node == null:
		return ""
	var my_pos = parent_body.global_position
	var closest_name: String = ""
	var closest_dist: float = PLAYER_INTERACT_RANGE
	for child in players_node.get_children():
		if child is CharacterBody3D:
			var other_peer = child.name.to_int()
			if other_peer == peer_id or other_peer <= 0:
				continue
			var dist = child.global_position.distance_to(my_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest_name = child.get("player_name_display") if child.get("player_name_display") else ""
	return closest_name

func _try_friend_request(target_name: String) -> void:
	var friend_mgr = get_node_or_null("/root/Main/GameWorld/FriendManager")
	if friend_mgr:
		friend_mgr.request_send_friend_request.rpc_id(1, target_name)

func _update_player_proximity_prompt() -> void:
	if parent_body == null:
		return
	# Don't override restaurant prompt
	if _showing_restaurant_prompt:
		if _showing_player_prompt:
			_showing_player_prompt = false
		return
	var player = get_parent()
	var is_busy: bool = player and player.get("is_busy")
	if is_busy:
		if _showing_player_prompt:
			_hide_player_prompt()
		return
	var target_name := _find_nearest_player_name()
	if target_name != "":
		if not _showing_player_prompt:
			var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
			if hud and hud.has_method("show_interaction_prompt"):
				hud.show_interaction_prompt("F: Add Friend | T: Trade | V: Battle", true)
				_showing_player_prompt = true
	elif _showing_player_prompt:
		_hide_player_prompt()

func _hide_player_prompt() -> void:
	_showing_player_prompt = false
	var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
	if hud and hud.has_method("hide_trainer_prompt"):
		hud.hide_trainer_prompt()

func _try_pvp_challenge() -> void:
	if parent_body == null:
		return
	# Find nearest other player within 5 units
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node == null:
		return
	var my_pos = parent_body.global_position
	var closest_peer: int = 0
	var closest_dist: float = 5.0
	for child in players_node.get_children():
		if child is CharacterBody3D:
			var other_peer = child.name.to_int()
			if other_peer == peer_id or other_peer <= 0:
				continue
			var dist = child.global_position.distance_to(my_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest_peer = other_peer
	if closest_peer > 0:
		var battle_mgr = get_node_or_null("/root/Main/GameWorld/BattleManager")
		if battle_mgr:
			battle_mgr.send_pvp_challenge(closest_peer)

func _try_trade() -> void:
	if parent_body == null:
		return
	var players_node = get_node_or_null("/root/Main/GameWorld/Players")
	if players_node == null:
		return
	var my_pos = parent_body.global_position
	var closest_peer: int = 0
	var closest_dist: float = 5.0
	for child in players_node.get_children():
		if child is CharacterBody3D:
			var other_peer = child.name.to_int()
			if other_peer == peer_id or other_peer <= 0:
				continue
			var dist = child.global_position.distance_to(my_pos)
			if dist < closest_dist:
				closest_dist = dist
				closest_peer = other_peer
	if closest_peer > 0:
		NetworkManager.request_trade.rpc_id(1, closest_peer)

# === FIND HELPERS ===

func _find_nearest_in_group(group_name: String, pos: Vector3, max_dist: float) -> Node3D:
	var nodes = get_tree().get_nodes_in_group(group_name)
	var closest: Node3D = null
	var closest_dist = max_dist
	for node in nodes:
		if node is Node3D:
			var dist = node.global_position.distance_to(pos)
			if dist < closest_dist:
				closest_dist = dist
				closest = node
	return closest

func _find_nearest_area(meta_tag: String, pos: Vector3, max_dist: float) -> Area3D:
	var areas = get_tree().get_nodes_in_group(meta_tag)
	var closest: Area3D = null
	var closest_dist = max_dist
	for area in areas:
		if area is Area3D:
			var dist = area.global_position.distance_to(pos)
			if dist < closest_dist:
				closest_dist = dist
				closest = area
	return closest

func _find_nearest_farm_manager(pos: Vector3) -> Node:
	var farm_managers = get_tree().get_nodes_in_group("farm_manager")
	var closest: Node = null
	var closest_dist: float = INF
	for fm in farm_managers:
		if fm is Node3D:
			var dist = fm.global_position.distance_to(pos)
			if dist < closest_dist:
				closest_dist = dist
				closest = fm
	return closest

func _find_nearest_crafting_station(pos: Vector3, max_dist: float) -> Area3D:
	# Check for station-typed crafting areas
	for station_type in ["kitchen", "workbench", "cauldron"]:
		var area = _find_nearest_area("crafting_" + station_type, pos, max_dist)
		if area:
			return area
	# Fallback: check old "crafting_table" group (generic station)
	return _find_nearest_area("crafting_table", pos, max_dist)

func _open_storage_ui() -> void:
	var ui = get_node_or_null("/root/Main/GameWorld/UI/StorageUI")
	if ui and ui.has_method("open"):
		ui.open()

func _open_crafting_ui(station: Area3D = null) -> void:
	var ui = get_node_or_null("/root/Main/GameWorld/UI/CraftingUI")
	if ui:
		# Determine station type from group membership
		var station_type = ""
		if station:
			for stype in ["kitchen", "workbench", "cauldron"]:
				if station.is_in_group("crafting_" + stype):
					station_type = stype
					break
		if ui.has_method("open_for_station"):
			ui.open_for_station(station_type)
		else:
			ui.visible = !ui.visible
			if ui.visible and ui.has_method("refresh"):
				ui.refresh()
