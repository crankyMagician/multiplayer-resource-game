# Input & Controls

Quick reference for how input is declared and consumed across the project.

## Where things live
- Input map: `project.godot` `[input]` section defines every action and default key.
- Local capture: `scripts/player/player_controller.gd` reads movement/mouse and hotkey presses each frame.
- Server authority: the server runs `_physics_process()` in `player_controller.gd`; it moves players using the synced input values.
- Interaction gating: `scripts/player/player_interaction.gd` listens for world/action hotkeys and issues server RPCs (calendar, NPCs, farming, PvP, trade, etc.).
- UI toggles: each UI scene listens for its action and flips visibility + busy state (party, inventory, map, calendar, friend list).
- Replication: `scenes/player/player.tscn` has two `MultiplayerSynchronizer` nodes:
  - `InputSync` replicates `input_direction`, `camera_yaw`, `camera_pitch`, `interact_pressed`, `input_sprint`, `input_crouch`, `input_jump` from client → server.
  - `StateSync` replicates server-owned state (position, velocity, player_color, player_name_display, mesh_rotation_y, is_busy, movement_state, anim_move_speed, anim_action) out to clients.

## Keybinds & actions
| Action | Default key | What it does | Main code path |
| --- | --- | --- | --- |
| `move_forward/back/left/right` | `W/S/A/D` | Captured locally for movement input; sent via `InputSync`; server applies motion. | `scripts/player/player_controller.gd` |
| `interact` | `E` | Contextual world interaction: calendar board, social/shop/trainer NPCs, restaurant door, storage, crafting station, water source refill, farm plot actions (harvest/hoe/axe/water/plant). | `scripts/player/player_interaction.gd` |
| `hotbar_1`…`hotbar_8` | `1–8` | Select hotbar slots (items/tools). | `player_interaction.gd` |
| `hotbar_next` / `hotbar_prev` | Mouse wheel up/down | Cycle hotbar selection. | `player_interaction.gd` |
| `pvp_challenge` | `V` | Finds nearest player ≤5 units and sends PvP challenge. | `player_interaction.gd` |
| `trade` | `T` | Finds nearest player ≤5 units and requests trade. | `player_interaction.gd` |
| `open_party` | `P` | Toggle party UI; marks player busy while open. | `scripts/ui/party_ui.gd` |
| `open_inventory` | `I` | Toggle inventory UI; marks busy; drives item use/sell/equip. | `scripts/ui/inventory_ui.gd` |
| `open_map` | `M` | Toggle pause/minimap overlay when no other overlay is open. | `scripts/ui/pause_overlay.gd` |
| `quest_log` | `J` | Toggle quest log UI. | `player_interaction.gd` → `QuestLogUI` |
| `compendium` | `K` | Toggle compendium UI. | `player_interaction.gd` → `CompendiumUI` |
| `friend_list` | `F` | Toggle friend/party UI; also responds to invites. | `player_interaction.gd`, `scripts/ui/friend_list_ui.gd` |
| `toggle_mouse` | `Esc` (physical keycode) | Toggle mouse capture/visibility during gameplay. | `player_controller.gd` `_input()` |
| `ui_cancel` | Godot default (`Esc`) | Used by several overlays to close (map, calendar, friend list) when open. | `pause_overlay.gd`, `calendar_ui.gd`, `friend_list_ui.gd` |

Notes:
- `Esc` is bound to both `toggle_mouse` and `ui_cancel`; UI scripts call `set_input_as_handled()` when they consume it to avoid double-triggering.
- When an overlay opens, it typically sets `Input.mouse_mode` to `VISIBLE` and calls `NetworkManager.request_set_busy` so the server stops processing movement/interaction for that player (`is_busy` shows above the player via StateSync).

## Input flow (per frame)
1) Client `_input` handles mouse motion and `toggle_mouse` for capture/rotation (yaw/pitch), clamped to ±70° pitch.
2) Client `_process` samples movement vector + hotkey presses and stores them in replicated vars (`input_direction`, `interact_pressed`).
3) `InputSync` pushes those to the server; server-only `_physics_process` applies gravity, speed buffs, and movement, and rotates the mesh toward movement.
4) Interaction hotkeys (`interact`, number keys, PvP, trade, social/UI toggles) run on the owning client and issue server RPCs where needed; server re-validates everything (farm actions, trades, challenges, etc.).
5) UI actions toggle layers and busy state; busy locks also prevent input handling in `player_interaction.gd` as a client-side guard.

## Updating controls
- Add new actions to `project.godot` `[input]`, then wire them in the relevant script.
- For anything that affects gameplay state, decide authority and sync path: server-only vs client-only vs replicated, and add to `NetworkManager`/StateSync/InputSync as appropriate.
- Remember to set/clear busy (via `NetworkManager.request_set_busy`) when adding new modal UIs so movement/interaction is paused safely.
