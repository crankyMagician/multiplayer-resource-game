# Agents Guide

## Quick Start (Local)
1. Start server:
   - `./start-docker-server.sh`
2. Launch client with Mechanical Turk and open this project.
3. Join using `127.0.0.1`.

## Quick Start (Kubernetes)
1. First-time setup:
   - `./scripts/deploy-k8s.sh --setup`
2. Build, push, and deploy:
   - `./scripts/deploy-k8s.sh`
3. Join using `10.225.0.153:30777`.

## Networking Contract
- Server/client default UDP port is `7777`.
- Any tooling, scripts, docs, and deployment defaults should assume `7777`.

## Multiplayer Expectations
- Server is authoritative for world state and movement simulation.
- Client must complete world-load readiness before spawn replication begins.
- If join fails, inspect logs for readiness/replication errors first.

## UI/UX Expectations
- Battle encounters must show mouse cursor for UI interaction.
- Exiting battle should recapture mouse for movement/camera control.
- Wild encounter areas should be clearly visible in-world and explained via HUD hinting.

## Kubernetes Deployment
- Namespace: `godot-multiplayer` (shared with sheep-tag and other game servers).
- Image: `ghcr.io/crankymagician/mt-creature-crafting-server:latest`.
- NodePort `30777` → container `7777/UDP`. Node IP: `10.225.0.153`.
- Player/world saves persist on a 1Gi PVC (`creature-crafting-data`) at `/app/data`.
- Deploy strategy is `Recreate` (RWO PVC constraint).
- Manifests live in `k8s/deployment.yaml` and `k8s/service.yaml`.
- Deploy script: `scripts/deploy-k8s.sh` (`--setup` for first-time, `--skip-build` to redeploy only).

## Operational Notes
- If local container/server appears stale, rebuild:
  - `docker compose up --build -d`
- If needed, force rebuild without cache:
  - `docker compose build --no-cache`
  - `docker compose up -d`
- If K8s pod appears stale, redeploy:
  - `./scripts/deploy-k8s.sh`
  - Or restart without rebuild: `./scripts/deploy-k8s.sh --skip-build`
