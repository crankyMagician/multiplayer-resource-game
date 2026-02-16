# NPC Social & Quest System Details

## NPC Social System (Stardew Valley-style)

### Friendship Mechanics
- **Friendship**: -100 to +100 points per NPC, 5 tiers (hate < -60, dislike < -20, neutral < 20, like < 60, love >= 60)
- **Talk**: +2 daily bonus (once/NPC/day), branching dialogue with player choices (+/- points per choice)
- **Gifts**: 1 gift/NPC/day. Tiers: loved (+15), liked (+8), neutral (+3), disliked (-8), hated (-15). 3x birthday multiplier.
- **Daily decay**: -1/day if not interacted (floor at 0, no negative spiral). Flags reset on day_changed.
- **NPC gifts**: One-time threshold rewards at 20/50/80 friendship points.

### NPCs
- **5 NPCs**: Baker Brioche, Sage Herbalist, Old Salt, Ember Smith, Professor Umami — each with branching dialogues, gift prefs, schedule.

### Architecture
- Server-authoritative. SocialManager (no class_name — references autoloads) handles all friendship logic. SocialNPC (Area3D) handles proximity + RPCs. DialogueUI (CanvasLayer) is client-only.
- **No class_name on SocialManager** — inlined static methods in dialogue_ui.gd and test files to avoid autoload reference issues.

### RPCs
- `request_talk` -> `_send_dialogue(npc_id, text, choices, points, tier)` -> `request_dialogue_choice(idx)` -> `_dialogue_choice_result(response, points, tier)`
- Gift: `request_give_gift(item_id)` -> `_gift_response(msg, pts)`

### Files
`scripts/data/npc_def.gd`, `scripts/world/social_npc.gd`, `scripts/world/social_manager.gd`, `scripts/ui/dialogue_ui.gd`, `scenes/ui/dialogue_ui.tscn`, `resources/npcs/*.tres` (5), `test/unit/world/test_social_system.gd`, `test/integration/test_social_flow.gd`

---

## NPC Creature Trades

### Data Model
- **`npc_def.creature_trades`**: Array of trade dicts per NPC. Each trade: `creature_species_id`, `creature_level`, `creature_nickname`, `cost_items` (dict of item_id → qty), `cost_money`, `required_friendship` (tier name), `required_season`, `required_quest_id`, `dialogue_text`, `dialogue_accept_label`, `dialogue_decline_label`, `one_time: bool`.
- **Trade keys**: One-time trades tracked as `"npc_creature_trade_" + npc_id + "_" + species_id` in `npc_friendships[npc_id]["gifts_received"]`.

### Available Trades
| NPC | Creature | Level | Cost | Friendship | Season | One-time |
|-----|----------|-------|------|------------|--------|----------|
| Baker Brioche | Wheat Golem | 8 | 20 grain_wheat + 3 sweet_crystal + 500g | like | spring | yes |
| Sage Herbalist | Basil Sprite | 10 | 15 herb_basil + 5 herbal_dew + 600g | love | — | yes |
| Ember Smith | Sear Slug | 12 | 10 chili_pepper + 5 spicy_essence + 800g | love | — | yes |

### Availability Check
`_get_available_creature_trade(peer_id, npc_id, npc_def)` filters by:
1. One-time flag (skip if trade_key in gifts_received)
2. Friendship tier (`_tier_meets_requirement` checks tier order: hate < dislike < neutral < like < love)
3. Season (must match current season if specified)
4. Quest (must be in completed_quests if specified)

### Acceptance Flow
1. `handle_talk_request()` appends creature trade accept/decline choices to dialogue
2. Client selects accept choice → `handle_dialogue_choice()` → `_handle_creature_trade_accept()`
3. Server re-validates all conditions (prevents replay attacks)
4. Server validates + deducts cost_items and cost_money
5. Creates creature: `CreatureInstance.create_from_species()` → dict with UUID + nickname
6. Routes through `NetworkManager.server_give_creature()` (universal handler)
7. If party full → triggers CreatureDestinationUI (storage or swap)
8. Marks trade as received (one-time flag in gifts_received)
9. Syncs inventory + money to client

### Files
`scripts/world/social_manager.gd` (`_get_available_creature_trade`, `_handle_creature_trade_accept`), `scripts/data/npc_def.gd` (`creature_trades` property), `resources/npcs/*.tres`

---

## Quest System

### Data Model
- **Data-driven**: QuestDef Resource (`scripts/data/quest_def.gd`, `class_name QuestDef`) with quest_id, objectives array, prereqs, rewards, NPC dialogue, chain/story fields
- **6 quest .tres resources**: 3 main story (ms_01_meet_baker, ms_02_first_harvest, ms_03_first_battle), 1 side (side_herbalist_remedy), 1 daily (daily_creature_patrol), 1 weekly (weekly_forager)
- **Categories**: `main_story`, `side`, `daily`, `weekly`. Daily/weekly auto-reset via SeasonManager day_changed signal.

### Quest Manager
- **QuestManager** (`scripts/world/quest_manager.gd`): Server-authoritative, no `class_name` (follows SocialManager pattern). Handles accept, progress, completion, abandonment, daily/weekly resets.

### Objective Types
- **Cumulative** (defeat_trainer, defeat_creature, defeat_pvp, discover_location, talk_to, craft, collect without consumes_items) tracked via `notify_progress()`
- **Inventory-check** (deliver, collect with consumes_items=true) validated at turn-in

### Integration Hooks
`notify_progress()` called from NetworkManager (collect), BattleManager (defeat_trainer/creature/pvp), CraftingSystem (craft), LocationManager (discover_location), SocialManager (talk_to)

### Prerequisites
prereq_quest_ids, prereq_friendship, prereq_locations, prereq_season, prereq_weather, prereq_main_story_quest_id — all checked in `check_prereqs()`

### Rewards & Chains
- **Rewards**: money, items, friendship points, recipe scrolls, unlock flags. Granted atomically in `handle_complete_quest()`. Delivery items consumed at turn-in.
- **Quest chains**: `next_quest_id` auto-offers next quest on completion. `chapter` + `sort_order` for main story grouping.

### UI
- **NPC quest indicators**: SocialNPC shows "!" (available quests) or "?" (completable quests) Label3D above head. Updated client-side in `_process()`.
- **QuestLogUI** (`scripts/ui/quest_log_ui.gd`): CanvasLayer (layer 10), J key toggle. Tabs: Active/Completed/Main Story. Shows objectives, rewards, action buttons (Track/Abandon/Complete). Also handles NPC quest offer/turn-in via `show_npc_quests()`. Sets busy state.
- **HUD quest tracker**: Bottom-right VBoxContainer showing tracked quest name + objective progress. Connected to `PlayerData.quests_changed`.

### Player State
`player_data_store[peer_id]["quests"]` = `{active: {}, completed: {}, daily_reset_day, weekly_reset_day, unlock_flags: []}`. Backfilled in `_finalize_join()`. Client mirror in PlayerData: `active_quests`, `completed_quests`, `unlock_flags`, signal `quests_changed`.

### RPCs
- Client->Server: `request_available_quests`, `request_accept_quest`, `request_complete_quest`, `request_abandon_quest`
- Server->Client: `_send_available_quests`, `_sync_quest_state`, `_notify_quest_progress`, `_notify_quest_complete`, `_offer_next_quest`

### Exploit Prevention
Server-only progress, atomic rewards, duplicate completion check, delivery re-validation at turn-in, main_story cannot be abandoned.

### Files
`scripts/data/quest_def.gd`, `scripts/world/quest_manager.gd`, `scripts/ui/quest_log_ui.gd`, `scenes/ui/quest_log_ui.tscn`, `resources/quests/*.tres` (6), `test/unit/world/test_quest_system.gd`, `test/integration/test_quest_flow.gd`
