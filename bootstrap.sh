#!/usr/bin/env bash
# One-click PUNA installer. Run on any server with kubectl access to a K8s cluster.
# Prerequisites: kubectl (configured), openssl
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

_check_prereqs() {
  local missing=()
  for cmd in kubectl openssl; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "[puna] missing prerequisites: ${missing[*]}" >&2
    exit 1
  fi
  kubectl cluster-info &>/dev/null || { echo "[puna] kubectl cannot reach a cluster" >&2; exit 1; }
}

_wait_deploy() { kubectl -n puna rollout status deployment/"$1" --timeout=120s; }

echo "[puna] checking prerequisites..."
_check_prereqs

# ── 0. Namespace ──────────────────────────────────────────────────────────────
kubectl apply -f "$REPO_ROOT/k8s/namespace.yaml"

# ── 1. Secrets (idempotent) ──────────────────────────────────────────────────

# Registry pull secret — read-only token, never touches Docker
if ! kubectl -n puna get secret ghcr-creds &>/dev/null; then
  read -rp "Registry server (default: ghcr.io): " REGISTRY
  REGISTRY="${REGISTRY:-ghcr.io}"
  read -rp "Registry username: " REG_USER
  read -s -p "Registry read-only token: " REG_TOKEN
  echo
  kubectl -n puna create secret docker-registry ghcr-creds \
    --docker-server="$REGISTRY" \
    --docker-username="$REG_USER" \
    --docker-password="$REG_TOKEN"
  unset REG_TOKEN
fi

# App secrets — DeepSeek key typed once; all other secrets auto-generated
if ! kubectl -n puna get secret puna-secrets &>/dev/null; then
  read -s -p "DeepSeek API key: " DEEPSEEK_API_KEY
  echo
  kubectl -n puna create secret generic puna-secrets \
    --from-literal=DEEPSEEK_API_KEY="$DEEPSEEK_API_KEY" \
    --from-literal=LITELLM_MASTER_KEY="$(openssl rand -hex 32)" \
    --from-literal=REDIS_PASSWORD="$(openssl rand -hex 32)"
  unset DEEPSEEK_API_KEY
fi

# GitHub PAT for MCP server
if ! kubectl -n puna get secret puna-github &>/dev/null; then
  read -s -p "GitHub Personal Access Token (for MCP): " GITHUB_PAT
  echo
  kubectl -n puna create secret generic puna-github \
    --from-literal=GITHUB_PERSONAL_ACCESS_TOKEN="$GITHUB_PAT"
  unset GITHUB_PAT
fi

# Postgres secret — auto-generated, separate from puna-secrets
if ! kubectl -n puna get secret puna-postgres-secret &>/dev/null; then
  kubectl -n puna create secret generic puna-postgres-secret \
    --from-literal=POSTGRES_PASSWORD="$(openssl rand -hex 32)"
fi

# ── 2. Manifests ──────────────────────────────────────────────────────────────

export PUNA_IMAGE="${PUNA_IMAGE:-ghcr.io/jjcorderomejia/puna-claudex:latest}"
export HOST_HOME="${HOST_HOME:-$HOME}"
export STORAGE_CLASS="${STORAGE_CLASS:-local-path}"

mkdir -p "$REPO_ROOT/k8s/_rendered"
envsubst '${PUNA_IMAGE} ${HOST_HOME}' < "$REPO_ROOT/k8s/puna.yaml.tpl"    > "$REPO_ROOT/k8s/_rendered/puna.yaml"
envsubst '${STORAGE_CLASS}'           < "$REPO_ROOT/k8s/postgres.yaml.tpl" > "$REPO_ROOT/k8s/_rendered/postgres.yaml"

kubectl apply -f "$REPO_ROOT/k8s/namespace.yaml"
kubectl apply -f "$REPO_ROOT/k8s/_rendered/postgres.yaml"
kubectl apply -f "$REPO_ROOT/k8s/redis.yaml"
kubectl apply -f "$REPO_ROOT/k8s/configmap.yaml"
kubectl apply -f "$REPO_ROOT/k8s/netpol.yaml"
kubectl apply -f "$REPO_ROOT/k8s/_rendered/puna.yaml"

# ── 3. Wait for healthy rollout ───────────────────────────────────────────────
echo "[puna] waiting for rollout..."
_wait_deploy puna-postgres
_wait_deploy puna-redis
_wait_deploy puna

# ── 4. Install local puna wrapper ─────────────────────────────────────────────
WRAPPER=/usr/local/bin/puna
cat > /tmp/puna-wrapper <<'EOF'
#!/usr/bin/env bash
exec kubectl exec -it -n puna deploy/puna -c claudex -- puna "$@"
EOF
if install -m 755 /tmp/puna-wrapper "$WRAPPER" 2>/dev/null; then
  echo "[puna] installed wrapper → $WRAPPER"
elif sudo install -m 755 /tmp/puna-wrapper "$WRAPPER"; then
  echo "[puna] installed wrapper → $WRAPPER (sudo)"
else
  echo "[puna] could not install to $WRAPPER — add this to your shell:" >&2
  echo "  alias puna='kubectl exec -it -n puna deploy/puna -c claudex -- puna'" >&2
fi
rm -f /tmp/puna-wrapper

echo ""
echo "[puna] ready."
echo "  puna                        # start in home dir"
echo "  puna /path/to/project       # start in a specific project"
echo "  puna --think /path/project  # R1 reasoning mode"
