# Character Customization System

## Source Assets

"Customizable 3D Characters Complete Bundle" (AR Kit, Unity Asset Store) — 397 FBX models across male/female, 8-9 body part categories per gender.

## Asset Pipeline

| Tool | Purpose |
|------|---------|
| `tools/convert_arkit_to_ual.py` | Blender batch bone remap: Mixamo→UAL |
| `tools/import_arkit_characters.sh` | Import + organize |
| `tools/validate_character_parts.gd` | Bone validation |
| `tools/retarget_rest_pose.py` | Rest pose retarget + finger weight collapse |

### Bone Remap

AR Kit uses Mixamo bones (`Hips`, `Arm.L`), UAL uses Unreal bones (`pelvis`, `upperarm_l`). Script inserts `root` bone as parent of `pelvis`. Vertex groups auto-rename.

### Asset Structure

```
assets/characters/{gender}/base/
assets/characters/{gender}/parts/{category}/
assets/characters/icons/{gender}/
assets/characters/texture/
```

## Key Classes

- **CharacterAppearance** (`class_name`, Resource): gender, head_id, hair_id, torso_id, pants_id, shoes_id, arms_id, hat_id, glasses_id, beard_id. `to_dict()` / `from_dict()`.
- **CharacterPartRegistry** (`class_name`, static): scans part dirs, handles `.glb`/`.glb.remap`/`.glb.import`. `get_parts()`, `get_part_path()`, `validate_appearance()`.
- **CharacterAssembler** (`class_name`, static): `assemble(parent, appearance_dict)` → loads base model, hides default meshes, attaches parts to Skeleton3D, applies atlas material. Falls back to UAL mannequin.

## Player Integration

- `player.tscn` has no hardcoded CharacterModel — built dynamically in `_assemble_character()` on clients.
- `appearance_data: Dictionary` synced via StateSync (spawn-only, replication_mode=0).
- Server sets `player.appearance_data` in `_spawn_player()` BEFORE `add_child()`.

## NPC Integration

- `NPCDef.appearance: CharacterAppearance` and `TrainerDef.appearance: CharacterAppearance` (optional).
- `NpcAnimator.create_character_from_appearance()` uses CharacterAssembler. Falls back to color-tinted mannequin if no appearance set.

## Network Sync

- `request_update_appearance(dict)` client→server RPC
- Server validates, updates `player_data_store`, saves, broadcasts `_sync_appearance(peer_id, dict)` to all clients
- Player's `update_appearance()` rebuilds model + animation tree

## Character Creator UI

- CanvasLayer (layer 12). 3D SubViewport preview (drag to rotate) + category tabs + sprite icon grid.
- Gender toggle rebuilds categories. "None" for optional parts. `appearance_confirmed` signal.

## First-Login Flow

1. Default player data has `"appearance": {"needs_customization": true}`
2. After `_receive_player_data`, `game_world._check_first_time_customization()` opens CharacterCreatorUI
3. Cancel disabled for first-time. TestPlayer gets pre-set appearance.

## Pause Menu

"Character" tab shows current appearance summary + "Customize" button → opens CharacterCreatorUI.

## Persistence

`appearance` dict in `player_data_store`, persisted to MongoDB via existing `PUT /api/players/:id`. Backfilled for old saves in `_finalize_join()`.
