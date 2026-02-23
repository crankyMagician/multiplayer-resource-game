extends CanvasLayer

# Client-side fishing minigame UI. Layer 8.
# Themed with UITheme/UITokens for visual coherence with the rest of the game.

const UITokens = preload("res://scripts/ui/ui_tokens.gd")

var _active: bool = false
var _casting: bool = false
var _hook_window: bool = false
var _showing_result: bool = false
var _seed_val: int = 0
var _difficulty: int = 1
var _movement_type: String = "smooth"
var _time_limit: float = 15.0
var _bar_size: float = 0.25
var _fish_name: String = ""
var _fish_id: String = ""

var _elapsed: float = 0.0
var _bar_pos: float = 0.5
var _bar_velocity: float = 0.0
var _catch_meter: float = 0.0
var _holding: bool = false
var _input_log: PackedFloat32Array = PackedFloat32Array()
var _finished: bool = false

# Fish state (Stardew-style frame stepping)
var _fish_pos: float = 0.5
var _fish_speed: float = 0.0
var _fish_target: float = 0.5
var _fish_bias: float = 0.0
var _fish_rng: int = 0
var _sdv_diff: float = 15.0

# Post-processing state
var _pp_shader_mat: ShaderMaterial = null
var _pp_rect: ColorRect = null
var _vignette_strength: float = 0.0
var _red_vignette: float = 0.0
var _white_flash: float = 0.0

# Hook window animation timer
var _hook_alert_timer: float = 0.0

# Meter pulse state
var _meter_pulse_time: float = 0.0

# Casting animation state
var _casting_anim_time: float = 0.0

# Difficulty preview state
var _difficulty_preview_timer: float = 0.0
var _difficulty_preview_active: bool = false
var _difficulty_card: Panel = null

# UI nodes
var _panel: Panel = null
var _bar_area: Control = null
var _fish_indicator: Panel = null
var _catch_bar: Panel = null
var _meter_bar: Panel = null
var _meter_bg: Panel = null
var _meter_ticks: Control = null
var _timer_label: Label = null
var _fish_label: Label = null
var _instruction_label: Label = null
var _casting_label: Label = null
var _hook_alert_label: Label = null
var _result_panel: Panel = null
var _result_label: Label = null
var _result_icon_container: HBoxContainer = null
var _result_stars_label: Label = null
var _result_perfect_label: Label = null
var _result_new_species_label: Label = null
var _result_dismiss_label: Label = null
var _quit_button: Button = null
var _bg: ColorRect = null
var _bar_bg: Panel = null
var _esc_label: Label = null
var _bar_top_y: float = 65.0  # Scaled in _build_ui

const BAR_WIDTH: int = 60
const BAR_HEIGHT: int = 400
const PANEL_WIDTH: int = 220
const PANEL_HEIGHT: int = 500

const MOVEMENT_HINTS: Dictionary = {
	"smooth": "Floating",
	"dart": "Darting",
	"sinker": "Deep",
	"mixed": "Tricky",
}


func _ready() -> void:
	layer = 8
	UITheme.init()
	_build_ui()
	_build_post_processing()
	visible = false


func _build_ui() -> void:
	# Semi-transparent background overlay
	_bg = ColorRect.new()
	_bg.name = "BG"
	_bg.color = UITokens.SCRIM_MENU
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Center panel (anchor-based centering)
	_panel = Panel.new()
	_panel.name = "FishingPanel"
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -PANEL_WIDTH / 2.0
	_panel.offset_right = PANEL_WIDTH / 2.0
	_panel.offset_top = -PANEL_HEIGHT / 2.0
	_panel.offset_bottom = PANEL_HEIGHT / 2.0
	var panel_bg_color := Color(UITokens.PAPER_CARD.r, UITokens.PAPER_CARD.g, UITokens.PAPER_CARD.b, 0.92)
	var style := UITheme.make_panel_style(panel_bg_color, UITokens.ACCENT_OCEAN, UITokens.CORNER_RADIUS_LG, UITokens.BORDER_WIDTH)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	# Scaled Y offsets for internal panel layout
	var fs: float = UITheme._font_scale
	var header_y: float = 8.0 * fs
	var timer_y: float = 32.0 * fs
	var bar_top_y: float = 65.0 * fs
	_bar_top_y = bar_top_y

	# Fish name label at top
	_fish_label = Label.new()
	_fish_label.name = "FishLabel"
	_fish_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fish_label.position = Vector2(0, header_y)
	_fish_label.size = Vector2(PANEL_WIDTH, 30.0 * fs)
	UITheme.style_emphasis(_fish_label)
	_panel.add_child(_fish_label)

	# Timer label
	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.position = Vector2(0, timer_y)
	_timer_label.size = Vector2(PANEL_WIDTH, 25.0 * fs)
	UITheme.style_caption(_timer_label)
	_panel.add_child(_timer_label)

	# Catch meter background (left side)
	_meter_bg = Panel.new()
	_meter_bg.name = "MeterBG"
	_meter_bg.position = Vector2(15, bar_top_y)
	_meter_bg.size = Vector2(20, BAR_HEIGHT)
	var meter_bg_style := StyleBoxFlat.new()
	meter_bg_style.bg_color = Color(UITokens.PAPER_EDGE.r, UITokens.PAPER_EDGE.g, UITokens.PAPER_EDGE.b, 0.8)
	meter_bg_style.set_corner_radius_all(4)
	_meter_bg.add_theme_stylebox_override("panel", meter_bg_style)
	_panel.add_child(_meter_bg)

	# Meter tick marks
	_meter_ticks = Control.new()
	_meter_ticks.name = "MeterTicks"
	_meter_ticks.position = Vector2(15, bar_top_y)
	_meter_ticks.size = Vector2(20, BAR_HEIGHT)
	_meter_ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(_meter_ticks)

	# Catch meter fill
	_meter_bar = Panel.new()
	_meter_bar.name = "MeterFill"
	_meter_bar.position = Vector2(15, bar_top_y + BAR_HEIGHT)
	_meter_bar.size = Vector2(20, 0)
	var meter_fill_style := StyleBoxFlat.new()
	meter_fill_style.bg_color = UITokens.ACCENT_BASIL
	meter_fill_style.set_corner_radius_all(4)
	_meter_bar.add_theme_stylebox_override("panel", meter_fill_style)
	_panel.add_child(_meter_bar)

	# Main bar area (the fishing column)
	_bar_area = Control.new()
	_bar_area.name = "BarArea"
	_bar_area.position = Vector2(55, bar_top_y)
	_bar_area.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_panel.add_child(_bar_area)

	# Bar area background
	_bar_bg = Panel.new()
	_bar_bg.name = "BarBG"
	_bar_bg.position = Vector2.ZERO
	_bar_bg.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	var bar_bg_style := StyleBoxFlat.new()
	bar_bg_style.bg_color = Color(UITokens.PAPER_EDGE.r, UITokens.PAPER_EDGE.g, UITokens.PAPER_EDGE.b, 0.6)
	bar_bg_style.set_corner_radius_all(UITokens.CORNER_RADIUS)
	bar_bg_style.set_border_width_all(1)
	bar_bg_style.border_color = Color(UITokens.ACCENT_CHESTNUT.r, UITokens.ACCENT_CHESTNUT.g, UITokens.ACCENT_CHESTNUT.b, 0.5)
	_bar_bg.add_theme_stylebox_override("panel", bar_bg_style)
	_bar_area.add_child(_bar_bg)

	# Catch bar (player-controlled)
	_catch_bar = Panel.new()
	_catch_bar.name = "CatchBar"
	_catch_bar.position = Vector2(0, 0)
	_catch_bar.size = Vector2(BAR_WIDTH, 50)
	var catch_bar_style := StyleBoxFlat.new()
	catch_bar_style.bg_color = Color(UITokens.ACCENT_BASIL.r, UITokens.ACCENT_BASIL.g, UITokens.ACCENT_BASIL.b, 0.55)
	catch_bar_style.set_corner_radius_all(6)
	catch_bar_style.set_border_width_all(2)
	catch_bar_style.border_color = UITokens.ACCENT_BASIL
	_catch_bar.add_theme_stylebox_override("panel", catch_bar_style)
	_bar_area.add_child(_catch_bar)

	# Fish indicator
	_fish_indicator = Panel.new()
	_fish_indicator.name = "FishIndicator"
	_fish_indicator.position = Vector2(4, 0)
	_fish_indicator.size = Vector2(BAR_WIDTH - 8, 16)
	var fish_style := StyleBoxFlat.new()
	fish_style.bg_color = UITokens.ACCENT_BERRY
	fish_style.set_corner_radius_all(4)
	fish_style.set_border_width_all(1)
	fish_style.border_color = UITokens.ACCENT_BERRY.lightened(0.3)
	_fish_indicator.add_theme_stylebox_override("panel", fish_style)
	_bar_area.add_child(_fish_indicator)

	# Instruction label (scaled offset from bottom)
	_instruction_label = Label.new()
	_instruction_label.name = "InstructionLabel"
	_instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction_label.position = Vector2(0, PANEL_HEIGHT - 55.0 * fs)
	_instruction_label.size = Vector2(PANEL_WIDTH, 25.0 * fs)
	UITheme.style_caption(_instruction_label)
	_instruction_label.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
	_panel.add_child(_instruction_label)

	# Esc hint (scaled offset from bottom)
	_esc_label = Label.new()
	_esc_label.name = "EscLabel"
	_esc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_esc_label.position = Vector2(0, PANEL_HEIGHT - 30.0 * fs)
	_esc_label.size = Vector2(PANEL_WIDTH, 20.0 * fs)
	_esc_label.text = "[Esc] Release line"
	UITheme.style_caption(_esc_label)
	_esc_label.add_theme_color_override("font_color", UITokens.INK_DISABLED)
	_esc_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	_panel.add_child(_esc_label)

	# Casting label (shown during wait phase — anchor-based centering)
	_casting_label = Label.new()
	_casting_label.name = "CastingLabel"
	_casting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_casting_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_casting_label.anchor_left = 0.25
	_casting_label.anchor_right = 0.75
	_casting_label.anchor_top = 0.4
	_casting_label.anchor_bottom = 0.6
	_casting_label.offset_left = 0
	_casting_label.offset_right = 0
	_casting_label.offset_top = 0
	_casting_label.offset_bottom = 0
	_casting_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_casting_label.text = "Casting..."
	UITheme.style_title(_casting_label)
	_casting_label.add_theme_color_override("font_color", UITokens.ACCENT_HONEY)
	_casting_label.visible = false
	add_child(_casting_label)

	# Hook alert label (anchor-based centering)
	_hook_alert_label = Label.new()
	_hook_alert_label.name = "HookAlertLabel"
	_hook_alert_label.text = "Bite!"
	_hook_alert_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hook_alert_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hook_alert_label.anchor_left = 0.2
	_hook_alert_label.anchor_right = 0.8
	_hook_alert_label.anchor_top = 0.35
	_hook_alert_label.anchor_bottom = 0.65
	_hook_alert_label.offset_left = 0
	_hook_alert_label.offset_right = 0
	_hook_alert_label.offset_top = 0
	_hook_alert_label.offset_bottom = 0
	UITheme.style_title(_hook_alert_label)
	_hook_alert_label.add_theme_font_size_override("font_size", UITheme.scaled(48))
	_hook_alert_label.add_theme_color_override("font_color", UITokens.ACCENT_TOMATO)
	_hook_alert_label.add_theme_color_override("font_outline_color", UITokens.PAPER_BASE)
	_hook_alert_label.add_theme_constant_override("outline_size", 6)
	_hook_alert_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	_hook_alert_label.add_theme_constant_override("shadow_offset_x", 2)
	_hook_alert_label.add_theme_constant_override("shadow_offset_y", 2)
	_hook_alert_label.visible = false
	add_child(_hook_alert_label)

	# Quit button (floating, bottom-center — anchor-based)
	_quit_button = Button.new()
	_quit_button.name = "QuitButton"
	_quit_button.text = "Reel In"
	_quit_button.anchor_left = 0.4
	_quit_button.anchor_right = 0.6
	_quit_button.anchor_top = 0.9
	_quit_button.anchor_bottom = 0.95
	_quit_button.offset_left = 0
	_quit_button.offset_right = 0
	_quit_button.offset_top = 0
	_quit_button.offset_bottom = 0
	UITheme.style_button(_quit_button, "danger")
	_quit_button.pressed.connect(_on_quit_pressed)
	_quit_button.visible = false
	add_child(_quit_button)

	# Result panel (shown after catch/fail — anchor-based centering)
	_result_panel = Panel.new()
	_result_panel.name = "ResultPanel"
	_result_panel.anchor_left = 0.5
	_result_panel.anchor_right = 0.5
	_result_panel.anchor_top = 0.5
	_result_panel.anchor_bottom = 0.5
	_result_panel.offset_left = -175
	_result_panel.offset_right = 175
	_result_panel.offset_top = -85
	_result_panel.offset_bottom = 85
	var result_style := UITheme.make_panel_style(UITokens.PAPER_BASE, UITokens.ACCENT_CHESTNUT, UITokens.CORNER_RADIUS_LG, UITokens.BORDER_WIDTH)
	_result_panel.add_theme_stylebox_override("panel", result_style)
	_result_panel.visible = false
	add_child(_result_panel)

	# Result icon + text container
	_result_icon_container = HBoxContainer.new()
	_result_icon_container.name = "ResultIconContainer"
	_result_icon_container.position = Vector2(14, 14)
	_result_icon_container.size = Vector2(322, 50)
	_result_icon_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_result_icon_container.add_theme_constant_override("separation", 8)
	_result_panel.add_child(_result_icon_container)

	_result_label = Label.new()
	_result_label.name = "ResultLabel"
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UITheme.style_body_text(_result_label)
	_result_icon_container.add_child(_result_label)

	# Star rating label
	_result_stars_label = Label.new()
	_result_stars_label.name = "StarsLabel"
	_result_stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_stars_label.position = Vector2(14, 70)
	_result_stars_label.size = Vector2(322, 25)
	UITheme.style_emphasis(_result_stars_label)
	_result_panel.add_child(_result_stars_label)

	# Perfect label
	_result_perfect_label = Label.new()
	_result_perfect_label.name = "PerfectLabel"
	_result_perfect_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_perfect_label.position = Vector2(14, 95)
	_result_perfect_label.size = Vector2(322, 25)
	UITheme.style_emphasis(_result_perfect_label)
	_result_perfect_label.add_theme_color_override("font_color", UITokens.ACCENT_BASIL)
	_result_perfect_label.visible = false
	_result_panel.add_child(_result_perfect_label)

	# New species label
	_result_new_species_label = Label.new()
	_result_new_species_label.name = "NewSpeciesLabel"
	_result_new_species_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_new_species_label.position = Vector2(14, 95)
	_result_new_species_label.size = Vector2(322, 25)
	_result_new_species_label.text = "NEW!"
	UITheme.style_badge(_result_new_species_label, "warning")
	_result_new_species_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_BODY))
	_result_new_species_label.visible = false
	_result_panel.add_child(_result_new_species_label)

	# Dismiss hint label (bottom of result panel)
	_result_dismiss_label = Label.new()
	_result_dismiss_label.name = "DismissLabel"
	_result_dismiss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_dismiss_label.position = Vector2(14, 140)
	_result_dismiss_label.size = Vector2(322, 20)
	_result_dismiss_label.text = "Press E to continue"
	UITheme.style_caption(_result_dismiss_label)
	_result_dismiss_label.add_theme_color_override("font_color", UITokens.INK_DISABLED)
	_result_dismiss_label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_TINY))
	_result_dismiss_label.visible = false
	_result_panel.add_child(_result_dismiss_label)

	# Difficulty preview card (shown briefly before minigame activates — anchor-based)
	_difficulty_card = Panel.new()
	_difficulty_card.name = "DifficultyCard"
	_difficulty_card.anchor_left = 0.5
	_difficulty_card.anchor_right = 0.5
	_difficulty_card.anchor_top = 0.5
	_difficulty_card.anchor_bottom = 0.5
	_difficulty_card.offset_left = -120
	_difficulty_card.offset_right = 120
	_difficulty_card.offset_top = -50
	_difficulty_card.offset_bottom = 50
	var diff_style := UITheme.make_panel_style(
		Color(UITokens.PAPER_CARD.r, UITokens.PAPER_CARD.g, UITokens.PAPER_CARD.b, 0.95),
		UITokens.ACCENT_OCEAN, UITokens.CORNER_RADIUS_LG, UITokens.BORDER_WIDTH)
	_difficulty_card.add_theme_stylebox_override("panel", diff_style)
	_difficulty_card.visible = false
	add_child(_difficulty_card)


func _build_post_processing() -> void:
	var pp_canvas := CanvasLayer.new()
	pp_canvas.name = "FishingPP"
	pp_canvas.layer = 9
	add_child(pp_canvas)

	_pp_rect = ColorRect.new()
	_pp_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pp_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pp_shader := Shader.new()
	pp_shader.code = """
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.0;
uniform float red_vignette : hint_range(0.0, 1.0) = 0.0;
uniform float white_flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_texture, uv).rgb;

	// Warm sepia vignette (used during hook window)
	float vig = 1.0 - smoothstep(0.3, 0.9, length(uv - vec2(0.5)) * 1.5);
	vec3 vig_tint = vec3(0.17, 0.12, 0.08);
	col = mix(col, col * vig + vig_tint * (1.0 - vig) * 0.3, vignette_strength);

	// Warm tomato vignette flash (fish lost)
	float red_vig = 1.0 - smoothstep(0.2, 0.8, length(uv - vec2(0.5)) * 1.3);
	col = mix(col, vec3(0.65, 0.28, 0.25), red_vignette * (1.0 - red_vig));

	// Warm cream flash (catch celebration)
	col = mix(col, vec3(1.0, 0.97, 0.94), white_flash);

	COLOR = vec4(col, 1.0);
}
"""
	_pp_shader_mat = ShaderMaterial.new()
	_pp_shader_mat.shader = pp_shader
	_pp_rect.material = _pp_shader_mat
	pp_canvas.add_child(_pp_rect)


func show_casting() -> void:
	visible = true
	_casting = true
	_active = false
	_hook_window = false
	_showing_result = false
	_finished = false
	_casting_anim_time = 0.0
	_panel.visible = false
	_casting_label.visible = true
	_casting_label.text = "Casting..."
	_casting_label.modulate.a = 0.0
	_hook_alert_label.visible = false
	_result_panel.visible = false
	_difficulty_card.visible = false
	_quit_button.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Casting label entrance tween (offset-based for anchor layout)
	_casting_label.offset_top = 0
	_casting_label.offset_bottom = 0
	var tween := create_tween()
	tween.tween_property(_casting_label, "modulate:a", 1.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(_casting_label, "offset_top", 0.0, 0.4)\
		.from(-20.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(_casting_label, "offset_bottom", 0.0, 0.4)\
		.from(-20.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func show_hook_alert() -> void:
	_casting = false
	_hook_window = true
	_active = false
	_finished = false
	_casting_label.visible = false
	_panel.visible = false
	_difficulty_card.visible = false
	_hook_alert_label.visible = true
	_hook_alert_label.modulate.a = 1.0
	_hook_alert_timer = 0.0
	_quit_button.visible = true
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Hook alert snap-in tween
	_hook_alert_label.scale = Vector2(1.5, 1.5)
	var tween := create_tween()
	tween.tween_property(_hook_alert_label, "scale", Vector2.ONE, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func start_minigame(seed_val: int, difficulty: int, movement_type: String,
		time_limit: float, bar_size: float, fish_name: String) -> void:
	_seed_val = seed_val
	_difficulty = difficulty
	_movement_type = movement_type
	_time_limit = time_limit
	_bar_size = bar_size
	_fish_name = fish_name

	_elapsed = 0.0
	_bar_pos = 0.5
	_bar_velocity = 0.0
	_catch_meter = FishingMinigame.INITIAL_CATCH_METER
	_holding = false
	_input_log = PackedFloat32Array()
	_finished = false
	_meter_pulse_time = 0.0

	# Initialize fish state (matches server replay)
	var fish_init: Dictionary = FishingMinigame.init_fish_state(seed_val, movement_type)
	_fish_pos = fish_init["pos"]
	_fish_speed = fish_init["speed"]
	_fish_target = fish_init["target"]
	_fish_bias = fish_init["bias"]
	_fish_rng = fish_init["rng"]
	_sdv_diff = FishingMinigame._sdv_difficulty(difficulty)

	_casting = false
	_hook_window = false
	_result_panel.visible = false
	_quit_button.visible = true

	_fish_label.text = ""  # Don't reveal fish species during minigame
	_instruction_label.text = _get_reel_hint()
	_esc_label.text = "[Esc] Release line"

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Show difficulty preview card first (no fish name — species is a surprise)
	_show_difficulty_preview(difficulty, movement_type)


func _show_difficulty_preview(difficulty: int, movement_type: String) -> void:
	_difficulty_preview_active = true
	_difficulty_preview_timer = 0.0
	_active = false
	_panel.visible = false
	_casting_label.visible = false
	_hook_alert_label.visible = false

	# Build card contents (no fish name — species revealed on catch)
	for child in _difficulty_card.get_children():
		child.queue_free()

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 4)
	_difficulty_card.add_child(vbox)

	var stars_text := ""
	for i in 5:
		if i < difficulty:
			stars_text += "\u2605"
		else:
			stars_text += "\u2606"
	var stars_label := Label.new()
	UITheme.style_emphasis(stars_label, stars_text)
	stars_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stars_label)

	var hint_text: String = MOVEMENT_HINTS.get(movement_type, "Unknown")
	var hint_label := Label.new()
	UITheme.style_caption(hint_label, hint_text)
	hint_label.add_theme_color_override("font_color", UITokens.INK_SECONDARY)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint_label)

	_difficulty_card.visible = true
	_difficulty_card.modulate.a = 0.0

	# Fade in
	var tween := create_tween()
	tween.tween_property(_difficulty_card, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _activate_minigame() -> void:
	_difficulty_preview_active = false
	_difficulty_card.visible = false
	_active = true
	visible = true

	# Panel entrance tween (slide from right, offset-based)
	_panel.visible = true
	_panel.modulate.a = 0.0
	var target_left: float = -PANEL_WIDTH / 2.0
	var target_right: float = PANEL_WIDTH / 2.0
	_panel.offset_left = target_left + 40.0
	_panel.offset_right = target_right + 40.0
	var tween := create_tween()
	tween.tween_property(_panel, "offset_left", target_left, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(_panel, "offset_right", target_right, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(_panel, "modulate:a", 1.0, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func show_result(success: bool, fish_id: String, fish_display_name: String,
		sell_value: int, difficulty: int = 1, is_perfect: bool = false,
		is_new_species: bool = false) -> void:
	_active = false
	_casting = false
	_hook_window = false
	_showing_result = true
	_difficulty_preview_active = false
	_panel.visible = false
	_casting_label.visible = false
	_hook_alert_label.visible = false
	_difficulty_card.visible = false
	_quit_button.visible = false
	_result_panel.visible = true
	visible = true
	_fish_id = fish_id

	# Clear old icon from result container
	for child in _result_icon_container.get_children():
		if child != _result_label:
			child.queue_free()

	# Star rating with Unicode
	var stars_text := ""
	if success:
		for i in 5:
			if i < difficulty:
				stars_text += "\u2605"
			else:
				stars_text += "\u2606"
	_result_stars_label.text = stars_text

	# Position tracking for stacking labels
	var next_y: float = 70.0

	_result_stars_label.position.y = next_y
	if stars_text != "":
		next_y += 25.0

	if success:
		# Add fish icon before result text
		var info := DataRegistry.get_item_display_info(fish_id)
		if not info.is_empty():
			var icon := UITheme.create_item_icon(info, 32)
			_result_icon_container.add_child(icon)
			_result_icon_container.move_child(icon, 0)

		# Fish name as heading + coin value
		var coin_text := ""
		if sell_value > 0:
			coin_text = "  %dg" % sell_value
		_result_label.text = fish_display_name + coin_text
		UITheme.style_emphasis(_result_label)

		# Result panel border - success green
		var result_style := _result_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if result_style:
			result_style.border_color = UITokens.ACCENT_BASIL

		# Perfect catch display
		if is_perfect:
			_result_perfect_label.text = "Perfect Cast!"
			_result_perfect_label.visible = true
			_result_perfect_label.position.y = next_y
			next_y += 25.0

			# Perfect label pop tween
			_result_perfect_label.scale = Vector2(1.5, 1.5)
			var perf_tween := create_tween()
			perf_tween.tween_property(_result_perfect_label, "scale", Vector2.ONE, 0.3)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(0.15)
		else:
			_result_perfect_label.visible = false

		# New species badge
		if is_new_species:
			_result_new_species_label.visible = true
			_result_new_species_label.position.y = next_y
			next_y += 25.0

			# NEW! badge pop tween
			_result_new_species_label.scale = Vector2(1.5, 1.5)
			var new_tween := create_tween()
			new_tween.tween_property(_result_new_species_label, "scale", Vector2.ONE, 0.3)\
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).set_delay(0.15)

			# Also show HUD toast
			var hud = get_node_or_null("/root/Main/GameWorld/UI/HUD")
			if hud and hud.has_method("show_new_fish_toast"):
				hud.show_new_fish_toast(fish_display_name)
		else:
			_result_new_species_label.visible = false

		# White flash post-processing
		_white_flash = 0.3

		# Scale-pop tween on result panel
		_result_panel.scale = Vector2(0.8, 0.8)
		var tween := create_tween()
		tween.tween_property(_result_panel, "scale", Vector2(1.0, 1.0), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	else:
		_result_label.text = "It got away..."
		UITheme.style_body_text(_result_label)
		_result_stars_label.text = ""
		_result_perfect_label.visible = false
		_result_new_species_label.visible = false

		var result_style := _result_panel.get_theme_stylebox("panel") as StyleBoxFlat
		if result_style:
			result_style.border_color = UITokens.ACCENT_TOMATO

		# Red vignette post-processing
		_red_vignette = 0.4

		# Failure: subtle fade-in instead of bounce
		_result_panel.scale = Vector2.ONE
		_result_panel.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_result_panel, "modulate:a", 1.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

		# Panel shake on failure (offset-based)
		var base_offset_left: float = _result_panel.offset_left
		var base_offset_right: float = _result_panel.offset_right
		var shake_tween := create_tween()
		for i in 4:
			var shake_x: float = randf_range(-3.0, 3.0)
			shake_tween.tween_property(_result_panel, "offset_left", base_offset_left + shake_x, 0.03)
			shake_tween.parallel().tween_property(_result_panel, "offset_right", base_offset_right + shake_x, 0.03)
		shake_tween.tween_property(_result_panel, "offset_left", base_offset_left, 0.03)
		shake_tween.parallel().tween_property(_result_panel, "offset_right", base_offset_right, 0.03)

	# Position dismiss label
	_result_dismiss_label.position.y = next_y + 5.0
	_result_dismiss_label.visible = true

	# Auto-fade result after 2.5s
	var exit_tween := create_tween()
	exit_tween.tween_interval(2.5)
	exit_tween.tween_property(_result_panel, "modulate:a", 0.0, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	exit_tween.tween_callback(close)


func close() -> void:
	_active = false
	_casting = false
	_hook_window = false
	_showing_result = false
	_finished = false
	_difficulty_preview_active = false
	visible = false
	if _result_dismiss_label:
		_result_dismiss_label.visible = false
	if _difficulty_card:
		_difficulty_card.visible = false
	_vignette_strength = 0.0
	_red_vignette = 0.0
	_white_flash = 0.0
	_update_pp_uniforms()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	# Update post-processing effects (always, even during hook window)
	_update_post_processing(delta)

	# Difficulty preview card timing
	if _difficulty_preview_active:
		_difficulty_preview_timer += delta
		if _difficulty_preview_timer >= 0.8:
			# Fade out card
			var tween := create_tween()
			tween.tween_property(_difficulty_card, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tween.tween_callback(_activate_minigame)
			_difficulty_preview_active = false
		return

	# Casting label animated ellipsis + bob
	if _casting and _casting_label.visible:
		_casting_anim_time += delta
		# Ellipsis cycle
		var dots: int = int(_casting_anim_time / 0.5) % 4
		var dot_str := ""
		for i in dots:
			dot_str += "."
		_casting_label.text = "Casting" + dot_str
		# Gentle Y bob via offset (anchors handle base position)
		_casting_label.offset_top = sin(_casting_anim_time * 1.5) * 4.0
		_casting_label.offset_bottom = sin(_casting_anim_time * 1.5) * 4.0

	# Hook window alert animation
	if _hook_window and _hook_alert_label.visible:
		_hook_alert_timer += delta
		# Subtle scale pulse (1.0 <-> 1.05)
		var pulse: float = 1.0 + sin(_hook_alert_timer * 8.0) * 0.05
		_hook_alert_label.scale = Vector2(pulse, pulse)
		# Flash modulate
		var flash: bool = fmod(_hook_alert_timer, 0.12) < 0.06
		_hook_alert_label.modulate.a = 1.0 if flash else 0.4
		# Pulsing vignette during hook window
		_vignette_strength = 0.2 + sin(_hook_alert_timer * 4.0) * 0.2

	if not _active or _finished:
		return

	_elapsed += delta

	# Update timer display with themed color feedback
	var remaining: float = maxf(_time_limit - _elapsed, 0.0)
	_timer_label.text = "%.1f" % remaining
	if remaining < 3.0:
		_timer_label.add_theme_color_override("font_color", UITokens.TEXT_DANGER)
	elif remaining < 5.0:
		_timer_label.add_theme_color_override("font_color", UITokens.TEXT_WARNING)
	else:
		_timer_label.add_theme_color_override("font_color", UITokens.INK_SECONDARY)

	# Step fish state (Stardew-style, matches server replay)
	var fish_state: Dictionary = FishingMinigame.step_fish(
			_fish_pos, _fish_speed, _fish_target, _fish_bias,
			_fish_rng, _sdv_diff, _movement_type)
	_fish_pos = fish_state["pos"]
	_fish_speed = fish_state["speed"]
	_fish_target = fish_state["target"]
	_fish_bias = fish_state["bias"]
	_fish_rng = fish_state["rng"]
	var fish_pos: float = _fish_pos

	# Physics-based bar movement (mirrors FishingMinigame.simulate)
	if _holding:
		_bar_velocity += FishingMinigame.BAR_LIFT * delta
	else:
		_bar_velocity += FishingMinigame.BAR_GRAVITY * delta
	_bar_velocity *= FishingMinigame.BAR_DAMPING
	_bar_pos += _bar_velocity * delta

	# Bounce off bottom
	if _bar_pos < 0.0:
		_bar_pos = 0.0
		_bar_velocity = absf(_bar_velocity) * FishingMinigame.BAR_BOUNCE

	# Clamp top
	if _bar_pos > 1.0:
		_bar_pos = 1.0
		_bar_velocity = 0.0

	# Check overlap
	var half_bar: float = _bar_size / 2.0
	var overlaps: bool = absf(fish_pos - _bar_pos) <= half_bar

	# Update catch meter
	if overlaps:
		_catch_meter += FishingMinigame.CATCH_FILL_RATE * delta
	else:
		_catch_meter -= FishingMinigame.CATCH_DRAIN_RATE * delta
	_catch_meter = clampf(_catch_meter, 0.0, 1.0)

	# Update visuals
	_update_visuals(fish_pos)

	# Check success
	if _catch_meter >= 1.0:
		_finished = true
		# Brief panel border flash on 100%
		var border_flash_tween := create_tween()
		var panel_style := _panel.get_theme_stylebox("panel") as StyleBoxFlat
		if panel_style:
			var orig_color := panel_style.border_color
			panel_style.border_color = UITokens.ACCENT_HONEY
			border_flash_tween.tween_interval(0.15)
			border_flash_tween.tween_callback(func(): panel_style.border_color = orig_color)
		_send_result(true)
		return

	# Check timeout
	if _elapsed >= _time_limit:
		_finished = true
		_send_result(false)
		return


func _update_visuals(fish_pos: float) -> void:
	# Fish indicator position (0.0 = top, 1.0 = bottom — invert for visual)
	var fish_y: float = (1.0 - fish_pos) * (BAR_HEIGHT - _fish_indicator.size.y)
	_fish_indicator.position.y = fish_y

	# Catch bar position and size
	var bar_pixel_size: float = _bar_size * BAR_HEIGHT
	var bar_y: float = (1.0 - _bar_pos) * BAR_HEIGHT - bar_pixel_size / 2.0
	bar_y = clampf(bar_y, 0.0, BAR_HEIGHT - bar_pixel_size)
	_catch_bar.position.y = bar_y
	_catch_bar.size.y = bar_pixel_size

	# Check overlap for visual feedback
	var half_bar: float = _bar_size / 2.0
	var overlaps: bool = absf(fish_pos - _bar_pos) <= half_bar

	# Catch bar color based on catch_meter (themed colors)
	var bar_style := _catch_bar.get_theme_stylebox("panel") as StyleBoxFlat
	if bar_style:
		var bar_color: Color
		var border_color: Color
		if _catch_meter > 0.5:
			bar_color = Color(UITokens.ACCENT_BASIL.r, UITokens.ACCENT_BASIL.g, UITokens.ACCENT_BASIL.b, 0.55)
			border_color = UITokens.ACCENT_BASIL
		elif _catch_meter > 0.25:
			bar_color = Color(UITokens.ACCENT_HONEY.r, UITokens.ACCENT_HONEY.g, UITokens.ACCENT_HONEY.b, 0.55)
			border_color = UITokens.ACCENT_HONEY
		else:
			bar_color = Color(UITokens.ACCENT_TOMATO.r, UITokens.ACCENT_TOMATO.g, UITokens.ACCENT_TOMATO.b, 0.55)
			border_color = UITokens.ACCENT_TOMATO

		# Brighten when overlapping fish
		if overlaps:
			bar_color.a = 0.75
			border_color = border_color.lightened(0.2)

		bar_style.bg_color = bar_color
		bar_style.border_color = border_color

	# Fish indicator overlap feedback
	var fish_style := _fish_indicator.get_theme_stylebox("panel") as StyleBoxFlat
	if fish_style:
		if overlaps:
			fish_style.bg_color = UITokens.ACCENT_BERRY.lerp(UITokens.ACCENT_BASIL, 0.2)
		else:
			fish_style.bg_color = UITokens.ACCENT_BERRY

	# Catch meter (fills from bottom)
	var meter_height: float = _catch_meter * BAR_HEIGHT
	_meter_bar.position.y = _bar_top_y + BAR_HEIGHT - meter_height
	_meter_bar.size.y = meter_height

	# Meter color matches catch bar thresholds
	var meter_style := _meter_bar.get_theme_stylebox("panel") as StyleBoxFlat
	if meter_style:
		if _catch_meter > 0.5:
			meter_style.bg_color = UITokens.ACCENT_BASIL
		elif _catch_meter > 0.25:
			meter_style.bg_color = UITokens.ACCENT_HONEY
		else:
			meter_style.bg_color = UITokens.ACCENT_TOMATO

	# Pulse meter fill width when catch_meter > 0.9 (almost done!)
	if _catch_meter > 0.9:
		_meter_pulse_time += get_process_delta_time() * 8.0
		var pulse_w: float = 20.0 + sin(_meter_pulse_time) * 2.0
		_meter_bar.size.x = pulse_w
		# Color lerp toward HONEY + alpha pulse
		if meter_style:
			var pulse_alpha: float = 0.8 + sin(_meter_pulse_time) * 0.2
			meter_style.bg_color = UITokens.ACCENT_BASIL.lerp(UITokens.ACCENT_HONEY, 0.3 + sin(_meter_pulse_time) * 0.3)
			meter_style.bg_color.a = pulse_alpha
	else:
		_meter_bar.size.x = 20.0
		_meter_pulse_time = 0.0


func _update_post_processing(delta: float) -> void:
	if _pp_shader_mat == null:
		return

	# Decay effects when not in hook window
	if not _hook_window:
		_vignette_strength = maxf(_vignette_strength - delta * 3.0, 0.0)

	# Decay red vignette
	_red_vignette = maxf(_red_vignette - delta * 0.7, 0.0)

	# Decay white flash
	_white_flash = maxf(_white_flash - delta * 0.6, 0.0)

	_update_pp_uniforms()


func _update_pp_uniforms() -> void:
	if _pp_shader_mat == null:
		return
	_pp_shader_mat.set_shader_parameter("vignette_strength", _vignette_strength)
	_pp_shader_mat.set_shader_parameter("red_vignette", _red_vignette)
	_pp_shader_mat.set_shader_parameter("white_flash", _white_flash)


func is_fishing() -> bool:
	return visible and (_active or _casting or _hook_window or _showing_result or _difficulty_preview_active)


func _input(event: InputEvent) -> void:
	# Result screen: E/Space/ESC to dismiss
	if _showing_result:
		if event.is_action_pressed("interact") or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel"):
			close()
			get_viewport().set_input_as_handled()
		return

	# Hook window: E/Space to hook, ESC to cancel
	if _hook_window:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
			_hook_window = false
			_casting = true  # Bridge gap until start_minigame() clears it
			_hook_alert_label.visible = false
			_vignette_strength = 0.0
			var fishing_mgr = get_node_or_null("/root/Main/GameWorld/FishingManager")
			if fishing_mgr:
				fishing_mgr.request_hook_fish.rpc_id(1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_cancel"):
			_hook_window = false
			_hook_alert_label.visible = false
			_vignette_strength = 0.0
			var fishing_mgr = get_node_or_null("/root/Main/GameWorld/FishingManager")
			if fishing_mgr:
				fishing_mgr.request_cancel_fishing.rpc_id(1)
			get_viewport().set_input_as_handled()
			return
		return

	if _casting and event.is_action_pressed("ui_cancel"):
		var fishing_mgr = get_node_or_null("/root/Main/GameWorld/FishingManager")
		if fishing_mgr:
			fishing_mgr.request_cancel_fishing.rpc_id(1)
		get_viewport().set_input_as_handled()
		return

	if not _active or _finished:
		return

	if event.is_action_pressed("ui_cancel"):
		_finished = true
		var fishing_mgr = get_node_or_null("/root/Main/GameWorld/FishingManager")
		if fishing_mgr:
			fishing_mgr.request_cancel_fishing.rpc_id(1)
		get_viewport().set_input_as_handled()
		return

	# Hold/release for fishing bar (ui_accept = Space, interact = E)
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		if not _holding:
			_holding = true
			_input_log.append(_elapsed)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("ui_accept") or event.is_action_released("interact"):
		if _holding:
			_holding = false
			_input_log.append(_elapsed)
		get_viewport().set_input_as_handled()


func _get_reel_hint() -> String:
	if Input.get_connected_joypads().size() > 0:
		return "Hold [A] to reel"
	return "Hold [E] to reel"


func _on_quit_pressed() -> void:
	var fishing_mgr = get_node_or_null("/root/Main/GameWorld/FishingManager")
	if not fishing_mgr:
		return
	if _active and not _finished:
		_finished = true
		fishing_mgr.request_cancel_fishing.rpc_id(1)
	elif _casting or _hook_window:
		_casting = false
		_hook_window = false
		_hook_alert_label.visible = false
		_vignette_strength = 0.0
		fishing_mgr.request_cancel_fishing.rpc_id(1)


func _send_result(success: bool) -> void:
	var fishing_mgr = get_node_or_null("/root/Main/GameWorld/FishingManager")
	if fishing_mgr:
		fishing_mgr.request_reel_result.rpc_id(1, _input_log, success)
