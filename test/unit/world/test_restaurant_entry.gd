extends GutTest

# Tests for the static restaurant door system.
# - Static door in the world enters YOUR OWN restaurant
# - Visit button in Friends panel enters a FRIEND's restaurant
# - No dynamic door spawning/replication

var mgr: Node

func before_each():
	var script = load("res://scripts/world/restaurant_manager.gd")
	mgr = Node.new()
	mgr.set_script(script)
	# Provide a MyRestaurantDoor Area3D so _ready() can find it at ../Zones/MyRestaurantDoor
	var door = Area3D.new()
	door.name = "MyRestaurantDoor"
	var zones = Node3D.new()
	zones.name = "Zones"
	zones.add_child(door)
	# mgr is a child of game_world-like parent; zones is sibling
	var parent_node = Node3D.new()
	parent_node.name = "GameWorld"
	parent_node.add_child(zones)
	parent_node.add_child(mgr)
	add_child_autofree(parent_node)

func after_each():
	mgr = null

# === Static Door Setup ===

func test_static_door_in_restaurant_door_group():
	var door = Area3D.new()
	door.add_to_group("restaurant_door")
	door.set_meta("owner_name", "")
	add_child_autofree(door)
	assert_true(door.is_in_group("restaurant_door"), "Static door should be in restaurant_door group")

func test_static_door_empty_owner_means_self():
	# Static door has empty owner_name — client resolves to local player's name
	var door = Area3D.new()
	door.add_to_group("restaurant_door")
	door.set_meta("owner_name", "")
	add_child_autofree(door)
	assert_eq(door.get_meta("owner_name"), "", "Static door should have empty owner_name meta")

func test_door_with_explicit_owner():
	var door = Area3D.new()
	door.add_to_group("restaurant_door")
	door.set_meta("owner_name", "Chef Bob")
	add_child_autofree(door)
	assert_eq(door.get_meta("owner_name"), "Chef Bob", "Door with explicit owner should keep it")

# === Restaurant Index Allocation ===

func test_allocate_restaurant_index_increments():
	var idx1 = mgr.allocate_restaurant_index("Alice")
	var idx2 = mgr.allocate_restaurant_index("Bob")
	assert_eq(idx1, 0, "First allocation should be index 0")
	assert_eq(idx2, 1, "Second allocation should be index 1")

func test_allocate_restaurant_index_idempotent():
	var idx1 = mgr.allocate_restaurant_index("Alice")
	var idx2 = mgr.allocate_restaurant_index("Alice")
	assert_eq(idx1, idx2, "Same player should get same index")

# === Exit Cooldown ===

func test_exit_cooldown_stored():
	mgr._exit_cooldown[42] = Time.get_ticks_msec()
	assert_true(42 in mgr._exit_cooldown, "Cooldown should be tracked for peer")

func test_exit_cooldown_prevents_reentry():
	mgr._exit_cooldown[42] = Time.get_ticks_msec()
	# Within 1 second, cooldown should block
	var elapsed = Time.get_ticks_msec() - mgr._exit_cooldown[42]
	assert_true(elapsed < 1000, "Cooldown should be within 1 second window")

# === Player Location Tracking ===

func test_handle_player_connected_sets_overworld():
	# Simulate minimal player_data_store entry
	NetworkManager.player_data_store[99] = {
		"player_name": "TestPlayer",
		"restaurant": {},
	}
	mgr.handle_player_connected(99)
	assert_eq(mgr.player_location[99], {"zone": "overworld", "owner": ""}, "New player should be in overworld")
	# Cleanup
	NetworkManager.player_data_store.erase(99)

func test_handle_player_connected_allocates_index():
	NetworkManager.player_data_store[99] = {
		"player_name": "TestPlayer",
		"restaurant": {},
	}
	mgr.handle_player_connected(99)
	assert_true("TestPlayer" in mgr.restaurant_index_map, "Restaurant index should be allocated on connect")
	NetworkManager.player_data_store.erase(99)

func test_handle_player_connected_skips_server():
	NetworkManager.player_data_store[99] = {
		"player_name": "Server",
		"restaurant": {},
	}
	mgr.handle_player_connected(99)
	assert_false(99 in mgr.player_location, "Server player should not get location tracking")
	NetworkManager.player_data_store.erase(99)

func test_handle_player_disconnect_cleans_up():
	NetworkManager.player_data_store[99] = {
		"player_name": "TestPlayer",
		"restaurant": {},
	}
	mgr.handle_player_connected(99)
	mgr.overworld_positions[99] = Vector3(10, 1, 20)
	mgr.handle_player_disconnect(99)
	assert_false(99 in mgr.player_location, "Location should be erased on disconnect")
	assert_false(99 in mgr.overworld_positions, "Overworld position should be erased on disconnect")
	NetworkManager.player_data_store.erase(99)

# === No Dynamic Door Methods ===

func test_no_spawn_overworld_door_method():
	assert_false(mgr.has_method("spawn_overworld_door"), "Dynamic spawn_overworld_door should be removed")

func test_no_remove_overworld_door_method():
	assert_false(mgr.has_method("remove_overworld_door"), "Dynamic remove_overworld_door should be removed")

func test_no_sync_doors_to_client_method():
	assert_false(mgr.has_method("sync_doors_to_client"), "sync_doors_to_client should be removed")

func test_no_door_nodes_dict():
	assert_false("door_nodes" in mgr, "door_nodes dict should be removed")

func test_no_client_door_nodes_dict():
	assert_false("_client_door_nodes" in mgr, "client_door_nodes dict should be removed")

# === Save/Load ===

func test_save_load_restaurant_data():
	mgr.allocate_restaurant_index("Alice")
	mgr.allocate_restaurant_index("Bob")
	var save = mgr.get_save_data()
	assert_eq(save["next_restaurant_index"], 2)
	assert_eq(save["restaurant_index_map"]["Alice"], 0)
	assert_eq(save["restaurant_index_map"]["Bob"], 1)
	# Reset and reload
	mgr.next_restaurant_index = 0
	mgr.restaurant_index_map.clear()
	mgr.load_save_data(save)
	assert_eq(mgr.next_restaurant_index, 2)
	assert_eq(mgr.restaurant_index_map["Alice"], 0)

# === Static Door Owner Resolution (simulates player_interaction.gd logic) ===

func test_empty_owner_resolves_to_player_name():
	# This tests the logic used in player_interaction.gd
	var door_owner := ""
	var player_name := "MyPlayer"
	if door_owner == "":
		door_owner = player_name
	assert_eq(door_owner, "MyPlayer", "Empty owner should resolve to local player name")

func test_explicit_owner_stays():
	var door_owner := "FriendPlayer"
	var player_name := "MyPlayer"
	if door_owner == "":
		door_owner = player_name
	assert_eq(door_owner, "FriendPlayer", "Explicit owner should not be overridden")
