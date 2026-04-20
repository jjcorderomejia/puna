#!/usr/bin/env bash
set -euo pipefail

export REGISTRY=ghcr.io
export ORG=jjcorderomejia
export IMAGE_NS=$REGISTRY/$ORG
export REPO_ROOT=/home/jjcm/puna
export GIT_SHA=$(git -C $REPO_ROOT rev-parse --short HEAD)

echo "GIT_SHA=${GIT_SHA}"

_wait_deploy() { kubectl -n puna rollout status deployment/"$1" --timeout=120s; }

# ── 0. Namespace first ────────────────────────────────────────────────────────
kubectl apply -f k8s/namespace.yaml

# ── 1. Bootstrap secrets (idempotent — skipped if already exist) ──────────────

# ghcr-creds — external GitHub PAT, typed once, never stored in files
if ! kubectl -n puna get secret ghcr-creds &>/dev/null; then
  read -s -p "Enter GHCR token (GitHub PAT with read:packages): " GHCR_TOKEN
  echo
  kubectl -n puna create secret docker-registry ghcr-creds \
    --docker-server=ghcr.io \
    --docker-username=jjcorderomejia \
    --docker-password="${GHCR_TOKEN}"
  unset GHCR_TOKEN
fi

# puna-secrets — DeepSeek key typed once; LITELLM_MASTER_KEY auto-generated
if ! kubectl -n puna get secret puna-secrets &>/dev/null; then
  read -s -p "Enter DeepSeek API key: " DEEPSEEK_API_KEY
  echo
  kubectl -n puna create secret generic puna-secrets \
    --from-literal=DEEPSEEK_API_KEY="${DEEPSEEK_API_KEY}" \
    --from-literal=LITELLM_MASTER_KEY="$(openssl rand -hex 32)"
  unset DEEPSEEK_API_KEY
fi

# ── 2. Build & push ───────────────────────────────────────────────────────────
if [[ "${1:-}" == "--build" ]]; then
  if [[ ! -d "$REPO_ROOT/claudex-src" ]]; then
    echo "[puna] claudex-src not found — run ./vendor.sh first"
    exit 1
  fi
  echo "[puna] Building $IMAGE_NS/puna-claudex:$GIT_SHA"
  docker build -t "$IMAGE_NS/puna-claudex:$GIT_SHA" "$REPO_ROOT"
  docker push "$IMAGE_NS/puna-claudex:$GIT_SHA"
fi

# ── 3. Apply manifests ────────────────────────────────────────────────────────
kubectl apply -f k8s/pvc.yaml
kubectl apply -f k8s/redis.yaml
kubectl apply -f k8s/configmap.yaml

envsubst '${GIT_SHA}' < k8s/puna.yaml | kubectl apply -f -

# ── 4. Wait ───────────────────────────────────────────────────────────────────
_wait_deploy puna-redis
_wait_deploy puna

echo ""
echo "[puna] Done. Connect with:"
echo "  kubectl exec -it -n puna deploy/puna -c claudex -- puna"
echo "  kubectl exec -it -n puna deploy/puna -c claudex -- puna --think"
