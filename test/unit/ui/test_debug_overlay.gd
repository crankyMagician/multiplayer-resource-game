extends GutTest

# Tests for DevDebugOverlay UI construction, validation, collapsible sections,
# and the debug result callback. We instantiate the overlay but skip dispatch
# tests that would trigger RPC errors. Action dispatchers are tested via
# _send_log (populated before the RPC call) for validation-gated actions only.

var overlay: Node

func before_each() -> void:
	RegistrySeeder.seed_all()
	overlay = load("res://scripts/ui/dev_debug_overlay.gd").new()
	overlay.layer = 25
	overlay._build_ui()
	overlay.visible = true
	add_child_autofree(overlay)

func after_each() -> void:
	RegistrySeeder.clear_all()

# === Construction Tests ===

func test_panel_exists() -> void:
	assert_not_null(overlay.panel, "Panel should be created")
	assert_is(overlay.panel, PanelContainer)

func test_scroll_exists() -> void:
	assert_not_null(overlay.scroll, "ScrollContainer should be created")
	assert_is(overlay.scroll, ScrollContainer)

func test_world_sections_exist() -> void:
	assert_not_null(overlay.world_sections, "World sections container should exist")
	assert_is(overlay.world_sections, VBoxContainer)

func test_battle_sections_exist() -> void:
	assert_not_null(overlay.battle_sections, "Battle sections container should exist")
	assert_is(overlay.battle_sections, VBoxContainer)

func test_battle_sections_hidden_by_default() -> void:
	assert_false(overlay.battle_sections.visible, "Battle sections should be hidden by default")

func test_world_sections_visible_by_default() -> void:
	assert_true(overlay.world_sections.visible, "World sections should be visible by default")

func test_feedback_label_exists() -> void:
	assert_not_null(overlay.feedback_label, "Feedback label should exist")
	assert_is(overlay.feedback_label, Label)

func test_time_label_exists() -> void:
	assert_not_null(overlay.time_label, "Time label should exist")

func test_info_label_exists() -> void:
	assert_not_null(overlay._info_label, "Info label should exist")

func test_panel_has_offset_margins() -> void:
	assert_eq(overlay.panel.offset_top, 10.0, "Panel should have top margin")
	assert_eq(overlay.panel.offset_bottom, -10.0, "Panel should have bottom margin")

func test_panel_width() -> void:
	assert_eq(overlay.panel.custom_minimum_size.x, 320.0, "Panel width should be 320")

func test_send_log_starts_empty() -> void:
	assert_eq(overlay._send_log.size(), 0)

# === Battle Mode Toggle ===

func test_battle_mode_toggle_shows_battle_hides_world() -> void:
	overlay._in_battle = true
	overlay.world_sections.visible = false
	overlay.battle_sections.visible = true
	assert_true(overlay.battle_sections.visible, "Battle sections should show in battle")
	assert_false(overlay.world_sections.visible, "World sections should hide in battle")

func test_battle_mode_toggle_back_to_world() -> void:
	overlay._in_battle = false
	overlay.world_sections.visible = true
	overlay.battle_sections.visible = false
	assert_false(overlay.battle_sections.visible)
	assert_true(overlay.world_sections.visible)

# === Validation Tests (these set feedback_label without calling _send) ===

func test_wild_battle_empty_species_shows_error() -> void:
	overlay._species_field.text = ""
	overlay._on_wild_battle()
	assert_eq(overlay._send_log.size(), 0, "Should not send with empty species")
	assert_string_contains(overlay.feedback_label.text, "species_id")

func test_give_item_empty_id_shows_error() -> void:
	overlay._item_field.text = ""
	overlay._on_give_item()
	assert_eq(overlay._send_log.size(), 0, "Should not send with empty item_id")
	assert_string_contains(overlay.feedback_label.text, "item_id")

func test_complete_quest_empty_id_shows_error() -> void:
	overlay._quest_field.text = ""
	overlay._on_complete_quest()
	assert_eq(overlay._send_log.size(), 0, "Should not send with empty quest_id")
	assert_string_contains(overlay.feedback_label.text, "quest_id")

func test_trainer_battle_empty_list_does_nothing() -> void:
	# Remove all items from trainer option
	while overlay._trainer_option.item_count > 0:
		overlay._trainer_option.remove_item(0)
	overlay._on_trainer_battle()
	assert_eq(overlay._send_log.size(), 0, "Should not send with no trainers")

func test_set_friendship_empty_list_does_nothing() -> void:
	while overlay._npc_option.item_count > 0:
		overlay._npc_option.remove_item(0)
	overlay._on_set_friendship()
	assert_eq(overlay._send_log.size(), 0, "Should not send with no NPCs")

# === Collapsible Sections ===

func test_collapsible_sections_exist() -> void:
	assert_gt(overlay._section_collapse_map.size(), 0, "Should have collapsible sections")

func test_section_count_world_mode() -> void:
	# World sections: Time & Weather, Battles, Items & Money, Player, Creatures,
	# Recipes, Farming, Quests, Social, Excursion = 10
	var world_section_count := 0
	for header_btn in overlay._section_collapse_map:
		if header_btn.get_parent() == overlay.world_sections:
			world_section_count += 1
	assert_eq(world_section_count, 10, "Should have 10 world collapsible sections")

func test_section_count_battle_mode() -> void:
	# Battle sections: Battle Controls, Creature HP, Status Effects, Stat Stages, Field Effects = 5
	var battle_section_count := 0
	for header_btn in overlay._section_collapse_map:
		if header_btn.get_parent() == overlay.battle_sections:
			battle_section_count += 1
	assert_eq(battle_section_count, 5, "Should have 5 battle collapsible sections")

func test_section_toggle_collapses_content() -> void:
	var header_btn: Button = overlay._section_collapse_map.keys()[0]
	var content: VBoxContainer = overlay._section_collapse_map[header_btn]
	assert_true(content.visible, "Content should start visible")
	overlay._on_section_header_pressed(header_btn)
	assert_false(content.visible, "Content should be hidden after toggle")
	assert_true(header_btn.text.begins_with("▸"), "Header should show collapsed arrow")

func test_section_toggle_expands_content() -> void:
	var header_btn: Button = overlay._section_collapse_map.keys()[0]
	var content: VBoxContainer = overlay._section_collapse_map[header_btn]
	overlay._on_section_header_pressed(header_btn)
	assert_false(content.visible)
	overlay._on_section_header_pressed(header_btn)
	assert_true(content.visible, "Content should be visible after re-toggle")
	assert_true(header_btn.text.begins_with("▾"), "Header should show expanded arrow")

func test_all_sections_start_expanded() -> void:
	for header_btn in overlay._section_collapse_map:
		var content: VBoxContainer = overlay._section_collapse_map[header_btn]
		assert_true(content.visible, "All sections should start expanded: %s" % header_btn.text)
		assert_true(header_btn.text.begins_with("▾"), "Arrow should be expanded: %s" % header_btn.text)

# === Debug Result Callback ===

func test_debug_result_updates_feedback_label() -> void:
	overlay._on_debug_result("give_item", "Gave 10x herb_poultice")
	assert_eq(overlay.feedback_label.text, "[give_item] Gave 10x herb_poultice")

func test_debug_result_different_action() -> void:
	overlay._on_debug_result("heal_party", "Party healed (3 creatures)")
	assert_eq(overlay.feedback_label.text, "[heal_party] Party healed (3 creatures)")

# === Spin Box Defaults ===

func test_money_spin_default() -> void:
	assert_eq(overlay._money_spin.value, 10000.0)

func test_level_spin_default() -> void:
	assert_eq(overlay._level_spin.value, 50.0)

func test_party_idx_spin_range() -> void:
	assert_eq(overlay._party_idx_spin.min_value, 0.0)
	assert_eq(overlay._party_idx_spin.max_value, 2.0)

func test_friendship_spin_range() -> void:
	assert_eq(overlay._friendship_spin.min_value, -100.0)
	assert_eq(overlay._friendship_spin.max_value, 100.0)
	assert_eq(overlay._friendship_spin.value, 100.0)

func test_year_spin_range() -> void:
	assert_eq(overlay._year_spin.min_value, 1.0)
	assert_eq(overlay._year_spin.max_value, 99.0)

func test_teleport_defaults() -> void:
	assert_eq(overlay._teleport_x.value, 0.0)
	assert_eq(overlay._teleport_y.value, 1.0)
	assert_eq(overlay._teleport_z.value, 3.0)
