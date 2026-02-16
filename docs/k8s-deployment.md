# Kubernetes Deployment

- **Namespace**: `godot-multiplayer` (shared with other multiplayer game servers)
- **3 deployments**:
  - `creature-crafting-mongodb` — mongo:7, ClusterIP service, 2Gi PVC (`creature-crafting-mongo-data`)
  - `creature-crafting-api` — Express API (`ghcr.io/crankymagician/mt-creature-crafting-api:latest`), ClusterIP service on port 3000, liveness/readiness probes on `/health`
  - `creature-crafting-server` — Game server (`ghcr.io/crankymagician/mt-creature-crafting-server:latest`), NodePort 7777/UDP, `SAVE_API_URL=http://creature-crafting-api:3000/api`
- **Public endpoint**: `207.32.216.76:7777` (UDP) — NodePort 7777 → container 7777.
- **Internal/VPN endpoint**: `10.225.0.153:7777`.
- **Node SSH access**: `ssh jayhawk@10.225.0.153` (password: `fir3W0rks!`). User has sudo. k3s config at `/etc/rancher/k3s/config.yaml`. NodePort range: `7000-32767`.
- **Deploy order**: MongoDB → API (waits for MongoDB rollout) → Game server. The deploy script handles this automatically.
- **Deploy strategy**: Game server uses `Recreate` (simplicity). API uses default `RollingUpdate`.
- **MCP config**: `.claude/mcp.json` provides both Godot and Kubernetes MCP servers
- **K8s MCP**: Uses `blazar-kubernetes-mcp/run-mcp.sh` with `K8S_NAMESPACE=godot-multiplayer`
- **RBAC**: Service account `mcp-admin` in `godot-multiplayer` namespace (configured in `blazar-kubernetes-mcp/k8s/rbac-setup.yaml`)

## K8s Deploy Workflow
```bash
./scripts/deploy-k8s.sh --setup      # first-time: namespace + ghcr-secret + RBAC
./scripts/deploy-k8s.sh              # full build (server + API images) + push + deploy all 3 deployments
./scripts/deploy-k8s.sh --skip-build # redeploy without rebuilding images
./scripts/build-engine-templates.sh          # build engine only (cached)
./scripts/build-engine-templates.sh --force  # rebuild engine from scratch
```

## K8s Manifests
- `k8s/mongodb.yaml` — PVC + Deployment + ClusterIP Service for MongoDB
- `k8s/api-service.yaml` — Deployment + ClusterIP Service for Express API
- `k8s/deployment.yaml` — Deployment for game server (SAVE_API_URL env var)
- `k8s/service.yaml` — NodePort Service for game server (7777/UDP)
