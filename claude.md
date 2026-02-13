# Claude Notes

## Project Runtime Defaults
- Multiplayer default port: `7777` (UDP).
- Local client connects to `127.0.0.1` on port `7777`.
- Dedicated server can be run in Docker or Mechanical Turk headless mode.

## Docker Server Workflow
- Use `./start-docker-server.sh` to build and start the dedicated server.
- The script runs `docker compose up --build -d` and prints service status.
- Docker mapping is `7777:7777/udp`.

## Multiplayer Join/Spawn Stabilization
- Join flow uses a client-ready handshake before server-side spawn.
- Spawn waits for client world path readiness (`/root/Main/GameWorld/Players/MultiplayerSpawner`).
- Server tracks temporary join state and times out peers that never become ready.

## Player/Camera Notes
- Player movement uses server authority with replicated input.
- Camera defaults to over-the-shoulder and captures mouse during world control.
- Mouse is explicitly made visible during battle UI and recaptured after battle ends.

## Wild Encounter UX
- Wild zones are represented by glowing colored grass patches.
- Wild zones include floating in-world labels for better discoverability.
- HUD provides persistent legend + contextual "wild munch zone" hint when inside encounter grass.

## Kubernetes Deployment
- **Namespace**: `godot-multiplayer` (shared with other multiplayer game servers)
- **Image**: `ghcr.io/crankymagician/mt-creature-crafting-server:latest`
- **Endpoint**: `10.225.0.153:30777` (UDP) — NodePort 30777 → container 7777
- **Persistent storage**: 1Gi PVC (`creature-crafting-data`) mounted at `/app/data` for player/world saves
- **Deploy strategy**: `Recreate` (RWO PVC can't be shared during rolling update)
- **MCP config**: `.claude/mcp.json` provides both Godot and Kubernetes MCP servers
- **K8s MCP**: Uses `blazar-kubernetes-mcp/run-mcp.sh` with `K8S_NAMESPACE=godot-multiplayer`
- **RBAC**: Service account `mcp-admin` in `godot-multiplayer` namespace (configured in `blazar-kubernetes-mcp/k8s/rbac-setup.yaml`)

### K8s Deploy Workflow
```bash
./scripts/deploy-k8s.sh --setup      # first-time: namespace + ghcr-secret + RBAC
./scripts/deploy-k8s.sh              # full build + push + deploy
./scripts/deploy-k8s.sh --skip-build # redeploy without rebuilding image
```

## Recent Infrastructure Changes
- `k8s/deployment.yaml`: PVC + Deployment for creature-crafting-server in `godot-multiplayer` namespace.
- `k8s/service.yaml`: NodePort service (30777 → 7777/UDP).
- `scripts/deploy-k8s.sh`: automated build, push, and deploy script with `--setup` bootstrapping.
- `scripts/autoload/network_manager.gd`: port switched to `7777`; join handshake and readiness flow hardened.
- `scripts/player/player_controller.gd`: authority setup and movement/camera reliability updates.
- `scripts/world/tall_grass.gd`: encounter zone visuals and multiplayer safety guards.
- `scripts/ui/battle_ui.gd`: cursor visibility behavior for encounter UI.
- `docker-compose.yml` and `Dockerfile`: updated to `7777`.
