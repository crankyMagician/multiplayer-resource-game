extends CanvasLayer

@onready var season_label: Label = $TopBar/SeasonLabel
@onready var day_label: Label = $TopBar/DayLabel
@onready var tool_label: Label = $ToolBar/ToolLabel
@onready var water_label: Label = $ToolBar/WaterLabel
@onready var grass_indicator: ColorRect = $GrassIndicator
@onready var grass_hint_label: Label = $GrassHintLabel
@onready var battle_transition: ColorRect = $BattleTransition

var money_label: Label = null
var buff_label: Label = null
var location_label: Label = null
var trainer_prompt_label: Label = null
var _trainer_prompt_timer: float = 0.0

func _ready() -> void:
	PlayerData.tool_changed.connect(_on_tool_changed)
	# Create money label dynamically
	money_label = Label.new()
	money_label.text = "$0"
	money_label.add_theme_font_size_override("font_size", 16)
	var top_bar = get_node_or_null("TopBar")
	if top_bar:
		top_bar.add_child(money_label)
	# Create buff indicator label
	buff_label = Label.new()
	buff_label.text = ""
	buff_label.add_theme_font_size_override("font_size", 14)
	buff_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	if top_bar:
		top_bar.add_child(buff_label)
	# Create location indicator label
	location_label = Label.new()
	location_label.text = "Overworld"
	location_label.add_theme_font_size_override("font_size", 14)
	location_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	if top_bar:
		top_bar.add_child(location_label)
	# Create trainer interaction prompt
	trainer_prompt_label = Label.new()
	trainer_prompt_label.text = ""
	trainer_prompt_label.visible = false
	trainer_prompt_label.add_theme_font_size_override("font_size", 20)
	trainer_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	trainer_prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	trainer_prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	trainer_prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	trainer_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trainer_prompt_label.anchor_left = 0.25
	trainer_prompt_label.anchor_right = 0.75
	trainer_prompt_label.anchor_top = 0.82
	trainer_prompt_label.anchor_bottom = 0.88
	add_child(trainer_prompt_label)

func _process(delta: float) -> void:
	# Auto-hide stale trainer prompt
	if _trainer_prompt_timer > 0.0:
		_trainer_prompt_timer -= delta
		if _trainer_prompt_timer <= 0.0:
			hide_trainer_prompt()
	water_label.text = "Water: %d/%d" % [PlayerData.watering_can_current, PlayerData.get_watering_can_capacity()]
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	if season_mgr:
		season_label.text = "Year %d, %s %d" % [season_mgr.current_year, season_mgr.get_month_name(), season_mgr.day_in_month]
		day_label.text = "%s" % season_mgr.get_weather_name().capitalize()
	if money_label:
		money_label.text = "$%d" % PlayerData.money
	# Update buff display
	if buff_label:
		var buff_text = ""
		var now = Time.get_unix_time_from_system()
		for buff in PlayerData.active_buffs:
			var remaining = float(buff.get("expires_at", 0)) - now
			if remaining > 0:
				var btype = buff.get("buff_type", "")
				var bval = buff.get("buff_value", 0.0)
				var mins = int(remaining / 60.0)
				var secs = int(remaining) % 60
				match btype:
					"speed_boost":
						buff_text += "SPD x%.1f %d:%02d  " % [bval, mins, secs]
					"xp_multiplier":
						buff_text += "XP x%.1f %d:%02d  " % [bval, mins, secs]
					"encounter_rate":
						buff_text += "ENC x%.1f %d:%02d  " % [bval, mins, secs]
		buff_label.text = buff_text
	# Update location display
	if location_label:
		if PlayerData.current_zone == "restaurant":
			location_label.text = PlayerData.current_restaurant_owner + "'s Restaurant"
		else:
			location_label.text = "Overworld"

func _on_tool_changed(tool_slot: String) -> void:
	if tool_slot == "" or tool_slot == "seeds":
		tool_label.text = "Tool: %s" % ("Hands" if tool_slot == "" else "Seeds")
	else:
		var display = PlayerData.get_tool_display_name(tool_slot)
		tool_label.text = "Tool: %s" % display

func show_pickup_notification(item_name: String, amount: int) -> void:
	var pickup_label = Label.new()
	if amount > 1:
		pickup_label.text = "Picked up %s x%d" % [item_name, amount]
	else:
		pickup_label.text = "Picked up %s" % item_name
	pickup_label.add_theme_font_size_override("font_size", 18)
	pickup_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	pickup_label.add_theme_constant_override("shadow_offset_x", 1)
	pickup_label.add_theme_constant_override("shadow_offset_y", 1)
	pickup_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	pickup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pickup_label.anchor_left = 0.3
	pickup_label.anchor_right = 0.7
	pickup_label.anchor_top = 0.7
	pickup_label.anchor_bottom = 0.75
	add_child(pickup_label)
	var tween = create_tween()
	tween.tween_property(pickup_label, "modulate:a", 0.0, 2.0).set_delay(0.5)
	tween.tween_callback(pickup_label.queue_free)

func show_discovery_toast(display_name: String) -> void:
	var toast = Label.new()
	toast.text = "Discovered: %s" % display_name
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	toast.add_theme_constant_override("shadow_offset_x", 1)
	toast.add_theme_constant_override("shadow_offset_y", 1)
	toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.anchor_left = 0.25
	toast.anchor_right = 0.75
	toast.anchor_top = 0.65
	toast.anchor_bottom = 0.7
	add_child(toast)
	var tween = create_tween()
	tween.tween_property(toast, "modulate:a", 0.0, 2.0).set_delay(1.0)
	tween.tween_callback(toast.queue_free)

func show_trainer_prompt(trainer_name: String) -> void:
	if trainer_prompt_label:
		trainer_prompt_label.text = "Press E to challenge %s!" % trainer_name
		trainer_prompt_label.visible = true
		_trainer_prompt_timer = 6.0

func hide_trainer_prompt() -> void:
	if trainer_prompt_label:
		trainer_prompt_label.visible = false
		_trainer_prompt_timer = 0.0

func show_grass_indicator(visible_state: bool) -> void:
	grass_indicator.visible = visible_state
	grass_hint_label.visible = visible_state

func play_battle_transition() -> void:
	battle_transition.visible = true
	battle_transition.color.a = 0.0
	var tween = create_tween()
	tween.tween_property(battle_transition, "color:a", 1.0, 0.3)
	await tween.finished

func clear_battle_transition() -> void:
	if not battle_transition.visible:
		return
	var tween = create_tween()
	tween.tween_property(battle_transition, "color:a", 0.0, 0.3)
	await tween.finished
	battle_transition.visible = false
