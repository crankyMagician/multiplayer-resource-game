# Compendium & Stat Tracking System Details

## StatTracker
- **StatTracker** (`scripts/data/stat_tracker.gd`): `class_name` static utility for all stat/compendium tracking. Uses `static var _store` initialized via `StatTracker.init(player_data_store)` in NetworkManager._ready().
- **Data model**: Two keys in `player_data_store[peer_id]`: `"stats"` (flat dict of integer counters + per-species sub-dicts) and `"compendium"` (arrays: `items`, `creatures_seen`, `creatures_owned`).

## Tracked Stats (~30)
battles_fought/won/lost, wild/trainer/pvp battle counts, pvp_wins/losses, creatures_fainted, player_defeats, total_xp_gained, per-species encounters/catches/evolutions, money_earned/spent, items_crafted/sold/bought, trades_completed, gifts_given, npc_conversations, quests_completed_{category}, crops_planted/harvested, locations_discovered, days_played.

## Compendium Unlocks
- Items unlock on first obtain (`server_add_inventory`)
- Creatures marked "seen" on battle encounter, "owned" on craft/catch

## Hook Integration
StatTracker calls in: battle_manager.gd (~15 hooks), network_manager.gd (inventory/money/buy/sell/trade), crafting_system.gd, farm_manager.gd, social_manager.gd, quest_manager.gd, location_manager.gd, season_manager.gd.

## Sync
- On-demand: Client opens UI -> `request_compendium_sync.rpc_id(1)` -> server sends `_sync_compendium_client(stats, compendium)` -> client stores in PlayerData.

## CompendiumUI
- `scripts/ui/compendium_ui.gd`: CanvasLayer (layer 10), K key toggle
- 3 tabs: Items (7 sub-filters, locked=??? grey, unlocked=colored), Creatures (unknown/seen/owned states with stats), Stats (categorized rows with species breakdown)

## PlayerData Additions
`stats: Dictionary`, `compendium: Dictionary`, signals `stats_changed()`, `compendium_changed()`.

## Files
`scripts/data/stat_tracker.gd`, `scripts/ui/compendium_ui.gd`, `scenes/ui/compendium_ui.tscn`, `test/unit/data/test_stat_tracker.gd`
