# PUNA — Coding Agent on Kubernetes

**Juan Cordero** — Data / Platform Engineer
[LinkedIn](https://www.linkedin.com/in/juan-cordero-034989112/) · [GitHub](https://github.com/jjcorderomejia) · jjcorderomejia@gmail.com

---

A self-hosted coding agent running on Kubernetes. Claudex (Claude Code CLI) runs in a pod, routes every API call through a LiteLLM sidecar to DeepSeek, and caches responses in Redis. You connect via `kubectl exec` and get a full coding assistant with persistent workspace storage — no cloud subscription, no data leaving your cluster.

---

## How it works

```mermaid
flowchart LR
    Dev(["kubectl exec\n(claudex container)"])
    LiteLLM["LiteLLM sidecar\n127.0.0.1:4000"]
    Redis[("Redis\nresponse cache")]
    DeepSeek["DeepSeek API\ndeepseek-chat / deepseek-reasoner"]
    Workspace[("PVC\n/workspace")]

    Dev -->|OpenAI-compat API| LiteLLM
    LiteLLM -->|cache hit| Redis
    LiteLLM -->|cache miss| DeepSeek
    DeepSeek -->|response| LiteLLM
    LiteLLM -->|cached response| Redis
    Dev --- Workspace
```

Claudex starts with `CLAUDE_CODE_USE_OPENAI=1` pointing at `http://localhost:4000`. LiteLLM receives the request, checks Redis (TTL 2h), and either returns the cached response or forwards to DeepSeek. The model names Claudex sees (`deepseek-chat`, `deepseek-reasoner`) are patched into the source before the Docker build — the `/model` picker shows only the two DeepSeek models.

Two models are available:

| Model | Use |
|-------|-----|
| `deepseek-chat` (V3) | Default — all coding tasks, 60s timeout |
| `deepseek-reasoner` (R1) | Architecture decisions, complex debugging, algorithm design, 300s timeout |

---

## Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Agent CLI | Claudex (Claude Code fork) | vendored |
| API router | LiteLLM | v1.83.10 (pinned) |
| Response cache | Redis | 7-alpine |
| Inference | DeepSeek API | V3 / R1 |
| Workspace storage | K8s PVC (local-path) | — |
| Registry | GHCR | — |
| Platform | Kubernetes | — |

---

## Design decisions

**LiteLLM runs as a sidecar, not a separate service.** Claudex and LiteLLM share `localhost:4000` — no service discovery, no network policy to manage, no cross-pod latency. The tradeoff is that scaling the pod scales both containers together, which is acceptable for a single-user coding agent.

**Model names are patched at build time, not at runtime.** Claudex hardcodes Anthropic model identifiers in its source. `patch/model-picker.sh` runs `sed` over the vendored TypeScript before `bun build` — the resulting binary never references Anthropic models. A runtime shim would need to intercept model-list API calls; the build-time patch is simpler and more complete.

**Claudex source is vendored, not pulled at build time.** `vendor.sh` clones Claudex once and strips the `.git` directory. The Dockerfile only needs local files — no outbound network calls during `docker build`, no dependency on the upstream repo being available. Run `./vendor.sh` again to refresh.

**Secrets are typed once, never stored.** `deploy.sh` prompts for the GHCR token and DeepSeek API key on first run and passes them directly to `kubectl create secret`. `LITELLM_MASTER_KEY` and `REDIS_PASSWORD` are generated with `openssl rand -hex 32` — no human ever sees them. All subsequent deploys skip the prompt if the secrets already exist.

**The manifest is a template, not a static file.** `k8s/puna.yaml.tpl` contains `${GIT_SHA}` — `deploy.sh` runs `envsubst` to produce `k8s/_rendered/puna.yaml` before applying. Every deployed pod is traceable to the exact commit that built it.

**Redis requires a password.** The password is auto-generated at bootstrap and mounted from `puna-secrets/REDIS_PASSWORD` into both the LiteLLM config and the `wait-for-redis` init container. Unauthenticated Redis is not used.

---

## Deploy

```bash
# Step 1 — vendor Claudex source (run once)
./vendor.sh

# Step 2 — build image, bootstrap secrets, apply K8s manifests
./deploy.sh --build
```

On first run `deploy.sh` prompts for two tokens:
- **GHCR PAT** (`read:packages` + `write:packages`) — to push and pull the image
- **DeepSeek API key** — for inference

Everything else generates automatically. Subsequent deploys (no `--build`) skip the build and re-apply manifests only — useful for config changes.

---

## Connect

```bash
# Standard mode
kubectl exec -it -n puna deploy/puna -c claudex -- puna

# Reasoning mode (R1)
kubectl exec -it -n puna deploy/puna -c claudex -- puna --think
```

Work persists in the PVC at `/workspace` across pod restarts.

---

## Repo layout

```
puna/
├── agent/
│   ├── CLAUDE.md           # agent persona and behavior rules
│   ├── settings.json       # model defaults, telemetry off
│   └── puna                # entrypoint wrapper
├── k8s/
│   ├── namespace.yaml
│   ├── puna.yaml.tpl       # main deployment template (${GIT_SHA})
│   ├── redis.yaml
│   ├── pvc.yaml
│   └── configmap.yaml      # LiteLLM config mounted into sidecar
├── litellm/
│   └── config.yaml         # model routing, Redis cache, timeouts
├── patch/
│   └── model-picker.sh     # patches Claudex source model list pre-build
├── Dockerfile              # multi-stage: build Claudex → runtime image
├── vendor.sh               # clone + strip Claudex source once
└── deploy.sh               # bootstrap secrets, build, apply manifests
```
