# Testing Guide

## Run Commands
```bash
# GDScript tests (GUT) — 533 tests
'/Applications/Mechanical Turk.app/Contents/MacOS/Mechanical Turk' --path . --headless -s addons/gut/gut_cmdln.gd -gexit

# Express API tests (Vitest) — 21 tests
cd api && npx vitest run
```

## GDScript Test Suite (GUT 9.5.0)
- **Config**: `.gutconfig.json` — dirs `res://test/`, prefix `test_`, include subdirs
- **Helpers** (`test/helpers/`): `mock_move.gd` (MoveDef factory), `battle_factory.gd` (creature/battle dict factory), `registry_seeder.gd` (DataRegistry populator), `battle_test_scene.gd` (integration helper)
- **Unit tests** (`test/unit/`): battle/ (calculator, status, field effects, abilities, held items, AI, calculator RNG, battle items), data/ (creature instance, creature creation, battle item def, stat tracker), world/ (season manager, shop system, social system, location system, calendar events, quest system), ui/ (compass math), crafting/ (validation)
- **Integration tests** (`test/integration/`): battle turn pipeline, PvP mechanics, player trading, social flow, quest flow

## Test Patterns
- **RegistrySeeder**: Populates DataRegistry directly (sets `_loaded = true`). Call `seed_all()` in `before_each()`, `clear_all()` in `after_each()`.
- **BattleFactory**: `creature(overrides)` and `battle(overrides)` create dicts with all expected battle keys + sensible defaults.
- **MockMove**: `physical()`, `special()`, `status()`, `with_props(overrides)` create MoveDef Resources without DataRegistry.
- **Deterministic RNG**: Use `seed(N)` for reproducible randf/randi results in tests.
- **No preloading**: Reference `class_name` utilities directly (BattleCalculator, StatusEffects, etc.) — never preload in tests.
- **SeasonManager testing**: Load script onto standalone Node, set state directly, don't add to tree (avoids multiplayer _ready).

## API Tests (Vitest + Supertest + MongoMemoryServer)
- **App extraction**: `api/src/app.ts` exports `createApp(db)` for Supertest without real listener.
- **Setup**: `api/test/setup.ts` — `setupTestDb()` / `teardownTestDb()` / `clearCollections()`
- **Test files**: `players.test.ts` (14 tests), `world.test.ts` (6 tests), `health.test.ts` (1 test)

## When Adding New Features
- **New battle mechanic** (move effect, ability, held item): Add tests to the relevant `test/unit/battle/` file. Update `registry_seeder.gd` if new data entries are needed.
- **New data type or resource**: Add serialization round-trip tests in `test/unit/data/`.
- **New API endpoint**: Add tests in `api/test/`. Use the existing `setupTestDb()` pattern.
- **New creature receipt source** (e.g., quests, events): Call `NetworkManager.server_give_creature(peer_id, creature_data, "source_type", "source_id")`. Handles party-full auto-prompting via CreatureDestinationUI.
- **P2P creature trade**: Test offer/pref/confirmation/execution flow. Validate min-party guard, storage capacity, creature UUID resolution in `_resolve_trade_creature`.
- **NPC creature trade**: Test prerequisite checks (friendship, season, one-time) via `_get_available_creature_trade`. Test cost deduction and creature creation in `_handle_creature_trade_accept`.
- **Friend/party feature**: Test both online and offline players. Use SaveManager signal-based async patterns for offline lookups. Guard against race conditions with pair-locks.
- **Run tests before committing**: All tests must pass.

## File Structure Overview
- `api/` — Express API service (TypeScript): `src/index.ts`, `src/routes/players.ts`, `src/routes/world.ts`, `Dockerfile`
- `k8s/` — Kubernetes manifests: `mongodb.yaml`, `api-service.yaml`, `deployment.yaml`, `service.yaml`
- `scripts/autoload/` — NetworkManager, GameManager, PlayerData, SaveManager
- `scripts/data/` — 20 Resource/utility class definitions (+ food_def, tool_def, recipe_scroll_def, battle_item_def, shop_def, npc_def, location_def, calendar_events, quest_def, stat_tracker)
- `scripts/battle/` — BattleManager, BattleCalculator, StatusEffects, FieldEffects, AbilityEffects, HeldItemEffects, BattleAI
- `scripts/world/` — FarmPlot, FarmManager, SeasonManager, TallGrass, EncounterManager, GameWorld, TrainerNPC, CraftingStation, RecipePickup, WorldItem, WorldItemManager, RestaurantManager, RestaurantInterior, RestaurantDoor, ShopNPC, SocialNPC, SocialManager, LocationManager, CalendarBoard, QuestManager, FriendManager
- `scripts/crafting/` — CraftingSystem
- `scripts/player/` — PlayerController, PlayerInteraction
- `scripts/ui/` — ConnectUI, HUD, BattleUI, CraftingUI, InventoryUI, PartyUI, PvPChallengeUI, TrainerDialogueUI, ShopUI, TradeUI, DialogueUI, CompassUI, MinimapUI, PauseOverlay, CalendarUI, QuestLogUI, CompendiumUI, CreatureDestinationUI
- `test/helpers/` — MockMove, BattleFactory, RegistrySeeder, BattleTestScene
- `test/unit/` — battle/, data/, world/, ui/, crafting/
- `test/integration/` — battle_turn, battle_pvp, player_trading, social_flow, quest_flow
- `api/test/` — players.test.ts, world.test.ts, health.test.ts
- `resources/` — ingredients/ (16), creatures/ (21), moves/ (57), encounters/ (6), recipes/ (58), abilities/ (20), held_items/ (18), trainers/ (7), foods/ (12), tools/ (12), recipe_scrolls/ (13), battle_items/ (6), shops/ (3), npcs/ (5), locations/ (28), quests/ (6)
