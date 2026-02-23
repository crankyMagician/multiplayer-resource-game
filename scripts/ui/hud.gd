extends CanvasLayer

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

@onready var top_panel: PanelContainer = $TopPanel
@onready var season_label: Label = $TopPanel/TopBar/SeasonLabel
@onready var weather_label: Label = $TopPanel/TopBar/WeatherLabel
@onready var money_label: Label = $TopPanel/TopBar/MoneyLabel
@onready var location_label: Label = $TopPanel/TopBar/LocationLabel
@onready var grass_indicator: ColorRect = $GrassIndicator
@onready var grass_hint_label: Label = $GrassHintLabel
@onready var battle_transition: ColorRect = $BattleTransition

var buff_label: Label = null
var trainer_prompt_label: Label = null
var _prompt_panel: PanelContainer = null
var _trainer_prompt_timer: float = 0.0
var now_playing_label: Label = null
var _now_playing_tween: Tween = null

func _ready() -> void:
	UITheme.init()

	# Style the top panel with semi-transparent parchment background
	var panel_bg := Color(UITokens.PAPER_TAN.r, UITokens.PAPER_TAN.g, UITokens.PAPER_TAN.b, 0.85)
	var panel_style := UITheme.make_panel_style(panel_bg, UITokens.STAMP_BROWN, UITokens.CORNER_RADIUS_SM, 1)
	panel_style.content_margin_left = 12
	panel_style.content_margin_top = 4
	panel_style.content_margin_right = 12
	panel_style.content_margin_bottom = 4
	top_panel.add_theme_stylebox_override("panel", panel_style)

	# All labels use caption size for the thin bar
	UITheme.style_caption(season_label)
	season_label.add_theme_color_override("font_color", UITokens.INK_DARK)

	UITheme.style_caption(weather_label)
	weather_label.add_theme_color_override("font_color", UITokens.STAMP_GOLD)

	UITheme.style_caption(location_label)
	location_label.add_theme_color_override("font_color", UITokens.INK_MEDIUM)

	# Money gets body size and gold color — slightly larger for prominence
	UITheme.style_body(money_label)
	money_label.add_theme_color_override("font_color", UITokens.STAMP_GOLD)

	# Add coin icon before money label
	var coin_tex = load("res://assets/ui/textures/icons/ui/ui_coin.png") as Texture2D
	if coin_tex:
		var coin_icon := TextureRect.new()
		coin_icon.texture = coin_tex
		var icon_size := UITheme.scaled(16)
		coin_icon.custom_minimum_size = Vector2(icon_size, icon_size)
		coin_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var top_bar = money_label.get_parent()
		if top_bar:
			var idx = money_label.get_index()
			top_bar.add_child(coin_icon)
			top_bar.move_child(coin_icon, idx)

	# "Now Playing" music label (right side of top bar)
	var top_bar = money_label.get_parent()
	if top_bar:
		var np_spacer := Control.new()
		np_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		np_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_bar.add_child(np_spacer)

		var np_icon := Label.new()
		np_icon.text = "♫"
		UITheme.style_caption(np_icon)
		np_icon.add_theme_color_override("font_color", UITokens.INK_LIGHT)
		np_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_bar.add_child(np_icon)

		now_playing_label = Label.new()
		now_playing_label.text = ""
		now_playing_label.clip_text = true
		now_playing_label.custom_minimum_size.x = 150
		UITheme.style_caption(now_playing_label)
		now_playing_label.add_theme_color_override("font_color", UITokens.INK_LIGHT)
		now_playing_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top_bar.add_child(now_playing_label)

	AudioManager.now_playing_changed.connect(_on_now_playing_changed)

	UITheme.style_small(grass_hint_label)
	var legend = get_node_or_null("WildZoneLegend")
	if legend and legend is Label:
		UITheme.style_small(legend)

	grass_indicator.color = UITokens.SCRIM

	# Apply diamond wipe shader to battle transition
	var transition_shader = load("res://shaders/battle_transition.gdshader") as Shader
	if transition_shader:
		var shader_mat = ShaderMaterial.new()
		shader_mat.shader = transition_shader
		shader_mat.set_shader_parameter("cover_color", Color(UITokens.INK_DARK.r, UITokens.INK_DARK.g, UITokens.INK_DARK.b, 1.0))
		shader_mat.set_shader_parameter("edge_color", UITokens.TRANSITION_EDGE)
		shader_mat.set_shader_parameter("progress", 0.0)
		battle_transition.material = shader_mat
	battle_transition.color = Color.WHITE  # Shader controls actual color

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
	buff_label.offset_top = 38.0
	buff_label.offset_bottom = 58.0
	add_child(buff_label)

	# Trainer interaction prompt (wrapped in panel)
	_prompt_panel = PanelContainer.new()
	_prompt_panel.visible = false
	_prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var prompt_style := UITheme.make_panel_style(
		Color(UITokens.PAPER_TAN.r, UITokens.PAPER_TAN.g, UITokens.PAPER_TAN.b, 0.85),
		UITokens.ACCENT_CHESTNUT,
		UITokens.CORNER_RADIUS,
		UITokens.BORDER_WIDTH
	)
	prompt_style.content_margin_left = 20
	prompt_style.content_margin_right = 20
	prompt_style.content_margin_top = 8
	prompt_style.content_margin_bottom = 8
	_prompt_panel.add_theme_stylebox_override("panel", prompt_style)
	_prompt_panel.anchor_left = 0.25
	_prompt_panel.anchor_right = 0.75
	_prompt_panel.anchor_top = 0.82
	_prompt_panel.anchor_bottom = 0.88
	_prompt_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	trainer_prompt_label = Label.new()
	trainer_prompt_label.text = ""
	UITheme.style_toast(trainer_prompt_label)
	trainer_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trainer_prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_panel.add_child(trainer_prompt_label)
	add_child(_prompt_panel)

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
		if buff_text != "":
			buff_label.add_theme_color_override("font_color", UITokens.STAMP_GREEN)
	# Update location display
	if location_label:
		if PlayerData.current_zone == "restaurant":
			location_label.text = PlayerData.current_restaurant_owner + "'s Restaurant"
		else:
			location_label.text = "Overworld"

func _make_toast_panel(text: String, font_color: Color = Color.TRANSPARENT) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := UITheme.make_panel_style(
		Color(UITokens.PAPER_TAN.r, UITokens.PAPER_TAN.g, UITokens.PAPER_TAN.b, 0.85),
		UITokens.ACCENT_CHESTNUT,
		UITokens.CORNER_RADIUS,
		UITokens.BORDER_WIDTH
	)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var label := Label.new()
	label.text = text
	UITheme.style_toast(label)
	if font_color.a > 0:
		label.add_theme_color_override("font_color", font_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel

func show_pickup_notification(item_name: String, amount: int) -> void:
	AudioManager.play_sfx("item_pickup")
	var text: String
	if amount > 1:
		text = "Picked up %s x%d" % [item_name, amount]
	else:
		text = "Picked up %s" % item_name
	var panel := _make_toast_panel(text)
	panel.anchor_left = 0.0
	panel.anchor_right = 0.4
	panel.anchor_top = 0.7
	panel.anchor_bottom = 0.75
	panel.offset_left = -100.0
	panel.modulate.a = 0.0
	add_child(panel)
	var tween = create_tween()
	# Slide in from left + fade in
	tween.tween_property(panel, "offset_left", 12.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
	# Hold
	tween.tween_interval(1.5)
	# Slide out right + fade out
	tween.tween_property(panel, "offset_left", 200.0, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(panel.queue_free)

func show_discovery_toast(display_name: String) -> void:
	AudioManager.play_sfx("quest_progress")
	var panel := _make_toast_panel("Discovered: %s" % display_name, UITokens.ACCENT_HONEY)
	panel.anchor_left = 0.25
	panel.anchor_right = 0.75
	panel.anchor_top = 0.65
	panel.anchor_bottom = 0.7
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.8, 0.8)
	panel.pivot_offset = panel.size / 2.0
	add_child(panel)
	var tween = create_tween()
	# Scale pop + fade in
	tween.tween_property(panel, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(panel, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
	# Brief golden shimmer
	tween.tween_property(panel, "modulate", UITokens.SHIMMER_GOLD, 0.15)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.15)
	# Hold
	tween.tween_interval(1.5)
	# Fade out
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)

func show_trainer_prompt(trainer_name: String) -> void:
	if trainer_prompt_label:
		trainer_prompt_label.text = "Press E to challenge %s!" % trainer_name
	if _prompt_panel:
		_prompt_panel.visible = true
	_trainer_prompt_timer = 6.0

func show_interaction_prompt(text: String, persistent: bool = false) -> void:
	if trainer_prompt_label:
		trainer_prompt_label.text = text
	if _prompt_panel:
		_prompt_panel.visible = true
	if not persistent:
		_trainer_prompt_timer = 6.0

func hide_trainer_prompt() -> void:
	if _prompt_panel:
		_prompt_panel.visible = false
	_trainer_prompt_timer = 0.0

func show_toast(message: String) -> void:
	var panel := _make_toast_panel(message)
	panel.anchor_left = 0.2
	panel.anchor_right = 0.8
	panel.anchor_top = 0.75
	panel.anchor_bottom = 0.8
	panel.modulate.a = 0.0
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(0.9, 0.9)
	add_child(panel)
	var tween = create_tween()
	# Pop in
	tween.tween_property(panel, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# Hold
	tween.tween_interval(1.5)
	# Fade out
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)

func show_new_fish_toast(fish_name: String) -> void:
	var panel := _make_toast_panel("New: %s!" % fish_name, UITokens.ACCENT_HONEY)
	panel.anchor_left = 0.3
	panel.anchor_right = 0.7
	panel.anchor_top = 0.6
	panel.anchor_bottom = 0.65
	panel.modulate.a = 0.0
	add_child(panel)
	var tween := create_tween()
	# Fade in
	tween.tween_property(panel, "modulate:a", 1.0, 0.3).set_ease(Tween.EASE_OUT)
	# Hold
	tween.tween_interval(2.0)
	# Fade out
	tween.tween_property(panel, "modulate:a", 0.0, 0.5)
	tween.tween_callback(panel.queue_free)


func show_grass_indicator(visible_state: bool) -> void:
	grass_indicator.visible = visible_state
	grass_hint_label.visible = visible_state

func play_screen_wipe() -> void:
	battle_transition.visible = true
	var shader_mat = battle_transition.material as ShaderMaterial
	if shader_mat:
		shader_mat.set_shader_parameter("progress", 0.0)
		var tween = create_tween()
		tween.tween_method(func(val: float): shader_mat.set_shader_parameter("progress", val), 0.0, 1.0, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		await tween.finished
	else:
		battle_transition.color.a = 0.0
		var tween = create_tween()
		tween.tween_property(battle_transition, "color:a", 1.0, 0.3)
		await tween.finished

func clear_screen_wipe() -> void:
	if not battle_transition.visible:
		return
	var shader_mat = battle_transition.material as ShaderMaterial
	if shader_mat:
		var tween = create_tween()
		tween.tween_method(func(val: float): shader_mat.set_shader_parameter("progress", val), 1.0, 0.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		await tween.finished
	else:
		var tween = create_tween()
		tween.tween_property(battle_transition, "color:a", 0.0, 0.3)
		await tween.finished
	battle_transition.visible = false

# Legacy aliases for existing callers
func play_battle_transition() -> void:
	await play_screen_wipe()

func clear_battle_transition() -> void:
	await clear_screen_wipe()

func _on_now_playing_changed(track_name: String) -> void:
	if not now_playing_label:
		return
	now_playing_label.text = track_name
	now_playing_label.modulate.a = 0.0
	if _now_playing_tween and _now_playing_tween.is_valid():
		_now_playing_tween.kill()
	_now_playing_tween = create_tween()
	_now_playing_tween.tween_property(now_playing_label, "modulate:a", 1.0, 0.5)
