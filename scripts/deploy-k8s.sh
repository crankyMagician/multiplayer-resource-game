#!/usr/bin/env bash
set -euo pipefail

# deploy-k8s.sh — Build, push to GHCR, and deploy the server to Kubernetes.
#
# Usage:
#   ./scripts/deploy-k8s.sh              # full build + push + deploy
#   ./scripts/deploy-k8s.sh --skip-build # redeploy without rebuilding image
#   ./scripts/deploy-k8s.sh --setup      # first-time: create namespace + ghcr-secret + RBAC

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

IMAGE_SERVER="ghcr.io/crankymagician/mt-creature-crafting-server:latest"
IMAGE_API="ghcr.io/crankymagician/mt-creature-crafting-api:latest"
K8S_NAMESPACE="godot-multiplayer"
K8S_DEPLOYMENT_SERVER="creature-crafting-server"
K8S_DEPLOYMENT_API="creature-crafting-api"
SERVER_ENDPOINT="207.32.216.76:7777"
RBAC_YAML="../blazar-kubernetes-mcp/k8s/rbac-setup.yaml"

SKIP_BUILD=false
SETUP=false

for arg in "$@"; do
	case "$arg" in
		--skip-build) SKIP_BUILD=true ;;
		--setup) SETUP=true ;;
		*) echo "Unknown flag: $arg"; exit 1 ;;
	esac
done

# --- First-time setup ---
if [ "$SETUP" = true ]; then
	echo "==> First-time setup..."

	# Create namespace if missing
	if ! kubectl get namespace "$K8S_NAMESPACE" &>/dev/null; then
		echo "    Creating namespace $K8S_NAMESPACE..."
		kubectl create namespace "$K8S_NAMESPACE"
	else
		echo "    Namespace $K8S_NAMESPACE already exists."
	fi

	# Create GHCR pull secret
	if ! kubectl get secret ghcr-secret -n "$K8S_NAMESPACE" &>/dev/null; then
		echo ""
		read -rp "GitHub username: " GHCR_USER
		read -rsp "GitHub PAT (with read:packages): " GHCR_TOKEN
		echo ""
		kubectl create secret docker-registry ghcr-secret \
			-n "$K8S_NAMESPACE" \
			--docker-server=ghcr.io \
			--docker-username="$GHCR_USER" \
			--docker-password="$GHCR_TOKEN"
		echo "    ghcr-secret created."
	else
		echo "    ghcr-secret already exists."
	fi

	# Apply RBAC
	if [ -f "$RBAC_YAML" ]; then
		echo "    Applying RBAC from $RBAC_YAML..."
		kubectl apply -f "$RBAC_YAML"
	else
		echo "    WARNING: RBAC file not found at $RBAC_YAML — skipping."
	fi

	echo "==> Setup complete."
	exit 0
fi

# --- Ensure engine binaries exist ---
if [ "$SKIP_BUILD" = false ]; then
	if [ ! -f "$PROJECT_ROOT/engine-builds/linux/godot-editor" ] || [ ! -f "$PROJECT_ROOT/engine-builds/linux/godot-template" ]; then
		echo "==> Engine binaries not found. Building MT engine for Linux..."
		"$SCRIPT_DIR/build-engine-templates.sh"
	else
		echo "==> Engine binaries found (use scripts/build-engine-templates.sh --force to rebuild)."
	fi
fi

# --- Build ---
if [ "$SKIP_BUILD" = false ]; then
	echo "==> Building game server Docker image ($IMAGE_SERVER)..."
	docker build --platform linux/amd64 -t "$IMAGE_SERVER" .

	echo "==> Building API service Docker image ($IMAGE_API)..."
	docker build --platform linux/amd64 -t "$IMAGE_API" ./api
else
	echo "==> Skipping build (using existing images)."
fi

# --- Push ---
echo "==> Pushing images to GHCR..."
if ! docker push "$IMAGE_SERVER"; then
	echo ""
	echo "ERROR: Push failed for game server. Make sure you are authenticated:"
	echo "  docker login ghcr.io -u YOUR_GITHUB_USERNAME"
	exit 1
fi

if ! docker push "$IMAGE_API"; then
	echo ""
	echo "ERROR: Push failed for API service. Make sure you are authenticated:"
	echo "  docker login ghcr.io -u YOUR_GITHUB_USERNAME"
	exit 1
fi

# --- Deploy ---
echo "==> Applying Kubernetes manifests..."
kubectl apply -f k8s/mongodb.yaml
kubectl apply -f k8s/api-service.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

echo "==> Waiting for MongoDB to be ready..."
kubectl rollout status "deployment/creature-crafting-mongodb" -n "$K8S_NAMESPACE" --timeout=120s

echo "==> Restarting API service..."
kubectl rollout restart "deployment/$K8S_DEPLOYMENT_API" -n "$K8S_NAMESPACE"
kubectl rollout status "deployment/$K8S_DEPLOYMENT_API" -n "$K8S_NAMESPACE" --timeout=120s

echo "==> Restarting game server..."
kubectl rollout restart "deployment/$K8S_DEPLOYMENT_SERVER" -n "$K8S_NAMESPACE"

echo "==> Waiting for rollout to complete..."
if kubectl rollout status "deployment/$K8S_DEPLOYMENT_SERVER" -n "$K8S_NAMESPACE" --timeout=180s; then
	echo ""
	echo "Deploy successful! Server available at $SERVER_ENDPOINT (UDP)"
else
	echo ""
	echo "WARNING: Rollout did not complete within 180s."
	echo "  Check status: kubectl get pods -n $K8S_NAMESPACE"
	exit 1
fi
