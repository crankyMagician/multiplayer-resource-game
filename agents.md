# Agents Guide — Creature Crafting Multiplayer Resource Game

## Quick Reference

| Area | Key Files | Notes |
|------|-----------|-------|
| UI Theme | `scripts/ui/ui_theme.gd`, `scripts/ui/ui_tokens.gd` | UITheme is `class_name` — never preload. UITokens has no `class_name` — must preload. |
| Settings | `scripts/ui/tabs/settings_tab.gd` | Font scale + text speed + volume. Persisted to `user://settings.cfg`. |
| Battle Arena | `scripts/battle/battle_arena.gd`, `scripts/battle/battle_arena_ui.gd` | 3D arena is client-only. Label3D sizes must use `UITheme.scaled()`. |
| Hotbar | `scripts/ui/hotbar_ui.gd` | CanvasLayer overlay. Font sizes must use `UITheme.scaled()`. |
| Animation | `scripts/player/player_controller.gd`, `tools/build_animation_library.gd` | AnimationTree as standalone AnimationMixer (no separate AnimationPlayer). See CLAUDE.md Animation System. |
| Player Physics | `scripts/player/player_controller.gd` (line ~578), `scenes/player/player.tscn` | `_update_crouch_collision()` MUST lerp both capsule height AND CollisionShape3D Y. See CLAUDE.md Player/Camera Notes. |
| Networking | `scripts/autoload/network_manager.gd` | Server-authoritative. See CLAUDE.md Networking Rules. |
| Battle | `scripts/battle/battle_manager.gd` | Server-authoritative battle state. See `docs/battle-system.md`. |
| Data Registry | `scripts/autoload/data_registry.gd` | Loads all `.tres` resources. Handles `.remap` in exports. |
| Game Pillars | `docs/game-pillars-theme.md` | Core fantasy, pillars, tone, and inspirations. |
| Demo Plan | `docs/demo-plan.md` | Target demo scope with Done/To Do status. |

## UI Styling Rules

### Font Scaling Convention
All runtime font sizes MUST go through `UITheme.scaled()`:
```gdscript
# CORRECT — scales with user's font size setting
label.add_theme_font_size_override("font_size", UITheme.scaled(UITokens.FONT_BODY))

# WRONG — bypasses font scaling, won't respond to accessibility settings
label.add_theme_font_size_override("font_size", UITokens.FONT_BODY)
```

This applies to:
- 2D UI Labels, Buttons, LineEdits, RichTextLabels
- 3D Label3D nodes (battle arena trainer/opponent names, damage numbers)
- Any `add_theme_font_size_override()` call

### Semantic Style Functions
Prefer semantic helpers over manual styling:
```gdscript
UITheme.style_title(label)         # H1, heading font, primary ink
UITheme.style_section(label)       # H2, heading font, primary ink
UITheme.style_body_text(label)     # Body, body font, primary ink
UITheme.style_caption(label)       # Small, body font, secondary ink
UITheme.style_button(button)       # Primary variant by default
UITheme.style_label3d(label, "", "npc_name")  # 3D label with role preset
```

These all call `UITheme.scaled()` internally — no extra scaling needed.

### Color Tokens
Use `UITokens` constants instead of hardcoded colors:
- **Ink**: `INK_PRIMARY`, `INK_SECONDARY`, `INK_DISABLED`
- **Paper**: `PAPER_BASE`, `PAPER_CARD`, `PAPER_EDGE`
- **Stamps**: `STAMP_RED`, `STAMP_GREEN`, `STAMP_GOLD`, `STAMP_BLUE`, `STAMP_BROWN`
- **Text semantics**: `TEXT_SUCCESS`, `TEXT_WARNING`, `TEXT_DANGER`, `TEXT_INFO`, `TEXT_MUTED`
- **Type colors**: `TYPE_SPICY`, `TYPE_SWEET`, `TYPE_SOUR`, `TYPE_HERBAL`, `TYPE_UMAMI`, `TYPE_GRAIN`

## Settings Persistence

Settings are saved to `user://settings.cfg` using Godot's `ConfigFile`:

```ini
[audio]
master_volume=1.0

[accessibility]
font_scale=1.0
font_scale_idx=1
text_speed_cps=40.0
text_speed_idx=1
```

- **Index keys** (`font_scale_idx`, `text_speed_idx`) are the reliable identifiers — integer slider positions.
- **Float keys** (`font_scale`, `text_speed_cps`) kept for backward compatibility and for `UITheme._load_settings()` which reads `font_scale` directly at init.
- Load prefers index, falls back to float `Array.find()` if index is missing (old config files).

## Networking Checklist (for any new feature)

Before writing code, answer:
1. Server only, client only, or both?
2. Does server need to validate? (Almost always yes)
3. Do other clients need to see the result?
4. Race condition risk with optimistic client update?

See CLAUDE.md "Networking Rules" for the full authority model table.

## Testing

```bash
# GDScript tests (GUT) — 767+ tests
'/Applications/Mechanical Turk.app/Contents/MacOS/Mechanical Turk' --path . --headless -s addons/gut/gut_cmdln.gd -gexit

# Express API tests (Vitest)
cd api && npx vitest run
```

All tests must pass before committing. See `docs/testing-guide.md` for patterns.
