# Compendium & Stat Tracking System

## Overview

The Compendium & Stat Tracking system provides per-player persistent tracking of gameplay statistics and a discoverable item/creature encyclopedia. All data is server-authoritative, persisted via the save system (MongoDB in production, file I/O in editor), and synced to clients on-demand.

## Architecture

### StatTracker (`scripts/data/stat_tracker.gd`)
- `class_name` static utility — all methods operate on `player_data_store` dictionaries
- Uses `static var _store` initialized via `StatTracker.init(player_data_store)` in `NetworkManager._ready()`
- Tests can set `StatTracker._store` directly (no autoload dependency)

### Data Model
Two keys in `player_data_store[peer_id]`:
- `"stats"` — flat dictionary of integer counters + per-species sub-dictionaries
- `"compendium"` — three arrays: `items`, `creatures_seen`, `creatures_owned`

Both are auto-initialized (backfilled) for new and legacy players in `_finalize_join()`.

### API Methods
| Method | Purpose |
|--------|---------|
| `increment(peer_id, stat_key, amount)` | Add to a flat counter |
| `increment_species(peer_id, stat_key, species_id, amount)` | Add to a per-species sub-dict counter |
| `unlock_compendium_item(peer_id, item_id)` | Mark item as discovered (idempotent) |
| `unlock_creature_seen(peer_id, species_id)` | Mark creature as encountered |
| `unlock_creature_owned(peer_id, species_id)` | Mark creature as obtained (also marks seen) |

## Tracked Stats (~30)

### Battle
| Stat Key | Description | Hook Location |
|----------|-------------|---------------|
| `battles_fought` | Total battles entered | battle_manager.gd (wild/trainer/pvp start) |
| `battles_won` | Wild/trainer battles won | battle_manager.gd `_end_battle_for_peer()` |
| `battles_lost` | Battles lost | battle_manager.gd `_end_battle_for_peer()` |
| `wild_battles_fought` | Wild encounters | battle_manager.gd `server_start_battle()` |
| `trainer_battles_fought` | Trainer battles | battle_manager.gd `server_start_trainer_battle()` |
| `trainer_battles_won` | Trainer battles won | battle_manager.gd `_end_battle_for_peer()` |
| `pvp_battles_fought` | PvP battles | battle_manager.gd `respond_pvp_challenge()` |
| `pvp_wins` | PvP victories | battle_manager.gd `_handle_pvp_end()` |
| `pvp_losses` | PvP defeats | battle_manager.gd `_handle_pvp_end()` |
| `creatures_fainted` | Enemies defeated | battle_manager.gd `_check_battle_outcome()` |
| `player_defeats` | Player lost all creatures | battle_manager.gd `_apply_defeat_penalty()` |
| `total_xp_gained` | Cumulative XP | battle_manager.gd `_grant_xp_for_defeat()` |

### Per-Species (sub-dictionaries)
| Stat Key | Description | Hook Location |
|----------|-------------|---------------|
| `species_encounters` | Times each species encountered | battle_manager.gd (battle start) |
| `species_catches` | Times each species obtained | crafting_system.gd (creature craft) |
| `species_evolutions` | Times each species evolved | battle_manager.gd (evolution) |

### Economy
| Stat Key | Description | Hook Location |
|----------|-------------|---------------|
| `money_earned` | Total money received | network_manager.gd `server_add_money()` |
| `money_spent` | Total money spent | network_manager.gd `server_remove_money()` |
| `items_crafted` | Items crafted | crafting_system.gd `_process_craft()` |
| `items_bought` | Items purchased from shops | network_manager.gd `_process_buy()` |
| `items_sold` | Items sold | network_manager.gd `_process_sell()` |
| `trades_completed` | Player trades completed | network_manager.gd `_execute_trade()` |

### Social
| Stat Key | Description | Hook Location |
|----------|-------------|---------------|
| `npc_conversations` | NPC talks | social_manager.gd `_process_talk()` |
| `gifts_given` | Gifts given to NPCs | social_manager.gd `_process_gift()` |
| `quests_completed_main` | Main quests done | quest_manager.gd `handle_complete_quest()` |
| `quests_completed_side` | Side quests done | quest_manager.gd `handle_complete_quest()` |
| `quests_completed_daily` | Daily quests done | quest_manager.gd `handle_complete_quest()` |
| `quests_completed_weekly` | Weekly quests done | quest_manager.gd `handle_complete_quest()` |

### Farming & Exploration
| Stat Key | Description | Hook Location |
|----------|-------------|---------------|
| `crops_planted` | Seeds planted | farm_manager.gd `_plant_crop()` |
| `crops_harvested` | Crops harvested | farm_manager.gd `_harvest_crop()` |
| `locations_discovered` | World locations found | location_manager.gd `_discover_location()` |
| `days_played` | In-game days elapsed | season_manager.gd `_advance_day()` |

## Compendium Unlocks

| Category | Trigger | Method |
|----------|---------|--------|
| Items | First time received in inventory | `unlock_compendium_item()` in `server_add_inventory()` |
| Creatures Seen | Encountered in any battle | `unlock_creature_seen()` in battle start / PvP setup |
| Creatures Owned | Crafted via creature recipe | `unlock_creature_owned()` in crafting_system.gd |

## Networking / Sync

- **Server-authoritative**: All StatTracker calls run on the server only
- **On-demand sync**: Client opens CompendiumUI → `request_compendium_sync.rpc_id(1)` → server responds with `_sync_compendium_client(stats, compendium)` → client stores in `PlayerData.stats` / `PlayerData.compendium`
- **PlayerData signals**: `stats_changed`, `compendium_changed` — CompendiumUI listens and auto-refreshes
- **Persistence**: Stats and compendium are part of the player save blob — saved to MongoDB via Express API (or file I/O in editor)

## CompendiumUI (`scripts/ui/compendium_ui.gd`)

- **Toggle**: K key (via `player_interaction.gd` `compendium` input action)
- **CanvasLayer**: Layer 10, sets busy state on open/close
- **3 tabs**: Items, Creatures, Stats

### Items Tab
- Shows all items from all registries (ingredients, foods, tools, held items, battle items, recipe scrolls)
- 7 sub-filter buttons: All, Ingredients, Foods, Tools, Held Items, Battle Items, Scrolls
- Unlocked items: colored by category. Locked items: "???" in grey
- Detail panel: name, category, sell price
- Counter: "Items: X/Y"

### Creatures Tab
- Shows all 21 species sorted alphabetically
- Three states: Unknown ("???"), Seen (name visible), Owned (green "[Owned]" tag)
- Owned creatures show: base stats, abilities, evolution info, per-species encounter/catch/evolution counts
- Seen-only creatures show: name, type, hint to own for full details
- Counter: "Creatures: X/21 seen, Y/21 owned"

### Stats Tab
- 5 sections: Battle, Economy, Social, Farming, Exploration
- Each stat as labeled row with formatted value (K/M suffixes for large numbers)
- Species Breakdown section: per-creature encounter/catch/evolution counts

## Per-Player Data Isolation

Each player's stats and compendium are completely isolated. Verified in MCP runtime testing:
- Player1 receiving items does NOT affect Player2's compendium
- PvP battle stats correctly attribute wins/losses to the right player
- Data persists across disconnect/reconnect cycles

## Files

| File | Purpose |
|------|---------|
| `scripts/data/stat_tracker.gd` | Static utility (class_name, server-only) |
| `scripts/ui/compendium_ui.gd` | Client UI (CanvasLayer, K key) |
| `scenes/ui/compendium_ui.tscn` | UI scene |
| `test/unit/data/test_stat_tracker.gd` | Unit tests for StatTracker |
