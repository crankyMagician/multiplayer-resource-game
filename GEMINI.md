# Mechanical Turk Engine - Creature Crafting Demo

## Project Overview

This project is a multiplayer resource management game, "Creature Crafting Demo," developed using a custom fork of the Godot Engine (Mechanical Turk Engine 4.7-dev). It features a dedicated Node.js API backend with MongoDB for data persistence and is designed for containerized deployment using Docker and Kubernetes.

The project's architecture consists of:
*   **Game Client/Server:** Built with Godot Engine 4.7-dev (Mechanical Turk fork), primarily using GDScript.
*   **API Service:** A Node.js application (`creature-crafting-api`) built with Express.js, TypeScript, and MongoDB for data management.
*   **Database:** MongoDB, utilized by the API service.

## Building and Running

### Prerequisites

*   **Godot Engine:** An installation of the Mechanical Turk Engine (Godot 4.7-dev fork) editor is required for client builds and local development. The `scripts/build-clients.sh` expects it at `/Applications/Mechanical Turk.app/Contents/MacOS/Mechanical Turk` on macOS.
*   **Node.js & npm/yarn:** For API development.
*   **Docker & Docker Compose:** For running the API, MongoDB, and dedicated game server.
*   **Bash:** For executing provided build scripts.
*   **SCons:** (Implicitly used by `Dockerfile.engine` for engine builds).

### Godot Editor

To open the project in the Godot editor, navigate to the project root and open `project.godot` with your Mechanical Turk Engine editor instance.

### Dedicated Game Server (Docker)

The dedicated game server uses a two-phase Docker build process:

1.  **Engine Build:** Compiles the custom Mechanical Turk Engine for Linux x86_64.
    *   Ensure the `mechanical-turk` engine repository is cloned one level up from this project (e.g., `../mechanical-turk/`).
    *   Run: `./scripts/build-engine-templates.sh` (use `--force` to rebuild).
    This script utilizes `Dockerfile.engine` to create a Docker image containing the engine binaries, which are then extracted to `engine-builds/linux/`.

2.  **Game Build & Run:** Uses the pre-built engine binaries to export and run the server.
    *   To build and start the dedicated server locally, use the provided script:
        ```bash
        ./scripts/start-docker-server.sh
        ```
    *   Alternatively, to manually start the services:
        ```bash
        docker compose up --build -d game-server
        ```
    The server listens on UDP port `7777`. Logs can be viewed with `docker logs -f multiplayer-resource-game-game-server-1`.

### Game Clients (macOS & Windows)

The `scripts/build-clients.sh` script automates the export process for macOS and Windows clients (debug and release variants).

*   **To build all clients:**
    ```bash
    ./scripts/build-clients.sh
    ```
*   **To clean previous builds:**
    ```bash
    ./scripts/build-clients.sh --clean
    ```
*   **Specific options:** `--skip-macos`, `--skip-windows`, `--debug-only`, `--release-only`.

### API Service

*   **Via Docker Compose:**
    ```bash
    docker compose up --build -d api-service
    ```
    The API service will be accessible on `http://localhost:3000`.

*   **Local Development (without Docker):**
    ```bash
    cd api
    npm install
    npm run dev
    ```
    The API requires a running MongoDB instance, which can be started via Docker Compose (`docker compose up -d mongodb`).

## Development Conventions

*   **Godot Engine (Game):**
    *   Uses GDScript for game logic.
    *   Relies on the custom Mechanical Turk Engine fork (Godot 4.7-dev).
    *   Testing is handled via the GUT (Godot Unit Test) addon.
*   **API Service:**
    *   Developed in TypeScript using Express.js.
    *   Uses Vitest for unit and integration testing.
*   **Build Systems:**
    *   **Engine:** SCons (orchestrated via Docker).
    *   **Game Server/Clients:** Godot's export system, automated with custom Bash scripts.
    *   **API:** TypeScript compiler (`tsc`), npm/yarn scripts.
*   **Containerization:** Docker for services and build environments, Docker Compose for local orchestration.
*   **Deployment:** Kubernetes configurations are available in the `k8s/` directory.
