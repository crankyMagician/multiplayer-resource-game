# Battle System Details

## Battle Modes
- **3 battle modes**: Wild, Trainer (7 NPCs), PvP (V key challenge within 5 units of another player)
- **21 creatures** (9 original + 9 gen2 + 3 evolutions), 7 evolution chains, MAX_PARTY_SIZE = 3
- **Starter creature**: All new players spawn with Rice Ball (Grain, Lv 5, 45 HP) with moves: grain_bash, quick_bite, bread_wall, syrup_trap
- **57 moves** including weather setters, hazards, protection, charging, multi-hit, recoil, drain, crit-boosters, taunt, trick room, substitutes
- **20 abilities** with trigger-based dispatch (on_enter/on_attack/on_defend/on_status/end_of_turn/on_weather)
- **18 held items** (6 type boosters, 6 utility, 3 choice items, 3 specialist) — all craftable from ingredients
- **XP/Leveling**: XP from battles, level-up stat recalc, learnset moves, evolution. Full XP to participants, 50% to bench.
- **AI**: 3 tiers (easy=random, medium=type-aware, hard=damage-calc + prediction)
- **PvP**: Both-submit simultaneous turns, 30s timeout, disconnect = forfeit. Loser forfeits 25% of each ingredient stack to winner.
- **6 battle items**: herb_poultice (30 HP), spicy_tonic (60 HP), full_feast (full HP), mint_extract (cure status), flavor_essence (5 PP), revival_soup (revive 50% HP). Used via "Items" button in battle UI. Item use consumes a turn. Blocked in PvP battles. Server processes via `_process_item_use()`.
- **Defeat penalty**: 50% money loss, teleport to spawn point, all creatures healed

## IVs, Bond, and Crit Stages
- **IVs**: 6 stats (hp/atk/def/spa/spd/spe), 0-31 range, rolled on creation via `CreatureInstance.create_from_species()`. Formula: `stat = int(base_stat * level_mult) + iv`. Old saves auto-backfilled. `CreatureInstance.IV_STATS` constant.
- **Bond**: Points earned via battles (+10 active, +1 bench) and feeding (+15). Levels 0-5, thresholds: 50/150/300/500/750 (`CreatureInstance.compute_bond_level()`). Modifiers: Lv2 +5% accuracy, Lv3 1.2x XP, Lv4 endure (survive lethal hit at 1 HP once), Lv5 +10% all stats. Battle affinities tracked for future expansion.
- **Crit stages**: Per-creature 0-3, rates: 6.25%/12.5%/25%/50% (`BattleCalculator.get_crit_stage()`). Moves modify via `self_crit_stage_change`. Resets each battle.
- **Taunt**: `taunt_turns` (3 turns), prevents status moves. Validated in `request_battle_action()`.
- **Trick Room**: `trick_room_turns` on battle dict, reverses speed priority.
- **Substitutes**: `substitute_hp` per creature, absorbs damage before real HP. Sound moves bypass.

## Move Properties (MoveDef)
- `self_crit_stage_change: int` — crit stage modifier on use
- `is_sound: bool` — bypasses substitutes
- `taunts_target: bool` — applies taunt on hit
- `knock_off: bool` — removes defender's held item
- `sets_trick_room: bool` — toggles trick room

## Battle UI
- **Enemy panel**: name, level, types, HP bar, status, stat stages, crit stage
- **Player panel**: name, level, types, HP bar, XP bar, ability, held item
- **Move buttons**: 3-line format — Name / Type|Category|Power / Accuracy|PP
- **Field effects bar**: trick room, taunt turns, substitute HP, crit stage
- **Weather bar**: weather name + remaining turns
- **Flee/Switch/Items**: Flee in wild only, Switch always available, Items button opens battle item list (hidden in PvP)
- **Turn log**: scrolling RichTextLabel. Ability messages in `[color=purple]`, item in `[color=cyan]`, effectiveness in green/yellow.
- **Summary screen**: Victory/Defeat, XP per creature (level-up highlights), item drops, trainer money + bonus ingredients. Continue button returns to world.
- **PvP-specific**: no Flee, "Waiting for opponent..." label, perspectives actor-swapped. PvP challenge UI auto-hides when battle starts.
- **Trainer prompt cleanup**: `_on_battle_started()` calls `hud.hide_trainer_prompt()`.

## Battle Manager Server-Side
- Battle state keyed by `battle_id` (auto-increment), `player_battle_map[peer_id] → battle_id`
- **Server-authoritative party data**: `_build_party_from_store(peer_id)` reads party from `NetworkManager.player_data_store`, NOT from client. No `_receive_party_data` RPC exists.
- **Move validation**: `request_battle_action()` verifies move_id exists in creature's actual moveset. Switch targets bounds-checked.
- Wild/Trainer: server picks AI action, resolves turn, sends `_send_turn_result` RPC
- PvP: both sides submit via `request_battle_action` RPC, server resolves when both received. `_swap_actor()` flips perspective for each player's log.
- Rewards via separate RPCs: `_grant_battle_rewards`, `_send_xp_results`, `_grant_trainer_rewards_client`, `_battle_defeat_penalty`
- **Party deep-copy**: `server_update_party()` uses `.duplicate(true)` to prevent cross-player state corruption.
