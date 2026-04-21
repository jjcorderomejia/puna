#!/usr/bin/env bash
# Dev convenience — apply manifests with a specific image tag.
# Build and push is handled by CI (.github/workflows/build.yml).
# For first-time or client installs, use bootstrap.sh instead.
#
# Usage: ./deploy.sh [IMAGE_TAG]
#   IMAGE_TAG defaults to 'latest'
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
export PUNA_IMAGE="ghcr.io/jjcorderomejia/puna-claudex:${1:-latest}"
export HOST_HOME="${HOST_HOME:-$HOME}"

_wait_deploy() { kubectl -n puna rollout status deployment/"$1" --timeout=120s; }

mkdir -p "$REPO_ROOT/k8s/_rendered"
envsubst '${PUNA_IMAGE} ${HOST_HOME}' < "$REPO_ROOT/k8s/puna.yaml.tpl" > "$REPO_ROOT/k8s/_rendered/puna.yaml"

kubectl apply -f "$REPO_ROOT/k8s/namespace.yaml"
kubectl apply -f "$REPO_ROOT/k8s/redis.yaml"
kubectl apply -f "$REPO_ROOT/k8s/configmap.yaml"
kubectl apply -f "$REPO_ROOT/k8s/netpol.yaml"
kubectl apply -f "$REPO_ROOT/k8s/_rendered/puna.yaml"

_wait_deploy puna-redis
_wait_deploy puna

echo ""
echo "[puna] deployed $PUNA_IMAGE"
echo "  kubectl exec -it -n puna deploy/puna -c claudex -- puna"
echo "  kubectl exec -it -n puna deploy/puna -c claudex -- puna --think"
