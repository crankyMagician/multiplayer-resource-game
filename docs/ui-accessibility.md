# UI Theme & Accessibility System

## Overview

The UI system uses two core files:
- **UITokens** (`scripts/ui/ui_tokens.gd`) — static design tokens (colors, font sizes, layout constants). No `class_name`, must be preloaded.
- **UITheme** (`scripts/ui/ui_theme.gd`) — `class_name UITheme`. Semantic styling API, font loading, font scale/text speed state, and settings persistence.

All UI code is client-only. The server skips UI setup entirely (see CLAUDE.md "Dedicated server detection").

## Architecture

```
UITokens (constants)          UITheme (class_name, static API)
├── Colors                    ├── init() — loads fonts + settings
│   ├── Paper (base/card/edge)│   ├── scaled(size) → int(size * _font_scale)
│   ├── Ink (primary/sec/dis) │   ├── style_title/section/body/caption/button/...
│   ├── Stamp (red/green/gold)│   ├── set_font_scale() / set_text_speed()
│   ├── Text semantics        │   └── make_panel_style() / style_label3d()
│   └── Type colors           │
├── Font sizes (H1=36..TINY=16)   Settings Tab (settings_tab.gd)
└── Layout (margins, radii)       ├── Font Size slider (4 steps)
                                  ├── Text Speed slider (4 steps)
                                  └── Volume slider + Reset button
```

## Font Scaling

### How It Works
`UITheme._font_scale` is a static float (default `1.0`) that multiplies all font sizes:

```gdscript
static func scaled(size: int) -> int:
    return int(size * _font_scale)
```

### 4 Scale Steps

| Step | Name | Scale | Effect |
|------|------|-------|--------|
| 0 | Small | 0.85x | 85% of base size |
| 1 | Normal | 1.0x | Default |
| 2 | Large | 1.15x | 115% of base size |
| 3 | Extra Large | 1.3x | 130% of base size |

### Usage Rules

**ALWAYS** use `UITheme.scaled()` when setting font sizes at runtime:

```gdscript
# 2D Labels — use scaled() with any UITokens constant
label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_BODY))

# 3D Label3D — use scaled() with literal values too
trainer_label.font_size = UITheme.scaled(28)
damage_label.font_size = UITheme.scaled(48)

# Semantic helpers (already call scaled() internally — don't double-scale)
UITheme.style_title(label)
UITheme.style_button(button)
UITheme.style_label3d(label, "text", "npc_name")
```

**NEVER** use raw `UITokens.FONT_*` for runtime font sizes — this bypasses scaling.

### Where Scaling Is Applied

| Component | File | What's Scaled |
|-----------|------|---------------|
| All styled Labels | `ui_theme.gd` `_style_label()` | Font size via `scaled()` |
| Buttons | `ui_theme.gd` `style_button()` | Font size |
| Sidebar buttons | `ui_theme.gd` `style_sidebar_button()` | Font size |
| LineEdit inputs | `ui_theme.gd` `style_input()` | Font size |
| RichTextLabels | `ui_theme.gd` `style_richtext_defaults()` | Normal font size |
| Label3D (world) | `ui_theme.gd` `style_label3d()` | Font size by role |
| Label3D (battle) | `battle_arena.gd` | Trainer/opponent labels (28), damage numbers (48) |
| Modal panels | Various `*_ui.gd` files | `scaled_vec()` for minimum sizes |

## Text Speed

### How It Works
`UITheme._text_speed_cps` controls typewriter text display speed (characters per second):

```gdscript
static func get_text_speed() -> float:
    return _text_speed_cps  # -1 means instant
```

### 4 Speed Steps

| Step | Name | CPS | Effect |
|------|------|-----|--------|
| 0 | Slow | 20 | Deliberate, easy to follow |
| 1 | Normal | 40 | Default speed |
| 2 | Fast | 80 | Quick readers |
| 3 | Instant | -1 | No typewriter, all text appears at once |

### Integration Points
- `dialogue_ui.gd` — NPC dialogue typewriter
- `trainer_dialogue_ui.gd` — Trainer pre/post battle dialogue
- Any future typewriter text should check `UITheme.get_text_speed()`

## Settings Persistence

### File Format
Settings are stored at `user://settings.cfg` using Godot's `ConfigFile`:

```ini
[audio]
master_volume=1.0

[accessibility]
font_scale=1.0
font_scale_idx=1
text_speed_cps=40.0
text_speed_idx=1
```

### Dual-Key Strategy
Both float values and integer indices are saved:

- **Index keys** (`font_scale_idx`, `text_speed_idx`) — reliable, immune to float comparison issues
- **Float keys** (`font_scale`, `text_speed_cps`) — backward compatible, used by `UITheme._load_settings()` at init

### Load Priority
1. Try integer index key first
2. If missing or out of range, fall back to float value + `Array.find()`
3. If float not found either, default to index 1 (Normal)

This ensures old config files (pre-index) still work, while new saves are robust.

### Two Load Paths
1. **`UITheme._load_settings()`** — runs at `init()`, reads `font_scale` float directly (sets `_font_scale` before any UI builds)
2. **`settings_tab.gd` `_load_settings()`** — runs when Settings tab opens, uses index-first strategy to position sliders correctly

## Color Token Reference

### Paper (backgrounds)
| Token | Hex | Usage |
|-------|-----|-------|
| `PAPER_BASE` | `#FFF8EF` | Primary background, buttons |
| `PAPER_CARD` | `#F6EBDD` | Card/panel backgrounds |
| `PAPER_EDGE` | `#E6D3BC` | Disabled backgrounds, borders |

### Ink (text)
| Token | Hex | Usage |
|-------|-----|-------|
| `INK_PRIMARY` | `#2B241E` | Main body text |
| `INK_SECONDARY` | `#55483B` | Captions, secondary text |
| `INK_DISABLED` | `#7A6A59` | Disabled/muted text |

### Stamps (accents)
| Token | Hex | Usage |
|-------|-----|-------|
| `STAMP_RED` | `#A6473F` | Danger, HP low |
| `STAMP_GREEN` | `#3F6A47` | Success, HP high |
| `STAMP_GOLD` | `#9C6A1A` | Accent, section headers, HP medium |
| `STAMP_BLUE` | `#3E5C7A` | Info, water bar |
| `STAMP_BROWN` | `#6C4B2F` | Borders, panels |

### Type Colors (battle)
| Token | Hex | Type |
|-------|-----|------|
| `TYPE_SPICY` | `#A84A3C` | Spicy |
| `TYPE_SWEET` | `#B56A7A` | Sweet |
| `TYPE_SOUR` | `#6E7A2F` | Sour |
| `TYPE_HERBAL` | `#4A6B3E` | Herbal |
| `TYPE_UMAMI` | `#6B4E38` | Umami |
| `TYPE_GRAIN` | `#8C6A2D` | Grain |

## Font Size Tokens

| Token | Base Size | At 0.85x | At 1.0x | At 1.15x | At 1.3x |
|-------|-----------|----------|---------|----------|---------|
| `FONT_H1` | 36 | 30 | 36 | 41 | 46 |
| `FONT_H2` | 30 | 25 | 30 | 34 | 39 |
| `FONT_H3` | 24 | 20 | 24 | 27 | 31 |
| `FONT_BODY` | 20 | 17 | 20 | 23 | 26 |
| `FONT_SMALL` | 18 | 15 | 18 | 20 | 23 |
| `FONT_TINY` | 16 | 13 | 16 | 18 | 20 |

## Label3D Roles

`UITheme.style_label3d(label, text, role)` applies preset styling:

| Role | Base Size | Font | Color | Usage |
|------|-----------|------|-------|-------|
| `"station"` | 48 | Heading | Gold | Crafting station signs |
| `"landmark"` | 72 | Heading | Gold | Major landmark names |
| `"npc_name"` | 24 | Heading | Dark ink | NPC nameplates |
| `"quest_marker"` | 48 | Heading | Gold | Quest indicators |
| `"interaction_hint"` | 24 | Body | Light ink | "Press E" prompts |
| `"zone_sign"` | 36 | Heading | Tan | Zone entrance signs |
| `"world_item"` | 32 | Body | Cream | Dropped item labels |
| `"danger"` | 28 | Heading | Red | Warning labels |
| (default) | 24 | Body | Base | Generic 3D text |

## Icon System (Synty POLYGON_Icons + Kawaii Shader)

### Overview
All item icons are pre-baked 256x256 PNGs rendered from Synty POLYGON_Icons 3D meshes through a kawaii toon shader pipeline. Zero runtime cost — icons are static textures loaded from `res://assets/ui/textures/icons/<category>/`.

### Icon Helper
`UITheme.create_item_icon(info, base_size)` is the universal factory for item icons:

```gdscript
# Returns TextureRect if icon_texture exists, ColorRect fallback otherwise
var icon: Control = UITheme.create_item_icon(info, 20)
container.add_child(icon)
```

- `info` — Dictionary from `DataRegistry.get_item_display_info()` (has `icon_texture` and `icon_color` keys)
- `base_size` — Base pixel size before scaling (default 32). Automatically scaled via `UITheme.scaled()`
- All icons have `mouse_filter = MOUSE_FILTER_IGNORE`

### Where Icons Are Used

| UI Component | File | Icon Size |
|-------------|------|-----------|
| Inventory list | `inventory_tab.gd` | 20 |
| Shop buy/sell | `shop_ui.gd` | 20 |
| Trade panels | `trade_ui.gd` | 16 |
| Crafting UI | `crafting_ui.gd` | 20 |
| Battle items | `battle_ui.gd` | 20 |
| Compendium | `compendium_tab.gd` | 20 |

### Adding Icons for New Items
1. Add the GLB path mapping in `tools/bake_icons_cli.gd` `icon_manifest`
2. Run the bake script: `'/Applications/Mechanical Turk.app/Contents/MacOS/Mechanical Turk' --path . --script tools/bake_icons_cli.gd`
3. Add `icon_texture = ExtResource(...)` to the item's `.tres` file pointing to the baked PNG
4. `DataRegistry.get_item_display_info()` automatically includes `icon_texture` — no code changes needed

### Bake Pipeline
- **Shaders**: `shaders/toon_icon.gdshader` (cel + pastel remap + rim light), `shaders/icon_outline.gdshader` (inverted hull)
- **Synty palette**: GLBs use shared `PolygonIcons_Texture_01_A.png` — bake script auto-assigns it
- **Output**: `assets/ui/textures/icons/{ingredients,foods,tools,battle_items,held_items,ui}/`

## Adding New UI Components

1. Call `UITheme.init()` in `_ready()` if the component is a root-level scene
2. Use semantic style functions (`style_title`, `style_body`, etc.) for labels
3. Use `UITheme.scaled()` for any manual `font_size` overrides
4. Use `UITokens` color constants, never hardcoded hex values
5. For panels, use `UITheme.make_panel_style()` or `UITheme.style_card()`
6. For 3D labels, use `UITheme.style_label3d()` with an appropriate role
7. For item icons, use `UITheme.create_item_icon(info)` — never create ColorRect manually
