extends GutTest

# Tests for friend_tab.gd — specifically the "Visit Restaurant" button for online friends.

var tab: Control

func before_each():
	var script = load("res://scripts/ui/tabs/friend_tab.gd")
	tab = Control.new()
	tab.set_script(script)
	add_child_autofree(tab)

func after_each():
	tab = null

# === Visit Button Presence ===

func test_visit_button_shown_for_online_friend():
	PlayerData.friends = [{"player_name": "Alice", "player_id": "abc123", "online": true}]
	tab._refresh()
	var visit_btn = _find_button_with_text(tab.content_list, "Visit")
	assert_not_null(visit_btn, "Visit button should appear for online friend")

func test_visit_button_hidden_for_offline_friend():
	PlayerData.friends = [{"player_name": "Bob", "player_id": "def456", "online": false}]
	tab._refresh()
	var visit_btn = _find_button_with_text(tab.content_list, "Visit")
	assert_null(visit_btn, "Visit button should NOT appear for offline friend")

func test_visit_button_uses_primary_style():
	PlayerData.friends = [{"player_name": "Alice", "player_id": "abc123", "online": true}]
	tab._refresh()
	var visit_btn = _find_button_with_text(tab.content_list, "Visit")
	assert_not_null(visit_btn, "Visit button should exist")

func test_remove_button_still_present():
	PlayerData.friends = [{"player_name": "Alice", "player_id": "abc123", "online": true}]
	tab._refresh()
	var remove_btn = _find_button_with_text(tab.content_list, "Remove")
	assert_not_null(remove_btn, "Remove button should still be present")

func test_block_button_still_present():
	PlayerData.friends = [{"player_name": "Alice", "player_id": "abc123", "online": true}]
	tab._refresh()
	var block_btn = _find_button_with_text(tab.content_list, "Block")
	assert_not_null(block_btn, "Block button should still be present")

func test_multiple_friends_both_get_visit_buttons():
	PlayerData.friends = [
		{"player_name": "Alice", "player_id": "abc123", "online": true},
		{"player_name": "Bob", "player_id": "def456", "online": true},
	]
	tab._refresh()
	var visit_btns = _find_all_buttons_with_text(tab.content_list, "Visit")
	assert_eq(visit_btns.size(), 2, "Both online friends should have Visit buttons")

func test_mixed_online_offline_friends():
	PlayerData.friends = [
		{"player_name": "Alice", "player_id": "abc123", "online": true},
		{"player_name": "Bob", "player_id": "def456", "online": false},
		{"player_name": "Charlie", "player_id": "ghi789", "online": true},
	]
	tab._refresh()
	var visit_btns = _find_all_buttons_with_text(tab.content_list, "Visit")
	assert_eq(visit_btns.size(), 2, "Only online friends should have Visit buttons")

func test_empty_friends_list_no_visit_button():
	PlayerData.friends = []
	tab._refresh()
	var visit_btn = _find_button_with_text(tab.content_list, "Visit")
	assert_null(visit_btn, "No Visit button when no friends")

# === Helpers ===

func _find_button_with_text(root: Node, text: String) -> Button:
	for child in root.get_children():
		if child is HBoxContainer:
			for sub in child.get_children():
				if sub is Button and sub.text == text:
					return sub
	return null

func _find_all_buttons_with_text(root: Node, text: String) -> Array:
	var results: Array = []
	for child in root.get_children():
		if child is HBoxContainer:
			for sub in child.get_children():
				if sub is Button and sub.text == text:
					results.append(sub)
	return results
