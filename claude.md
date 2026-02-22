# Claude Notes

## Product Docs
- `docs/game-pillars-theme.md` — Core fantasy, pillars, tone, and inspirations (Stardew Valley, Harvest Moon, Pokemon, low-poly, kawaii).
- `docs/demo-plan.md` — Target demo scope with Done/To Do status.

## Project Runtime Defaults
- Multiplayer default port: `7777` (UDP).
- **Smart IP defaults**: In editor, ConnectUI defaults to `127.0.0.1` (localhost). In exported builds, defaults to `207.32.216.76` (public server). Editor mode ignores saved prefs for IP to prevent stale overrides.
- **Dedicated server detection** (3 triggers, checked in `NetworkManager._ready()`):
  1. `DisplayServer.get_name() == "headless"` — Docker/headless export
  2. `OS.has_feature("dedicated_server")` — Godot dedicated server export
  3. `--server` or `--role=server` in `OS.get_cmdline_user_args()` — CLI flags (MCP `run_multiplayer_session` auto-passes `--role=server`)
- When dedicated mode is detected: auto-calls `host_game("Server")` + `GameManager.start_game()`, skips ConnectUI entirely, skips game world UI setup (HUD, BattleUI, etc.) and camera creation.

## Persistence Architecture (MongoDB + Express API)
- Server→Express API(:3000)→MongoDB(:27017). Clients get data via RPCs only. Editor dev: SaveManager auto-falls back to file I/O.
- **UUID Rule (CRITICAL)**: Every persistent entity MUST have a stable UUID. New entity types need a UUID field generated server-side. Use `creature_id` (not party index) for cross-references.
- **SaveManager**: `save_player(data)` → PUT, `load_player_async(name)` → GET, `create_player_async(data)` → POST (API generates UUID).
- **Ingredient renames**: 8 old fantasy IDs auto-migrated via `INGREDIENT_RENAMES` dict in `network_manager.gd`. To add new renames, just add to the dict.

See `docs/persistence.md` for full details: UUID table, Express API endpoints, join flow, Docker Compose, ingredient rename table.

## Docker Server Build
See `docs/docker-build.md` for full build instructions (two-phase engine + game build, SCons flags, local dev).

## New Player Defaults
- **Normal players**: Start with 4 basic tools, $0, 1 Rice Ball starter, no recipes.
- **First login**: `appearance` has `needs_customization: true` → character creator opens (can't dismiss). Mannequin shown until customization completes.

## Multiplayer Join/Spawn Stabilization
- **Client pre-loads GameWorld on connect**: `_on_connected_to_server()` calls `GameManager.start_game()` BEFORE `request_join`. This ensures the MultiplayerSpawner exists before spawn replication RPCs arrive.
- **Name uniqueness**: `active_player_names` dict (name → peer_id) rejects duplicate online names. `_join_rejected` RPC tells client why.
- Spawn waits for client world path readiness (`/root/Main/GameWorld/Players/MultiplayerSpawner`).
- Server tracks temporary join state and times out peers that never become ready.
- **New player spread spawn**: Players with no saved position spawn in a golden-angle circle (radius 2, center 0,0,3) to avoid overlap.

## Player/Camera Notes
- Player movement uses server authority with replicated input.
- Camera defaults to over-the-shoulder and captures mouse during world control. Mouse made visible during battle UI and recaptured after.
- **Server has no camera or UI** — `game_world.gd` `_ready()` skips `_setup_ui()` and `_ensure_fallback_camera()` on the server.
- **Player collision layers**: Players use `collision_layer=2`, `collision_mask=1`. TallGrass and TrainerNPC Area3Ds set `collision_mask=3` (bits 1+2) to detect players.
- **UI node sharing**: `_setup_ui()` adds HUD, BattleUI, CraftingUI, InventoryUI, PartyUI to the **existing** `$UI` node from `game_world.tscn`. Do NOT create a new "UI" node — Godot will rename it, breaking path lookups.
- **Player visuals** (color, nameplate): set on the player node server-side **before** `add_child()` in `_spawn_player()`, synced via StateSync spawn-only mode.
- **StateSync properties** (9 total): `position`, `velocity` (always), `player_color`, `player_name_display` (spawn-only), `mesh_rotation_y` (always), `is_busy` (always), `movement_state` (always), `anim_move_speed` (always), `anim_action` (always).
- **Character vibration/clipping (DO NOT REVERT)**: `_update_crouch_collision()` in `player_controller.gd` (line ~578) runs every physics frame and lerps BOTH `capsule.height` AND `collision_shape.position.y` (= height/2.0). Without the Y position adjustment, the capsule bottom lifts off the floor → `is_on_floor()` returns false → gravity pulls down → oscillation loop. This affects both crouching AND walking if the collision shape Y drifts. The radius also scales: `clamp(height / 3.6, 0.28, 0.5)`. Scene defaults: height=1.8, radius=0.5, CollisionShape3D y=0.9.

## Animation System
- **Architecture**: AnimationTree as standalone AnimationMixer (NOT paired with separate AnimationPlayer). 260 UAL animations. Track paths: `Armature/Skeleton3D:bone_name` (no remapping needed).
- **Sync**: Server sets `movement_state`, `anim_move_speed`, `anim_action` via StateSync. Clients drive AnimationTree locally.
- **Key files**: `player_controller.gd` (`_build_animation_tree()`, `_update_animation_tree()`), `tools/build_animation_library.gd`
- **Re-build**: `'/Applications/Mechanical Turk.app/Contents/MacOS/Mechanical Turk' --path . --script tools/build_animation_library.gd`

See `docs/animation-system.md` for full details: blend tree, locomotion mapping, tool action mapping, loop modes.

## Character Customization System
- **Key classes**: `CharacterAppearance` (Resource), `CharacterPartRegistry` (static scanner), `CharacterAssembler` (static builder). Falls back to UAL mannequin.
- **Player**: No hardcoded model — built dynamically. `appearance_data` synced via StateSync (spawn-only). Server sets before `add_child()`.
- **Network**: `request_update_appearance(dict)` → server validates → `_sync_appearance` broadcast. `update_appearance()` rebuilds model + anim tree.

See `docs/character-system.md` for full details: asset pipeline, bone remap, first-login flow, NPC integration, creator UI.

## Battle System
- **3 modes**: Wild, Trainer (7 NPCs), PvP (V key, 5 units). MAX_PARTY_SIZE = 3. Starter: Rice Ball (Grain, Lv 5).
- **Server-authoritative**: `_build_party_from_store(peer_id)` reads from `player_data_store`, NOT client. Move validation in `request_battle_action()`.
- **PvP**: Simultaneous turns, 30s timeout, disconnect = forfeit. Loser forfeits 25% ingredients.
- **Defeat**: 50% money loss, teleport to spawn, creatures healed.

See `docs/battle-system.md` for full details: IVs, bond levels, crit stages, MoveDef properties, battle UI, items, XP/leveling.

## Crafting & Item System
- **3 stations**: Kitchen (restaurant), Workbench (near spawn), Cauldron (deep wild). 67 recipes, 6 item types.
- **Security**: Single-phase server-authoritative — `request_craft(recipe_id)` validates, deducts, produces, syncs.

See `docs/crafting-items.md` for full details: recipes, buffs, tool upgrades, farming, selling, ingredients.

## World Systems
- **Hub**: Spawn (0,1,3), farm zone (25,0,0), restaurant doors z=12. 6 encounter zones, 7 trainers.
- **Busy state**: `is_busy: bool` on player, StateSync always mode. Guards encounters, PvP, trainers, shop, trade.

See `docs/world-systems.md` for full details: trainers, world items, restaurant, shops, trading.

## NPC Social System
- **Friendship**: -100 to +100, 5 tiers. SocialManager (no `class_name`). NPC creature trades data-driven via `npc_def.creature_trades`.

See `docs/social-quests.md` for full details.

## Creature Destination Chooser
- **Universal entry point**: `server_give_creature(peer_id, creature_data, source_type, source_id)` handles ALL creature receipts (crafting, NPC trade, P2P trade, battle catches)
- **Party has space**: Creature added directly to party, `_notify_creature_received` RPC
- **Party full**: Stores in `pending_creature_choices[peer_id]`, sends `_show_creature_destination_chooser` RPC
- **CreatureDestinationUI**: CanvasLayer modal with 3 options: Send to Storage, Swap with party member, Release (creature lost)
- **RPC**: `request_creature_destination(choice, swap_party_idx)` — validates bounds, min-party, storage capacity

## Friend & Party System
- **FriendManager**: No `class_name`, child of GameWorld. Server-authoritative with pair-locks. 4-player parties, 60s invite TTL.
- **MCP testing**: Call `_process_friend_request`, `_do_accept_friend`, `_process_block` directly (bypasses `get_remote_sender_id()`).

See `docs/friend-party-system.md` for full details: data model, RPCs, offline mutations, blocking.

## Quest System
- **Data-driven**: QuestDef Resource, QuestManager (server-authoritative, no `class_name`). Daily/weekly auto-reset.
- **Player state**: `player_data_store[peer_id]["quests"]` = `{active, completed, daily_reset_day, weekly_reset_day, unlock_flags}`

See `docs/social-quests.md` for full details: objectives, rewards, quest chains, prereqs, exploit prevention.

## Excursion System
- **Party-gated procedural zones**: 80x80 terrain, 15-minute timer, per-party isolated instances. Shared loot to all members.
- **ExcursionManager** (no `class_name`), **ExcursionGenerator** (`class_name`, static). Deterministic terrain from seed + season.

See `docs/excursion-system.md` for full details: entry validation, harvestables, dig spots, late-join, encounter tables.

## Networking Rules (IMPORTANT)

This is a server-authoritative multiplayer game. **Every gameplay change must be evaluated for networking impact.** If the user does not specify whether a change should be networked, always ask before implementing.

### Questions to resolve before writing code
- Should this run on **server only**, **client only**, or **both**?
- Does the server need to **validate/authorize** this action? (Almost always yes for state changes.)
- Do other clients need to **see the result**? If so, how — RPC, StateSync, or MultiplayerSpawner?
- Is there a **race condition** if the client optimistically updates before the server confirms?

### Authority model (non-obvious entries)
| System | Authority | Sync mechanism |
|--------|-----------|---------------|
| Player movement/rotation | Server (`_physics_process`) | StateSync (position, velocity, mesh_rotation_y) |
| Player visuals (color, name) | Server (set before spawn) | StateSync (spawn-only) |
| Inventory changes | Server (`server_add/remove_inventory`) | RPC to client |
| Farm actions | Server (`request_farm_action` RPC) | Server validates, then RPC result to client |
| Battle state | Server (BattleManager) | RPCs to involved clients |
| Crafting | Server (`request_craft` single-phase) | RPC results + inventory sync to client |
| World item spawn/pickup | Server (WorldItemManager) | `_spawn/_despawn_world_item_client` RPCs to all |
| Character appearance | Server (`request_update_appearance` RPC) | StateSync spawn-only + `_sync_appearance` RPC |
| Save/load | Server only (SaveManager → API → MongoDB) | `_receive_player_data` RPC |

All other systems follow the same pattern: server-authoritative with RPC sync. See full table in git history if needed.

### Never do this
- **Never deduct resources client-side before server confirms.** Always let the server deduct first, then sync to client via RPC. The old planting flow had this bug — client removed seed, then told server, creating desync on disconnect.
- **Never assume a gameplay feature is local-only** unless explicitly told so. Even "cosmetic" things like player color need syncing in multiplayer.
- **Never modify `PlayerData` (the autoload) on the server.** `PlayerData` is the client's local mirror. The server uses `NetworkManager.player_data_store[peer_id]`. Sync changes from server store to client PlayerData via RPC.

## Location, Compass & Calendar
- **Calendar**: 12 months, 28 days/month, 336 days/year, start March. `DAY_DURATION = 600.0` (10 min). Seasons: Mar-May=spring, Jun-Aug=summer, Sep-Nov=autumn, Dec-Feb=winter.
- **Sync**: `_broadcast_time(year, month, day, total_days, weather)` RPC. Late-joiners: `request_season_sync`.

See `docs/location-calendar.md` for full details: locations, compass, minimap, weather, calendar events.

## Compendium & Stat Tracking
- **StatTracker** (`class_name`, static `_store` via `init(player_data_store)` in NetworkManager._ready()). ~30 stats + compendium (items, creatures_seen, creatures_owned).
- **Sync**: `request_compendium_sync.rpc_id(1)` → `_sync_compendium_client(stats, compendium)`

See `docs/compendium-stats.md` for full details.

## Audio System
- **AudioManager**: Client-only singleton. Server guard on every public method. No networking impact.

See `docs/audio-system.md` for full details: 6-bus layout, SFX registry, music contexts, ambience layers, adding audio.

## UI Theme & Accessibility
- **CRITICAL**: All UI code MUST use `UITheme.scaled(UITokens.FONT_*)` — never raw `UITokens.FONT_*` for runtime font sizes. Label3D also uses `UITheme.scaled()`.
- **UITheme** (`class_name`): semantic styling API, font loading, `create_item_icon(info, base_size)`.
- **4 font scale steps**: Small (0.85), Normal (1.0), Large (1.15), Extra Large (1.3)

See `docs/ui-accessibility.md` for full details.

## Icon System
- **Pre-baked** 256x256 PNGs via `tools/bake_icons_cli.gd`. All item defs have `@export var icon_texture: Texture2D`.
- **UI helper**: `UITheme.create_item_icon(info, base_size)` — TextureRect if texture exists, falls back to ColorRect.
- **Re-bake**: `'/Applications/Mechanical Turk.app/Contents/MacOS/Mechanical Turk' --path . --script tools/bake_icons_cli.gd`

## GDScript Conventions
- Use `class_name` for static utility classes (BattleCalculator, StatusEffects, FieldEffects, AbilityEffects, HeldItemEffects, BattleAI, StatTracker)
- Do NOT preload scripts that already have `class_name` — causes "constant has same name as global class" warning
- Prefix unused parameters/variables with `_` to suppress warnings
- Use `4.0` instead of `4` in division to avoid integer division warnings

## Export Build Gotchas
- **DataRegistry .tres/.remap handling**: Godot exports convert `.tres` to `.tres.remap`. Any code using `DirAccess` to scan for resources must check `.tres`, `.res`, AND `.remap` extensions.
- **Battle stacking prevention**: All encounter/battle entry points must check `BattleManager.player_battle_map` before starting a new battle. Client-side `start_battle_client()` also guards against duplicate RPCs.
- **stdbuf for Docker logs**: Godot headless buffers stdout. Dockerfile uses `stdbuf -oL` for line-buffered output.
- **Duplicate node name trap**: If a .tscn already has child "X", creating a new `Node("X")` + `add_child()` causes silent rename. Always use `get_node("X")` for existing nodes.
- **CanvasLayer child visibility**: CanvasLayer's `visible = false` does NOT propagate to child Controls — they still report `visible = true`. When checking if a CanvasLayer-based UI is open, always check the CanvasLayer's own `.visible` first. Hiding children requires explicit restore on next use. `_on_battle_started()` restores all children.
- **MCP addon excluded from server export**: `export_presets.cfg` has `exclude_filter="addons/mechanical_turk_mcp/*"`. Non-fatal "File not found" on startup is expected.
- **Connection timeout**: ConnectUI has a 10-second timeout for transport-connected but multiplayer-rejected peers.

## Kubernetes Deployment
See `docs/k8s-deployment.md` for full K8s deployment details (3 deployments, SSH access, deploy workflow, manifests).

## Automated Testing
See `docs/testing-guide.md` for full test suite details.

### Run Commands
```bash
# GDScript tests (GUT)
'/Applications/Mechanical Turk.app/Contents/MacOS/Mechanical Turk' --path . --headless -s addons/gut/gut_cmdln.gd -gexit

# Express API tests (Vitest)
cd api && npx vitest run
```

### Test Patterns
- **RegistrySeeder**: `seed_all()` in `before_each()`, `clear_all()` in `after_each()`
- **BattleFactory**: `creature(overrides)` and `battle(overrides)` with sensible defaults
- **MockMove**: `physical()`, `special()`, `status()`, `with_props(overrides)`
- **Deterministic RNG**: Use `seed(N)` for reproducible results
- **Run tests before committing**: All tests must pass.

## MCP Testing Workflow
See `docs/mcp-testing.md` for full MCP testing guide (editor bridge, runtime bridge sessions, caveats, port conflicts).
