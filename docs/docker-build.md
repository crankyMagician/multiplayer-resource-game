# Docker Server Build

## Two-Phase Build (Engine + Game)
The server Docker image requires matching the Mechanical Turk engine (Godot 4.7 fork) — stock Godot will cause RPC checksum mismatches and clients won't connect. The build is split into two phases:

1. **Engine build** (`Dockerfile.engine` + `scripts/build-engine-templates.sh`): Compiles MT engine from C++ source for Linux x86_64, producing `engine-builds/linux/godot-editor` (149MB) and `engine-builds/linux/godot-template` (82MB). Results are cached — subsequent runs are instant unless `--force` is passed. Requires the `mechanical-turk` engine repo at `../mechanical-turk/`.
2. **Game build** (`Dockerfile`): Uses the pre-built MT engine binaries to export the server. Templates go in `/root/.local/share/mechanical_turk/export_templates/4.7.dev/` (MT uses `mechanical_turk` as its data dir, NOT `godot`).

## Engine Build Details
- SCons flags: `platform=linuxbsd target=editor arch=x86_64 module_mono_enabled=no accesskit=no dev_mode=no lto=none`
- **LTO is disabled** (`lto=none`) because Docker's memory limit (~8GB) is insufficient for LTO linking (requires 16+ GB)
- Both `editor` (for `--export-release`) and `template_release` (embedded in exported binary) targets are built
- Build script: `./scripts/build-engine-templates.sh` (or `--force` to rebuild)

## Local Dev
- Use `./scripts/start-docker-server.sh` to rebuild and start the dedicated server locally.
- The script runs `docker compose up --build -d` from the project root and prints service status.
- Docker mapping is `7777:7777/udp`.
- Docker logs work in real-time via `docker logs -f multiplayer-resource-game-game-server-1` (uses `stdbuf -oL` for line-buffered output).
- Godot's internal log file is also available: `docker exec <container> cat "/root/.local/share/mechanical_turk/app_userdata/Creature Crafting Demo/logs/godot.log"`
