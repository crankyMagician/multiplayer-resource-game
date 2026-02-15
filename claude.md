# Claude Notes

## Project Runtime Defaults
- Multiplayer default port: `7777` (UDP).
- **Smart IP defaults**: In editor, ConnectUI defaults to `127.0.0.1` (localhost). In exported builds, defaults to `207.32.216.76` (public server). Editor mode ignores saved prefs for IP to prevent stale overrides.
- **Dedicated server detection** (3 triggers, checked in `NetworkManager._ready()`):
  1. `DisplayServer.get_name() == "headless"` — Docker/headless export
  2. `OS.has_feature("dedicated_server")` — Godot dedicated server export
  3. `--server` or `--role=server` in `OS.get_cmdline_user_args()` — CLI flags (MCP `run_multiplayer_session` auto-passes `--role=server`)
- When dedicated mode is detected: auto-calls `host_game("Server")` + `GameManager.start_game()`, skips ConnectUI entirely, skips game world UI setup (HUD, BattleUI, etc.) and camera creation.

## Docker Server Workflow

### Two-Phase Build (Engine + Game)
The server Docker image requires matching the Mechanical Turk engine (Godot 4.7 fork) — stock Godot will cause RPC checksum mismatches and clients won't connect. The build is split into two phases:

1. **Engine build** (`Dockerfile.engine` + `scripts/build-engine-templates.sh`): Compiles MT engine from C++ source for Linux x86_64, producing `engine-builds/linux/godot-editor` (149MB) and `engine-builds/linux/godot-template` (82MB). Results are cached — subsequent runs are instant unless `--force` is passed. Requires the `mechanical-turk` engine repo at `../mechanical-turk/`.
2. **Game build** (`Dockerfile`): Uses the pre-built MT engine binaries to export the server. Templates go in `/root/.local/share/mechanical_turk/export_templates/4.7.dev/` (MT uses `mechanical_turk` as its data dir, NOT `godot`).

### Engine Build Details
- SCons flags: `platform=linuxbsd target=editor arch=x86_64 module_mono_enabled=no accesskit=no dev_mode=no lto=none`
- **LTO is disabled** (`lto=none`) because Docker's memory limit (~8GB) is insufficient for LTO linking (requires 16+ GB)
- Both `editor` (for `--export-release`) and `template_release` (embedded in exported binary) targets are built
- Build script: `./scripts/build-engine-templates.sh` (or `--force` to rebuild)

### Local Dev
- Use `./scripts/start-docker-server.sh` to rebuild and start the dedicated server locally.
- The script runs `docker compose up --build -d` from the project root and prints service status.
- Docker mapping is `7777:7777/udp`.
- Docker logs work in real-time via `docker logs -f multiplayer-resource-game-game-server-1` (uses `stdbuf -oL` for line-buffered output).
- Godot's internal log file is also available: `docker exec <container> cat "/root/.local/share/mechanical_turk/app_userdata/Creature Crafting Demo/logs/godot.log"`

## Multiplayer Join/Spawn Stabilization
- **Client pre-loads GameWorld on connect**: `_on_connected_to_server()` calls `GameManager.start_game()` BEFORE `request_join`. This ensures the MultiplayerSpawner exists in the client's scene tree before any spawn replication RPCs arrive from the server. Without this, late-joining clients get cascading errors when the server tries to replicate already-spawned players.
- Join flow uses a client-ready handshake before server-side spawn.
- Spawn waits for client world path readiness (`/root/Main/GameWorld/Players/MultiplayerSpawner`).
- Server tracks temporary join state and times out peers that never become ready.
- **New player spread spawn**: Players with no saved position spawn in a golden-angle circle (radius 2, center 0,0,3) to avoid overlap. Default player data has empty position `{}` so the spread logic triggers.

## Player/Camera Notes
- Player movement uses server authority with replicated input.
- Camera defaults to over-the-shoulder and captures mouse during world control.
- Mouse is explicitly made visible during battle UI and recaptured after battle ends.
- **Server has no camera or UI** — `game_world.gd` `_ready()` skips `_setup_ui()` and `_ensure_fallback_camera()` on the server. Only clients get HUD, BattleUI, etc.
- **Player collision layers**: Players use `collision_layer=2`, `collision_mask=1` (collide with ground/buildings on layer 1, but NOT with each other). TallGrass and TrainerNPC Area3Ds set `collision_mask=3` (bits 1+2) to detect players on layer 2.
- **UI node sharing**: `_setup_ui()` adds HUD, BattleUI, CraftingUI, InventoryUI, PartyUI to the **existing** `$UI` node from `game_world.tscn` (which already contains PvPChallengeUI, TrainerDialogueUI). Do NOT create a new "UI" node — Godot will rename it (e.g. `@Node@38`), breaking all path-based lookups.
- **Player visuals** (color, nameplate): set on the player node server-side **before** `add_child()` in `_spawn_player()`, synced via StateSync spawn-only mode (replication_mode=0). `_apply_visuals()` runs on all peers to apply color to mesh material and set nameplate text.
- **Mesh rotation**: `mesh_rotation_y` computed server-side in `_physics_process`, synced via StateSync always-mode. All clients apply it in `_process()` to `mesh.rotation.y`.
- **StateSync properties** (5 total): `position`, `velocity` (always), `player_color`, `player_name_display` (spawn-only), `mesh_rotation_y` (always).

## Battle System
- **3 battle modes**: Wild, Trainer (7 NPCs), PvP (V key challenge within 5 units of another player)
- **18 creatures** (9 original + 9 new), 4 evolution chains, MAX_PARTY_SIZE = 3
- **Starter creature**: All new players spawn with Rice Ball (Grain, Lv 5, 45 HP) with moves: grain_bash, quick_bite, bread_wall, syrup_trap
- **42 moves** including weather setters, hazards, protection, charging, multi-hit, recoil, drain
- **18 abilities** with trigger-based dispatch (on_enter/on_attack/on_defend/on_status/end_of_turn/on_weather)
- **12 held items** (6 type boosters, 6 utility) — all craftable from ingredients
- **XP/Leveling**: XP from battles, level-up stat recalc, learnset moves, evolution. Full XP to participants, 50% to bench.
- **AI**: 3 tiers (easy=random, medium=type-aware, hard=damage-calc + prediction)
- **PvP**: Both-submit simultaneous turns, 30s timeout, disconnect = forfeit. Loser forfeits 25% of each ingredient stack to winner.
- **Defeat penalty**: 50% money loss, teleport to spawn point, all creatures healed

### Battle UI
- **Enemy panel**: name, level, types, HP bar, status effect, stat stage labels (e.g. "Stats: DEF+2 SPA+1")
- **Player panel**: name, level, types, HP bar, XP bar, ability name, held item name
- **Move buttons**: 3-line format — Name / Type|Category|Power / Accuracy|PP (e.g. "Grain Bash / Grain | Phys | Pwr:65 / Acc:100% | 15/15 PP")
- **Weather bar**: shown when weather is active, displays weather name + remaining turns
- **Flee/Switch**: Flee available in wild only, Switch always available (opens creature picker overlay)
- **Turn log**: scrolling RichTextLabel with staggered entry animation (~0.3s apart). Ability messages in `[color=purple]`, item messages in `[color=cyan]`, effectiveness in green/yellow.
- **Visual polish**: HP bar tweens (0.5s smooth decrease, green→yellow→red color shift), hit flash on enemy mesh, damage number popups, fade-to-black battle transitions (via HUD CanvasLayer), summary panel slide-in + fade animation, XP bar fill animation (0.8s).
- **Summary screen**: shown after battle ends — hides all battle panels, shows Victory!/Defeat, XP per creature (with level-up highlights), item drops, trainer money + bonus ingredients. Continue button dismisses and returns to world.
- **PvP-specific**: no Flee button, "Waiting for opponent..." label after submitting move, both perspectives actor-swapped. PvP challenge UI auto-hides when battle starts.

### Battle Manager Server-Side
- Battle state keyed by `battle_id` (auto-increment), `player_battle_map[peer_id] → battle_id`
- Wild/Trainer: server picks AI action, resolves turn, sends `_send_turn_result` RPC
- PvP: both sides submit via `request_battle_action` RPC, server resolves when both received. End-of-turn effects (status, abilities, items, weather) are collected into a temp array and appended to both player logs with perspective-swapped actors.
- PvP perspective swap: `_swap_actor()` flips top-level `actor` field ("player"↔"enemy"). Ability/item messages are plain strings embedded in the move result — no separate actor field needed.
- Rewards sent via separate RPCs: `_grant_battle_rewards` (drops), `_send_xp_results` (XP/level-ups), `_grant_trainer_rewards_client` (money+ingredients), `_battle_defeat_penalty` (money loss)
- Client accumulates reward data in `summary_*` vars, summary screen displays after 0.5s delay

## Crafting & Item System (Unified Overhaul)
- **46 recipes**: 13 creature (cauldron, unlockable), 12 held item (workbench), 12 food (kitchen), 9 tool upgrade (workbench)
- **5 item types**: ingredients (16), held items (12), foods (12), tools (12), recipe scrolls (13) — all share single inventory namespace
- **3 crafting stations**: Kitchen (restaurant zone), Workbench (near spawn), Cauldron (deep wild zone) — each filters recipes by `station` field
- **Recipe unlock system**: Creature recipes require recipe scrolls to unlock. Scrolls come from trainer first-defeat rewards, world pickups, or fragment collection (3-5 fragments auto-combine)
- **Food & buffs**: 4 buff foods (speed_boost, xp_multiplier, encounter_rate, creature_heal) + 8 trade goods for selling. Buffs are timed, server-side expiry checked every 5s
- **Tool upgrades**: 3 tool types (hoe, axe, watering_can) x 4 tiers (basic→bronze→iron→gold). Upgrade recipes consume old tool + ingredients. Dynamic stats from ToolDef (capacity, speed_mult)
- **Crafting security**: Single-phase server-authoritative — `request_craft(recipe_id)` RPC validates everything server-side, deducts, produces result, syncs to client. No client-side deduction.
- **Selling**: `request_sell_item(item_id, qty)` RPC for food trade goods with sell_price
- **16 ingredients**: farm crops (season-locked) + battle drops
- New plantable crops: lemon (summer), pickle_brine (autumn)
- **Planting flow** (server-authoritative): Client sends `request_farm_action(plot_idx, "plant", seed_id)` RPC to server. Server removes seed from `player_data_store` inventory, attempts plant, rolls back on failure. No client-side inventory deduction.
- **Watering flow** (server-authoritative): Client sends `request_farm_action(plot_idx, "water", "")` RPC. Server calls `server_use_watering_can()` to decrement, then syncs remaining charges to client via `_sync_watering_can` RPC. Refill via `_request_refill` RPC at water sources.

### Buff Application Points
- **Speed boost**: `player_controller.gd` `_physics_process()` — multiplies move speed
- **XP multiplier**: `battle_manager.gd` `_grant_xp_for_defeat()` — multiplies XP
- **Encounter rate**: `encounter_manager.gd` `get_encounter_rate_multiplier()` — multiplies probability

### PlayerData Tool System
- **No Tool enum** — replaced with string-based `current_tool_slot` ("", "hoe", "axe", "watering_can", "seeds")
- `equipped_tools: Dictionary` maps tool_type → tool_id (e.g. `{"hoe": "tool_hoe_basic", ...}`)
- `get_watering_can_capacity()` reads from equipped ToolDef's effectiveness dict
- `known_recipes: Array` tracks unlocked recipe IDs
- `active_buffs: Array` of `{buff_type, buff_value, expires_at}` dicts

## World Item Drop & Pickup System
- **WorldItemManager** (`scripts/world/world_item_manager.gd`): Server-authoritative manager node in `game_world.tscn`, sibling of BattleManager/EncounterManager
- **WorldItem** (`scripts/world/world_item.gd`): Area3D pickup node with colored BoxMesh (0.4³), billboard Label3D, bobbing animation, walk-over auto-pickup
- **WorldItems** container: Node3D in `game_world.tscn` holds all spawned WorldItem nodes
- **Pickup flow**: Area3D `body_entered` (server-only) → `WorldItemManager.try_pickup()` → `server_add_inventory()` + `_sync_inventory_full` RPC → `_notify_pickup` RPC (HUD toast) → `_remove_world_item()` (despawn RPC to all)
- **Drop sources**: Random world forage spawns (every 120s, 10 spawn points, weighted table), farm plot clearing (wild plots drop mushroom/herb_basil/grain_core)
- **Random spawn table**: mushroom (20), herb_basil (20), grain_core (20), herbal_dew (15), sour_essence (15), sweet_crystal (10) — max 10 simultaneous random items
- **Despawn**: Configurable timeout per item (default 300s for random, 120s for farm drops), checked every physics frame
- **Late-joiner sync**: `sync_all_to_client(peer_id)` sends bulk `_spawn_world_item_client` RPCs, called from `_sync_world_to_client()`
- **Persistence**: `get_save_data()` / `load_save_data()` integrated into `game_world.gd` save/load flow. Despawn times recalculated relative to current time on load.
- **Node naming**: `"WorldItem_" + str(uid)` with monotonic auto-increment UIDs to avoid duplicate name trap
- **Collision**: Area3D with `collision_layer=0`, `collision_mask=3` (detects players on layer 2). SphereShape3D radius=1.2 for pickup range.
- **HUD notification**: `hud.gd` `show_pickup_notification()` shows "Picked up [item] x[amount]" toast that fades out after 2.5s

## World Layout
- **Hub area**: Players spawn near (0, 1, 3). Farm zone at (25, 0, 0). Restaurant doors at z=12.
- **Decorative nodes** in `game_world.tscn` under GameWorld: `Paths` (17 ground path meshes), `Signposts` (6 posts with Label3D), `Trees` (40 tree meshes), `ZoneOverlays` (6 zone ground overlays with Label3D)
- **Trainer progression**: Optional trainers flank the main path south; gatekeepers block advancement to deeper zones

## Wild Encounter Zones
- 6 zones total: Herb Garden, Flame Kitchen, Frost Pantry, Harvest Field, Sour Springs, Fusion Kitchen
- Represented by glowing colored grass patches with floating in-world labels
- HUD provides persistent legend + contextual hint when inside encounter grass

## NPC Trainers
- 7 trainers placed along world paths under `Zones/Trainers` in game_world.tscn
- Color-coded by difficulty: green=easy, yellow=medium, red=hard
- Trainers: Sous Chef Pepper, Farmer Green, Pastry Chef Dulce, Brinemaster Vlad, Chef Umami, Head Chef Roux, Grand Chef Michelin

### Optional vs Gatekeeper Trainers
- **Optional trainers** (`is_gatekeeper=false`): Sous Chef Pepper, Farmer Green, Pastry Chef Dulce, Brinemaster Vlad, Grand Chef Michelin
  - Walking near shows "Press E to challenge [Name]!" on HUD via `_show_trainer_prompt` RPC
  - E-key triggers `request_challenge` RPC → server validates proximity + not-in-battle → starts trainer battle
  - Walking away hides prompt via `_hide_trainer_prompt` RPC (body_exited signal)
  - Rematch cooldown per trainer (`trainer.rematch_cooldown_sec`)
- **Gatekeeper trainers** (`is_gatekeeper=true`): Chef Umami, Head Chef Roux
  - Walking near triggers forced pushback + TrainerDialogueUI with Accept/Decline
  - Accept → `request_challenge` RPC → trainer battle
  - Decline → `_respond_gatekeeper_decline` RPC → teleports player south (gate_z + 6)
  - Defeating a gatekeeper: records `defeated_trainers[trainer_id] = timestamp` in player_data_store, calls `update_gate_for_peer()` → `_notify_gate_opened` RPC hides gate mesh/label on that client only
  - **Per-player gates**: Each player sees gates independently based on their own `defeated_trainers` dict. Bob sees a gate, Alice doesn't if she defeated it.
  - Gate visual: red translucent BoxMesh (8x2.5x0.5) + "Defeat X to Pass!" Label3D
  - Detection radius: 4.0 for gatekeepers, 3.0 for optional

### Trainer Authority Model
| Action | Authority | Sync |
|--------|-----------|------|
| Proximity detection | Server (Area3D body_entered/exited) | `_show/_hide_trainer_prompt` RPC to client |
| Challenge request | Client sends `request_challenge` RPC | Server validates, starts battle |
| Gatekeeper pushback | Server (velocity + teleport) | Position syncs via StateSync |
| Gatekeeper dialogue | Server triggers | `_show_gatekeeper_challenge` RPC to client |
| Gate open state | Server (defeated_trainers in player_data_store) | `_notify_gate_opened` RPC per-client |
| Decline pushback | Server (teleport to safe_pos) | Position syncs via StateSync |

## Restaurant System
- **Architecture**: Server-authoritative, per-player restaurant instances. Each player gets a unique restaurant with its own interior scene, farm plots, and kitchen crafting station.
- **Instance positioning**: Restaurants instanced at `Vector3(1000 + idx*200, 0, 1000)` — far from overworld to prevent collision. Index allocated via `allocate_restaurant_index()` and persisted in player save data.
- **Unique instance names**: `Restaurant_<owner_name>` set before `add_child()` on both server and client to prevent Godot auto-rename when multiple restaurants are loaded simultaneously.
- **Entry/exit flow**: Walk-over overworld door (Area3D) or E-key interaction → server saves overworld position → teleports player to restaurant interior → `_notify_location_change` RPC → client instantiates scene locally. Exit via ExitDoor `body_entered` → server restores overworld position (offset if too close to door row to prevent re-entry).
- **Exit cooldown**: 1s debounce (`_exit_cooldown` dict) prevents immediate re-entry after exit teleport.
- **Farm routing**: `get_farm_manager_for_peer(peer_id)` checks `player_location` dict — returns restaurant's FarmManager if player is inside one, otherwise returns overworld FarmManager.
- **Bulk farm sync**: `_receive_restaurant_farm_data` RPC sends all plot states at once (not per-plot RPCs) to avoid node path mismatch when client hasn't finished instantiating.
- **Persistence**: Restaurant index map saved in world data. Individual restaurant farm plots saved to owner's `player_data_store["restaurant"]` on unload and auto-save. RestaurantManager data restored from world save on server start.
- **Door replication**: Server creates Area3D doors with collision (for walk-over detection). `_spawn_door_client` RPC creates visual-only doors (mesh + label, no collision) on all clients. `_remove_door_client` RPC removes on disconnect. Late-joiners receive all existing doors via `sync_doors_to_client()`.
- **Auto-save position fix**: `save_manager.gd` and `network_manager.gd` both check `RestaurantManager.overworld_positions[peer_id]` before falling back to `player_node.position` — prevents saving interior coordinates (~1000+) as the player's overworld position.
- **Unloading**: When all players leave a restaurant, `_try_unload_restaurant()` saves farm data and `queue_free()`s the instance. Re-entering creates a fresh instance from saved data.
- **Files**: `scripts/world/restaurant_manager.gd`, `scripts/world/restaurant_interior.gd`, `scripts/world/restaurant_door.gd`, `scenes/world/restaurant_interior.tscn`

## Networking Rules (IMPORTANT)

This is a server-authoritative multiplayer game. **Every gameplay change — new feature, new action, new resource, any UI that affects game state — must be evaluated for networking impact.** If the user does not specify whether a change should be networked, always ask before implementing.

### Questions to resolve before writing code
- Should this run on **server only**, **client only**, or **both**?
- Does the server need to **validate/authorize** this action? (Almost always yes for anything that changes player data, inventory, party, or world state.)
- Do other clients need to **see the result**? If so, how is it synced — RPC, MultiplayerSynchronizer property, or MultiplayerSpawner?
- Is there a **race condition** if the client optimistically updates before the server confirms?

### Authority model
| System | Authority | Sync mechanism |
|--------|-----------|---------------|
| Player movement | Server (`_physics_process`) | StateSync (position, velocity) |
| Player rotation | Server (`_physics_process`) | StateSync (`mesh_rotation_y`) |
| Player visuals (color, name) | Server (set before spawn) | StateSync (spawn-only) |
| Camera / input | Client (InputSync) | InputSync → server reads |
| Inventory changes | Server (`server_add/remove_inventory`) | RPC to client (`_sync_inventory_remove`, `_grant_harvest`) |
| Watering can | Server (`server_use/refill_watering_can`) | RPC to client (`_sync_watering_can`, `_receive_refill`) |
| Farm actions (plant/water/harvest/till) | Server (`request_farm_action` RPC) | Server validates, then RPC result to client |
| Battle state | Server (BattleManager) | RPCs to involved clients |
| Crafting | Server (`request_craft` single-phase) | RPC results + inventory sync to client |
| Food/buffs | Server (`request_use_food`) | `_sync_active_buffs` RPC to client |
| Tool equip | Server (`request_equip_tool`) | `_sync_equipped_tools` RPC to client |
| Held item equip | Server (`request_equip/unequip_held_item`) | `_sync_party_full` RPC to client |
| Recipe unlocks | Server (`request_use_recipe_scroll`) | `_sync_known_recipes` + `_notify_recipe_unlocked` RPCs |
| Selling | Server (`request_sell_item`) | Inventory + money sync RPCs |
| World item spawn/pickup | Server (WorldItemManager) | `_spawn/_despawn_world_item_client` RPCs to all |
| Restaurant entry/exit | Server (RestaurantManager) | `_notify_location_change` RPC + client-side scene instantiation |
| Restaurant doors | Server (collision) + Client (visual) | `_spawn/_remove_door_client` RPCs to all |
| Trainer proximity prompt | Server (Area3D detect) | `_show/_hide_trainer_prompt` RPC to client HUD |
| Gatekeeper challenge | Server (Area3D + pushback) | `_show_gatekeeper_challenge` RPC to client TrainerDialogueUI |
| Gate open/close | Server (`defeated_trainers` in player_data_store) | `_notify_gate_opened` RPC per-client |
| Save/load | Server only (SaveManager) | Data sent to client via `_receive_player_data` |

### Never do this
- **Never deduct resources client-side before server confirms.** Always let the server deduct first, then sync to client via RPC. The old planting flow had this bug — client removed seed, then told server, creating desync on disconnect.
- **Never assume a gameplay feature is local-only** unless explicitly told so. Even "cosmetic" things like player color need syncing in multiplayer.
- **Never modify `PlayerData` (the autoload) on the server.** `PlayerData` is the client's local mirror. The server uses `NetworkManager.player_data_store[peer_id]`. Sync changes from server store to client PlayerData via RPC.

## GDScript Conventions
- Use `class_name` for static utility classes (BattleCalculator, StatusEffects, FieldEffects, AbilityEffects, HeldItemEffects, BattleAI)
- Do NOT preload scripts that already have `class_name` — causes "constant has same name as global class" warning
- Prefix unused parameters/variables with `_` to suppress warnings
- Use `4.0` instead of `4` in division to avoid integer division warnings

## Export Build Gotchas
- **DataRegistry .tres/.remap handling**: Godot exports convert `.tres` files to `.tres.remap` (binary format with remap indirection). Any code using `DirAccess` to scan for resources must check `.tres`, `.res`, AND `.remap` extensions — otherwise the exported build loads zero resources while the editor build works fine.
- **Battle stacking prevention**: All encounter/battle entry points (TallGrass, EncounterManager, TrainerNPC) must check `BattleManager.player_battle_map` before starting a new battle. The `active_encounters` dict in EncounterManager only tracks wild encounters, NOT trainer/PvP battles. Client-side `start_battle_client()` also guards against duplicate `_start_battle_client` RPCs.
- **stdbuf for Docker logs**: Godot headless buffers stdout, making `docker logs` empty. The Dockerfile uses `stdbuf -oL` in the CMD to force line-buffered output.
- **Duplicate node name trap**: If a .tscn file already has a child named "X", creating a new `Node("X")` in `_ready()` and calling `add_child()` causes Godot to silently rename it (e.g. `@Node@38`). This breaks all hardcoded path lookups like `/root/Main/GameWorld/UI/BattleUI`. Always use `get_node("X")` to reference existing nodes, don't create duplicates.
- **CanvasLayer child visibility persistence**: If you hide all children of a CanvasLayer (e.g. for a summary overlay), you MUST restore their visibility when the next screen/battle starts. Setting the CanvasLayer's own `visible` property does not propagate to children. The `_on_battle_started()` handler restores all child visibility and cleans up leftover dynamically-created panels.
- **MCP addon excluded from server export**: `export_presets.cfg` has `exclude_filter="addons/mechanical_turk_mcp/*"` on the Linux Server preset. The runtime bridge autoload entry in `project.godot` still exists (needed for editor), so server logs show a non-fatal "File not found" error for `runtime_bridge.gd` on startup — this is expected.
- **Connection timeout**: ConnectUI has a 10-second timeout. If ENet connects at transport layer but the Godot multiplayer layer rejects the peer (e.g. engine version mismatch), the client shows "Connection timed out" instead of hanging forever.

## Kubernetes Deployment
- **Namespace**: `godot-multiplayer` (shared with other multiplayer game servers)
- **Image**: `ghcr.io/crankymagician/mt-creature-crafting-server:latest`
- **Public endpoint**: `207.32.216.76:7777` (UDP) — NodePort 7777 → container 7777.
- **Internal/VPN endpoint**: `10.225.0.153:7777`.
- **Node SSH access**: `ssh jayhawk@10.225.0.153` (password: `fir3W0rks!`). User has sudo. k3s config at `/etc/rancher/k3s/config.yaml`. NodePort range: `7000-32767`.
- **Persistent storage**: 1Gi PVC (`creature-crafting-data`) mounted at `/app/data` for player/world saves
- **Deploy strategy**: `Recreate` (RWO PVC can't be shared during rolling update)
- **MCP config**: `.claude/mcp.json` provides both Godot and Kubernetes MCP servers
- **K8s MCP**: Uses `blazar-kubernetes-mcp/run-mcp.sh` with `K8S_NAMESPACE=godot-multiplayer`
- **RBAC**: Service account `mcp-admin` in `godot-multiplayer` namespace (configured in `blazar-kubernetes-mcp/k8s/rbac-setup.yaml`)

### K8s Deploy Workflow
```bash
./scripts/deploy-k8s.sh --setup      # first-time: namespace + ghcr-secret + RBAC
./scripts/deploy-k8s.sh              # full build + push + deploy (auto-builds engine if missing)
./scripts/deploy-k8s.sh --skip-build # redeploy without rebuilding image
./scripts/build-engine-templates.sh          # build engine only (cached)
./scripts/build-engine-templates.sh --force  # rebuild engine from scratch
```

## MCP Testing Workflow

### Editor-only bridge (single process)
- MCP bridge by default communicates with the editor process on port 9080, NOT the running game
- `batch_scene_operations` creates wrong node types — write .tscn files directly instead
- **To test server-side logic via MCP**: add temporary test code to `connect_ui.gd` `_ready()`, call `NetworkManager.host_game()`, run tests synchronously (no `await`), then check `get_debug_output`. Revert the test code afterward.
- **IMPORTANT**: Do NOT call `GameManager.start_game()` before your test code finishes — it frees ConnectUI via `queue_free`, killing any running coroutine. Run all assertions before `start_game()`.

### Runtime bridge — MCP multiplayer session (preferred)
- **Use `run_multiplayer_session` MCP tool** for multi-instance testing. It launches 1 server + N clients, each with a unique runtime bridge port, all managed by MCP.
- Pass `serverArgs: ["--server"]` so the server instance auto-starts without ConnectUI.
- Pass `numClients: 2` (or more) for client instances.
- Target instances with `target: "runtime:server"`, `target: "runtime:client_1"`, `target: "runtime:client_2"`, etc.
- **Lifecycle**: `stop_all_instances` to stop everything, `list_instances` to see running PIDs/ports.
- **Client join via GDScript**: Use `execute_gdscript` with `target: "runtime:client_N"` to call `NetworkManager.join_game("127.0.0.1", "PlayerName")` directly (more reliable than emitting button signals or mouse clicks).
- **Screenshot caching**: MCP screenshot tool may cache results — use `get_scene_tree` or `execute_gdscript` for reliable state verification.

### Runtime bridge — manual setup (alternative)
- The runtime bridge plugin enables `execute_gdscript`, `capture_screenshot`, `send_input_event`, and `send_action` on **running game processes**
- Each instance uses a different bridge port via `-- --bridge-port=NNNN` CLI arg
- **Headless server**: `'/Applications/Mechanical Turk.app/Contents/MacOS/Mechanical Turk' --path <project> --headless -- --bridge-port=9082`
- **Client 1**: launched via `run_project` MCP tool (uses default bridge port 9081)
- **Client 2**: launched manually with `-- --bridge-port=9083`

### Runtime bridge caveats
- **GDScript injection caveats**: runtime errors in injected scripts trigger the Godot debugger break, freezing the entire process. All subsequent MCP calls will timeout. Requires killing and restarting the process. GDScript has no try/catch.
- **Screenshot size**: use small resolutions (400x300) to avoid WebSocket `ERR_OUT_OF_MEMORY` on large images
- **PvP testing**: players must be within 5 units for challenge flow. Move them on server via `nm._get_player_node(peer_id).position = Vector3(...)`. PvP has 30s turn timeout — act quickly or increase temporarily.
- **Battle dict access via MCP**: Battle state is a Dictionary (not an object). Use `bm.battles` (not `active_battles`), `battle.get("side_b_party")`, creature HP key is `"hp"` (not `"current_hp"`). The `request_battle_action` RPC takes `(action_type, action_data)` where action_data for moves is the **move ID string** (e.g. `"grain_bash"`), NOT an index.
- **Force-winning battles via MCP**: Set all enemy party creatures' `"hp"` to 1 (active) and 0 (rest) via dict access, then submit a move RPC from the client. Do NOT use `_end_battle_full()` — it bypasses trainer reward flow (defeated_trainers, XP, drops, gate opening).
- **Area3D re-detection**: Teleporting a player directly into an Area3D zone may not trigger `body_entered` if the physics engine doesn't detect the transition. Move the player far away first, then back, to guarantee signal fires.

### Port conflicts
- If `host_game()` returns error 20 (ERR_CANT_CREATE), check `lsof -i :7777` — a Docker container or previous server may be holding the port. Stop it with `docker compose down` first.
- Check bridge ports: `lsof -i :9081 -i :9082 -i :9083`

## File Structure Overview
- `scripts/autoload/` — NetworkManager, GameManager, PlayerData, SaveManager
- `scripts/data/` — 13 Resource class definitions (+ food_def, tool_def, recipe_scroll_def)
- `scripts/battle/` — BattleManager, BattleCalculator, StatusEffects, FieldEffects, AbilityEffects, HeldItemEffects, BattleAI
- `scripts/world/` — FarmPlot, FarmManager, SeasonManager, TallGrass, EncounterManager, GameWorld, TrainerNPC, CraftingStation, RecipePickup, WorldItem, WorldItemManager, RestaurantManager, RestaurantInterior, RestaurantDoor
- `scripts/crafting/` — CraftingSystem
- `scripts/player/` — PlayerController, PlayerInteraction
- `scripts/ui/` — ConnectUI, HUD (trainer prompt label), BattleUI, CraftingUI (station-filtered), InventoryUI (tabbed), PartyUI (networked equip), PvPChallengeUI, TrainerDialogueUI (gatekeeper accept/decline + post-battle dialogue)
- `resources/` — ingredients/ (16), creatures/ (18), moves/ (42), encounters/ (6), recipes/ (46), abilities/ (18), held_items/ (12), trainers/ (7), foods/ (12), tools/ (12), recipe_scrolls/ (13)
