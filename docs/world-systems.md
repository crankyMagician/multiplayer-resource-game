# World Systems Details

## World Layout
- **Hub area**: Players spawn near (0, 1, 3). Farm zone at (25, 0, 0). Restaurant doors at z=12.
- **Decorative nodes** in `game_world.tscn` under GameWorld: `Paths`, `Signposts`, `Trees`, `ZoneOverlays`
- **Trainer progression**: Optional trainers flank the main path south; gatekeepers block advancement to deeper zones

## Wild Encounter Zones
- 6 zones total: Herb Garden, Flame Kitchen, Frost Pantry, Harvest Field, Sour Springs, Fusion Kitchen
- Represented by glowing colored grass patches with floating in-world labels
- HUD provides persistent legend + contextual hint when inside encounter grass

## NPC Trainers
- 7 trainers placed along world paths under `Zones/Trainers` in game_world.tscn
- Color-coded by difficulty: green=easy, yellow=medium, red=hard
- Trainers: Sous Chef Pepper, Farmer Green, Pastry Chef Dulce, Brinemaster Vlad, Chef Umami, Head Chef Roux, Grand Chef Michelin
- **Optional** (`is_gatekeeper=false`): Pepper, Green, Dulce, Vlad, Michelin — E-key prompt via `_show_trainer_prompt` RPC, `request_challenge` RPC to start. Rematch cooldown per trainer.
- **Gatekeeper** (`is_gatekeeper=true`): Umami, Roux — forced pushback + TrainerDialogueUI (Accept/Decline). Defeating records `defeated_trainers[trainer_id]` in player_data_store, `_notify_gate_opened` RPC hides gate per-client. Detection radius: 4.0 gatekeepers, 3.0 optional.

## World Item Drop & Pickup System
- **WorldItemManager** (`scripts/world/world_item_manager.gd`): Server-authoritative manager in `game_world.tscn`
- **WorldItem** (`scripts/world/world_item.gd`): Area3D pickup node with colored BoxMesh, billboard Label3D, bobbing animation, walk-over auto-pickup
- **Pickup flow**: Area3D `body_entered` (server-only) -> `WorldItemManager.try_pickup()` -> `server_add_inventory()` + `_sync_inventory_full` RPC -> `_notify_pickup` RPC (HUD toast) -> `_remove_world_item()` (despawn RPC to all)
- **Drop sources**: Random world forage spawns (every 120s, 10 spawn points), farm plot clearing
- **Late-joiner sync**: `sync_all_to_client(peer_id)` sends bulk `_spawn_world_item_client` RPCs
- **Persistence**: `get_save_data()` / `load_save_data()` integrated into `game_world.gd` save/load flow
- **Node naming**: `"WorldItem_" + str(uid)` with monotonic auto-increment UIDs to avoid duplicate name trap

## Restaurant System
- **Architecture**: Server-authoritative, per-player restaurant instances with own interior scene, farm plots, kitchen crafting station.
- **Instance positioning**: `Vector3(1000 + idx*200, 0, 1000)` — far from overworld. Index persisted in player save data.
- **Unique instance names**: `Restaurant_<owner_name>` set before `add_child()` to prevent Godot auto-rename.
- **Entry/exit flow**: Walk-over door (Area3D) -> server saves overworld position -> teleports to interior -> `_notify_location_change` RPC -> client instantiates scene. Exit via ExitDoor restores overworld position.
- **Farm routing**: `get_farm_manager_for_peer(peer_id)` checks `player_location` dict — returns restaurant's or overworld FarmManager.
- **Persistence**: Restaurant index map in world data. Farm plots saved to `player_data_store["restaurant"]` on unload/auto-save.
- **Auto-save position fix**: Both `save_manager.gd` and `network_manager.gd` check `RestaurantManager.overworld_positions[peer_id]` before falling back to `player_node.position` — prevents saving interior coordinates as overworld position.
- **Unloading**: When all players leave, saves farm data and `queue_free()`s the instance.
- **Files**: `scripts/world/restaurant_manager.gd`, `restaurant_interior.gd`, `restaurant_door.gd`, `scenes/world/restaurant_interior.tscn`

## Shop System
- **ShopDef** (`scripts/data/shop_def.gd`): Resource with `shop_id`, `display_name`, `items_for_sale` (Array of `{item_id, buy_price}` dicts)
- **3 shops**: General Store (ingredients), Battle Supplies (battle items), Rare Goods (premium items)
- **ShopNPC** (`scripts/world/shop_npc.gd`): Area3D with 3.0-unit detection radius. E-key prompt via HUD's trainer prompt system. Guards: rejects if player `is_busy` or in battle.
- **ShopUI** (`scripts/ui/shop_ui.gd`): CanvasLayer with Buy/Sell tabs. Buy shows catalog with prices (disabled if insufficient money). Sell lists player inventory with sell prices.
- **RPCs**: `request_open_shop()` -> server validates -> `_open_shop_client(shop_id, name, catalog)`. `request_buy_item(item_id, qty, shop_id)` / `request_sell_item(item_id, qty)` for transactions. Sets player busy state on open/close.

## Player Trading
- **T key** initiates trade with nearest player (within 5 units). Server validates both players not busy/in battle.
- **TradeUI** (`scripts/ui/trade_ui.gd`): Two phases — request panel (Accept/Decline) and trade panel (3-column: Your Offer | Their Offer | Your Inventory with +/- buttons).
- **Atomic swap**: Both players must confirm. Server re-validates all items exist before executing swap. `_execute_trade()` transfers items atomically.
- **RPCs**: `request_trade(target_peer)` -> `_trade_request_received(name, peer)` -> `respond_trade(peer, accepted)` -> `update_trade_offer(item_id, count_change)` -> `confirm_trade()` / `cancel_trade()`. Sets busy state during trade.

## Player Busy State
- **`is_busy: bool`** on player node, synced via StateSync (always mode). Visible to all clients.
- **BusyIndicator**: Label3D above player showing "[Busy]" when `is_busy = true`.
- **Guards**: Wild encounters, PvP challenges, trainer interactions, shop/trade all check `is_busy` before proceeding.
- **RPC**: `request_set_busy(busy: bool)` — client requests busy toggle, server sets on player node. Auto-cleared when closing shop/trade UI.
