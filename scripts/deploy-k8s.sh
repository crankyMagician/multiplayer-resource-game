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

IMAGE="ghcr.io/crankymagician/mt-creature-crafting-server:latest"
K8S_NAMESPACE="godot-multiplayer"
K8S_DEPLOYMENT="creature-crafting-server"
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

# --- Build ---
if [ "$SKIP_BUILD" = false ]; then
	echo "==> Building Docker image ($IMAGE)..."
	docker build --platform linux/amd64 -t "$IMAGE" .
else
	echo "==> Skipping build (using existing image)."
fi

# --- Push ---
echo "==> Pushing image to GHCR..."
if ! docker push "$IMAGE"; then
	echo ""
	echo "ERROR: Push failed. Make sure you are authenticated:"
	echo "  docker login ghcr.io -u YOUR_GITHUB_USERNAME"
	exit 1
fi

# --- Deploy ---
echo "==> Applying Kubernetes manifests..."
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml

echo "==> Restarting deployment to pull new image..."
kubectl rollout restart "deployment/$K8S_DEPLOYMENT" -n "$K8S_NAMESPACE"

echo "==> Waiting for rollout to complete..."
if kubectl rollout status "deployment/$K8S_DEPLOYMENT" -n "$K8S_NAMESPACE" --timeout=180s; then
	echo ""
	echo "Deploy successful! Server available at $SERVER_ENDPOINT (UDP)"
else
	echo ""
	echo "WARNING: Rollout did not complete within 180s."
	echo "  Check status: kubectl get pods -n $K8S_NAMESPACE"
	exit 1
fi
