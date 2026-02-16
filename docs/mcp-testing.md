# MCP Testing Workflow

## Editor-only bridge (single process)
- MCP bridge by default communicates with the editor process on port 9080, NOT the running game
- `batch_scene_operations` creates wrong node types — write .tscn files directly instead
- **To test server-side logic via MCP**: add temporary test code to `connect_ui.gd` `_ready()`, call `NetworkManager.host_game()`, run tests synchronously (no `await`), then check `get_debug_output`. Revert the test code afterward.
- **IMPORTANT**: Do NOT call `GameManager.start_game()` before your test code finishes — it frees ConnectUI via `queue_free`, killing any running coroutine. Run all assertions before `start_game()`.

## Runtime bridge — MCP multiplayer session (preferred)
- **Use `run_multiplayer_session` MCP tool** for multi-instance testing. It launches 1 server + N clients, each with a unique runtime bridge port, all managed by MCP.
- Pass `serverArgs: ["--server"]` so the server instance auto-starts without ConnectUI.
- Pass `numClients: 2` (or more) for client instances.
- Target instances with `target: "runtime:server"`, `target: "runtime:client_1"`, `target: "runtime:client_2"`, etc.
- **Lifecycle**: `stop_all_instances` to stop everything, `list_instances` to see running PIDs/ports.
- **Client join via GDScript**: Use `execute_gdscript` with `target: "runtime:client_N"` to call `NetworkManager.join_game("127.0.0.1", "PlayerName")` directly (more reliable than emitting button signals or mouse clicks).
- **Screenshot caching**: MCP screenshot tool may cache results — use `get_scene_tree` or `execute_gdscript` for reliable state verification.

## Runtime bridge — manual setup (alternative)
- The runtime bridge plugin enables `execute_gdscript`, `capture_screenshot`, `send_input_event`, and `send_action` on **running game processes**
- Each instance uses a different bridge port via `-- --bridge-port=NNNN` CLI arg
- **Headless server**: `'/Applications/Mechanical Turk.app/Contents/MacOS/Mechanical Turk' --path <project> --headless -- --bridge-port=9082`
- **Client 1**: launched via `run_project` MCP tool (uses default bridge port 9081)
- **Client 2**: launched manually with `-- --bridge-port=9083`

## Runtime bridge caveats
- **GDScript injection caveats**: runtime errors in injected scripts trigger the Godot debugger break, freezing the entire process. All subsequent MCP calls will timeout. Requires killing and restarting the process. GDScript has no try/catch. Common freeze causes: using `await`, accessing non-existent properties (e.g. `.state` instead of `.plot_state`), calling `.get()` on Resource objects, calling `rpc_id()` from injected scripts, using `is` operator on Arrays.
- **Server-side direct testing preferred**: For battle testing, call `bm._process_move_turn(battle, "move", "grain_bash")` and `bm._handle_pvp_action(battle, "a", "move", "grain_bash")` directly on the server — avoids `get_remote_sender_id()` issues. Similarly call `rm._enter_restaurant_server(peer_id, owner_name)` and `plot.try_clear(peer_id)` directly.
- **Key node paths**: FarmManager is at `Main/GameWorld/Zones/FarmZone/FarmManager` (NOT `Main/GameWorld/FarmManager`). HUD trainer label property is `trainer_prompt_label`. FarmPlot state property is `plot_state` (not `state`). DataRegistry stores Resource objects — use `.property_name` not `.get("property")`.
- **Screenshot size**: use small resolutions (400x300) to avoid WebSocket `ERR_OUT_OF_MEMORY` on large images
- **PvP testing**: players must be within 5 units for challenge flow. Move them on server via `nm._get_player_node(peer_id).position = Vector3(...)`. PvP has 30s turn timeout — act quickly or increase temporarily.
- **Battle dict access via MCP**: Battle state is a Dictionary (not an object). Use `bm.battles` (not `active_battles`), `battle.get("side_b_party")`, creature HP key is `"hp"` (not `"current_hp"`). The `request_battle_action` RPC takes `(action_type, action_data)` where action_data for moves is the **move ID string** (e.g. `"grain_bash"`), NOT an index.
- **Force-winning battles via MCP**: Set enemy creature `"hp"` to 1, set `battle.state = "processing"`, then call `bm._process_move_turn(battle, "move", "quick_bite")` directly on the server. Do NOT use `_end_battle_full()` — it bypasses trainer reward flow. For PvP, use `bm._handle_pvp_action(battle, "a"/"b", "move", "move_id")` for both sides.
- **Area3D re-detection**: Teleporting a player directly into an Area3D zone may not trigger `body_entered` if the physics engine doesn't detect the transition. Move the player far away first, then back, to guarantee signal fires.

## Port conflicts
- If `host_game()` returns error 20 (ERR_CANT_CREATE), check `lsof -i :7777` — a Docker container or previous server may be holding the port. Stop it with `docker compose down` first.
- Check bridge ports: `lsof -i :9081 -i :9082 -i :9083`
