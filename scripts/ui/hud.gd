extends CanvasLayer

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

@onready var top_panel: PanelContainer = $TopPanel
@onready var season_label: Label = $TopPanel/TopBar/LeftInfo/SeasonLabel
@onready var weather_label: Label = $TopPanel/TopBar/LeftInfo/WeatherLabel
@onready var money_label: Label = $TopPanel/TopBar/RightInfo/MoneyLabel
@onready var location_label: Label = $TopPanel/TopBar/RightInfo/LocationLabel
@onready var grass_indicator: ColorRect = $GrassIndicator
@onready var grass_hint_label: Label = $GrassHintLabel
@onready var battle_transition: ColorRect = $BattleTransition

var buff_label: Label = null
var trainer_prompt_label: Label = null
var _trainer_prompt_timer: float = 0.0

func _ready() -> void:
	UITheme.init()

	# Style the top panel with semi-transparent parchment background
	var panel_bg := Color(UITokens.PAPER_TAN.r, UITokens.PAPER_TAN.g, UITokens.PAPER_TAN.b, 0.85)
	var panel_style := UITheme.make_panel_style(panel_bg, UITokens.STAMP_BROWN, UITokens.CORNER_RADIUS_SM, 1)
	panel_style.content_margin_left = 10
	panel_style.content_margin_top = 6
	panel_style.content_margin_right = 10
	panel_style.content_margin_bottom = 6
	top_panel.add_theme_stylebox_override("panel", panel_style)

	# Left info: date line (body size, primary ink)
	UITheme.style_body(season_label)
	_add_text_shadow(season_label)
	# Weather line (caption, gold)
	UITheme.style_caption(weather_label)
	weather_label.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
	_add_text_shadow(weather_label)
	# Right info: money (section heading, gold — large and prominent)
	UITheme.style_section(money_label)
	money_label.add_theme_color_override("font_color", UITokens.STAMP_GOLD)
	_add_text_shadow(money_label)
	# Location (caption, muted)
	UITheme.style_caption(location_label)
	location_label.add_theme_color_override("font_color", UITokens.INK_MEDIUM)
	_add_text_shadow(location_label)

	UITheme.style_small(grass_hint_label)
	var legend = get_node_or_null("WildZoneLegend")
	if legend and legend is Label:
		UITheme.style_small(legend)

	grass_indicator.color = UITokens.SCRIM
	battle_transition.color = UITokens.INK_DARK

	# Buff indicator (below top bar, left side)
	buff_label = Label.new()
	buff_label.text = ""
	UITheme.style_small(buff_label)
	buff_label.add_theme_color_override("font_color", UITokens.STAMP_GREEN)
	buff_label.anchor_left = 0.0
	buff_label.anchor_right = 0.5
	buff_label.anchor_top = 0.0
	buff_label.anchor_bottom = 0.0
	buff_label.offset_left = 12.0
	buff_label.offset_top = 68.0
	buff_label.offset_bottom = 88.0
	add_child(buff_label)

	# Trainer interaction prompt
	trainer_prompt_label = Label.new()
	trainer_prompt_label.text = ""
	trainer_prompt_label.visible = false
	UITheme.style_toast(trainer_prompt_label)
	trainer_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trainer_prompt_label.anchor_left = 0.25
	trainer_prompt_label.anchor_right = 0.75
	trainer_prompt_label.anchor_top = 0.82
	trainer_prompt_label.anchor_bottom = 0.88
	add_child(trainer_prompt_label)

func _add_text_shadow(label: Label) -> void:
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.3))

func _process(delta: float) -> void:
	# Auto-hide stale trainer prompt
	if _trainer_prompt_timer > 0.0:
		_trainer_prompt_timer -= delta
		if _trainer_prompt_timer <= 0.0:
			hide_trainer_prompt()
	var season_mgr = get_node_or_null("/root/Main/GameWorld/SeasonManager")
	if season_mgr:
		season_label.text = "%s  Year %d  Day %d" % [season_mgr.get_month_name(), season_mgr.current_year, season_mgr.day_in_month]
		weather_label.text = "%s" % season_mgr.get_weather_name().capitalize()
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

func show_pickup_notification(item_name: String, amount: int) -> void:
	var pickup_label = Label.new()
	if amount > 1:
		pickup_label.text = "Picked up %s x%d" % [item_name, amount]
	else:
		pickup_label.text = "Picked up %s" % item_name
	UITheme.style_toast(pickup_label)
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
	UITheme.style_toast(toast)
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

func show_toast(message: String) -> void:
	var toast = Label.new()
	toast.text = message
	UITheme.style_toast(toast)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.anchor_left = 0.2
	toast.anchor_right = 0.8
	toast.anchor_top = 0.75
	toast.anchor_bottom = 0.8
	add_child(toast)
	var tween = create_tween()
	tween.tween_property(toast, "modulate:a", 0.0, 2.0).set_delay(1.0)
	tween.tween_callback(toast.queue_free)

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
