# Location System, Calendar & Weather Details

## Location System, Compass & Minimap
- **28 LocationDefs** (`resources/locations/*.tres`): Static world landmarks with `location_id`, `display_name`, `world_position`, `discovery_radius`, `category`, `icon_color`
- **DataRegistry integration**: `DataRegistry.locations` dict, `get_location(id)` accessor
- **LocationManager** (`scripts/world/location_manager.gd`): Server-side, no `class_name`. Checks player proximity to undiscovered locations every 10 physics frames. Skips players in restaurants.
- **Discovery flow**: Server detects proximity -> appends to `player_data_store[peer_id]["discovered_locations"]` -> `_notify_location_discovered` RPC -> client updates `PlayerData.discovered_locations` + HUD toast
- **Persistence**: `discovered_locations` array saved in player_data_store -> MongoDB. Backfilled to `[]` for old saves.
- **Compass UI** (`scripts/ui/compass_ui.gd`): CanvasLayer (layer 5), always-visible horizontal strip at top-center. Cardinal markers scroll based on `camera_yaw`. Undiscovered locations shown as dimmed markers (6x4 px, `icon_color` at 40% alpha) at the top of the strip; discovered locations use the target dropdown system. Target dropdown lists discovered locations by category. Hides when in restaurant.
- **Compass math**: North = -Z (toward wild zones) = `camera_yaw` at PI. Target bearing: `atan2(dx, dz)` matches `forward = Vector3(sin(yaw), 0, cos(yaw))`.
- **Minimap** (`scripts/ui/minimap_ui.gd`): `Control._draw()` based, renders all locations — discovered as filled category-shaped icons, undiscovered as outlined shapes with "???" labels. Category legend in bottom-left corner. Player triangle at center. Scroll wheel zoom. Click to set compass target (discovered only).
- **Pause Overlay** (`scripts/ui/pause_overlay.gd`): CanvasLayer (layer 15), toggled by M key (`open_map` action). Shows minimap, sets busy state. Won't open if other modal UIs are active (explicit blocklist check — permanent HUD elements like HotbarUI, CompassUI, ExcursionHUD are excluded). Note: CanvasLayer `visible=false` does NOT propagate to children, so the check inspects the CanvasLayer's own `.visible` before scanning child Controls.
- **PlayerData additions**: `discovered_locations: Array`, `compass_target_id: String`, signals `discovered_locations_changed`, `compass_target_changed`
- **RPCs**: `_notify_location_discovered(location_id, display_name)`, `_sync_discovered_locations(location_ids)` — both server->client
- **Files**: `scripts/data/location_def.gd`, `scripts/world/location_manager.gd`, `scripts/ui/compass_ui.gd`, `scripts/ui/minimap_ui.gd`, `scripts/ui/pause_overlay.gd`, `scenes/ui/compass_ui.tscn`, `scenes/ui/pause_overlay.tscn`, `resources/locations/*.tres` (28)

## Calendar & Weather System (12-Month)
- **SeasonManager** (`scripts/world/season_manager.gd`): Server-authoritative 12-month calendar. Seasons derived from month.
- **Day cycle**: 10 real minutes per in-game day (`DAY_DURATION = 600.0`)
- **Months**: 12 months (Jan-Dec), 28 days/month, 336 days/year. Game starts March (spring).
- **Seasons**: Derived from `MONTH_TO_SEASON` — Mar-May=spring, Jun-Aug=summer, Sep-Nov=autumn, Dec-Feb=winter.
- **Weather**: 4 types — Sunny (50%), Rainy (25%), Windy (15%), Stormy (10%). Rolled each day.
- **Rain auto-waters**: On rainy/stormy days, `_rain_water_all_farms()` waters all FarmManagers
- **HUD display**: `season_label` shows "Year N, MonthName D", `day_label` shows weather name
- **Crop seasons**: `is_crop_in_season(crop_season)` checks against month-derived season
- **Sync**: `_broadcast_time(year, month, day, total_days, weather)` RPC. Late-joiners use `request_season_sync`.
- **Persistence**: `current_month`, `day_in_month`, `current_year`, `day_timer`, `total_day_count`, `current_weather`. Old saves auto-convert from season enum.
- **NPC birthdays**: `{month: int, day: int}` format. Old `{season, day}` format supported via backward compat.

## Calendar Board & Calendar UI
- **CalendarBoard** (`scripts/world/calendar_board.gd`): Area3D at `Vector3(5, 0, 5)`. E-key opens CalendarUI. `calendar_board` group.
- **CalendarUI** (`scripts/ui/calendar_ui.gd`): 28-day grid, month arrows, event markers. Sets busy state.
- **CalendarEvents** (`scripts/data/calendar_events.gd`): 10 holidays + NPC birthday lookup. `get_events_for_month/day()`.
- **Event types**: festival (gold), holiday (cyan), birthday (pink)
