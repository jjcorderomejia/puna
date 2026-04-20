FROM node:20-alpine AS builder

RUN apk add --no-cache bash curl unzip

# Install bun (Claudex build tool)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

# ── Build Claudex from vendored source ────────────────────────────────────────
WORKDIR /build
COPY claudex-src/ .

RUN bun install --frozen-lockfile
RUN bun run build

# Pack for clean install
RUN npm pack --pack-destination /tmp/claudex-pkg

# ── Runtime image ──────────────────────────────────────────────────────────────
FROM node:20-alpine

RUN apk add --no-cache bash git jq

# Install from local pack — zero network calls
RUN --mount=type=bind,from=builder,source=/tmp/claudex-pkg,target=/tmp/claudex-pkg \
    npm install -g /tmp/claudex-pkg/*.tgz

# ── Agent config ───────────────────────────────────────────────────────────────
RUN mkdir -p /root/.claude /workspace

COPY agent/settings.json /root/.claude/settings.json
COPY agent/CLAUDE.md /workspace/CLAUDE.md
COPY agent/puna /usr/local/bin/puna
RUN chmod +x /usr/local/bin/puna

WORKDIR /workspace

ENV CLAUDE_CODE_USE_OPENAI=1
ENV OPENAI_BASE_URL=http://localhost:4000
ENV OPENAI_API_KEY=sk-puna-local
ENV OPENAI_MODEL=deepseek-chat
ENV NODE_TLS_REJECT_UNAUTHORIZED=1

CMD ["puna"]
