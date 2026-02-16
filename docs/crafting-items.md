# Crafting & Item System Details

## Overview
- **58 recipes**: 13 creature (cauldron, unlockable), 18 held item (workbench), 12 food (kitchen), 9 tool upgrade (workbench), 6 battle item (kitchen)
- **6 item types**: ingredients (16), held items (18), foods (12), tools (12), recipe scrolls (13), battle items (6) — all share single inventory namespace
- **3 crafting stations**: Kitchen (restaurant zone), Workbench (near spawn), Cauldron (deep wild zone) — each filters recipes by `station` field
- **Recipe unlock system**: Creature recipes require recipe scrolls to unlock. Scrolls come from trainer first-defeat rewards, world pickups, or fragment collection (3-5 fragments auto-combine)

## Food & Buffs
- 4 buff foods (speed_boost, xp_multiplier, encounter_rate, creature_heal) + 8 trade goods for selling
- Buffs are timed, server-side expiry checked every 5s

### Buff Application Points
- **Speed boost**: `player_controller.gd` `_physics_process()` — multiplies move speed
- **XP multiplier**: `battle_manager.gd` `_grant_xp_for_defeat()` — multiplies XP
- **Encounter rate**: `encounter_manager.gd` `get_encounter_rate_multiplier()` — multiplies probability

## Tool Upgrades
- 3 tool types (hoe, axe, watering_can) x 4 tiers (basic->bronze->iron->gold)
- Upgrade recipes consume old tool + ingredients. Dynamic stats from ToolDef

## Crafting Security
- Single-phase server-authoritative — `request_craft(recipe_id)` RPC validates everything server-side, deducts, produces result, syncs to client. No client-side deduction.

## Selling
- `request_sell_item(item_id, qty)` RPC. Universal `DataRegistry.get_sell_price(item_id)` checks BattleItemDef, FoodDef, IngredientDef for sell prices

## Ingredients & Farming
- **16 ingredients**: farm crops (season-locked) + battle drops. Plantable crops: lemon (summer), pickle_brine (autumn)
- **Planting flow** (server-authoritative): Client sends `request_farm_action(plot_idx, "plant", seed_id)` RPC. Server removes seed from `player_data_store`, attempts plant, rolls back on failure. No client-side deduction.
- **Watering flow** (server-authoritative): Client sends `request_farm_action(plot_idx, "water", "")` RPC. Server decrements, syncs via `_sync_watering_can` RPC. Refill via `_request_refill` RPC.

## PlayerData Tool System
- **No Tool enum** — replaced with string-based `current_tool_slot` ("", "hoe", "axe", "watering_can", "seeds")
- `equipped_tools: Dictionary` maps tool_type -> tool_id (e.g. `{"hoe": "tool_hoe_basic", ...}`)
- `get_watering_can_capacity()` reads from equipped ToolDef's effectiveness dict
- `known_recipes: Array` tracks unlocked recipe IDs
- `active_buffs: Array` of `{buff_type, buff_value, expires_at}` dicts
