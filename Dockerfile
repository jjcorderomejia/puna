FROM node:20-alpine AS builder

RUN apk add --no-cache bash curl unzip

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

WORKDIR /build
COPY claudex-src/ .

RUN bun install --frozen-lockfile
RUN bun run build
RUN mkdir -p /tmp/claudex-pkg && npm pack --pack-destination /tmp/claudex-pkg

FROM node:20-alpine

RUN apk add --no-cache bash git jq kubectl gettext openssh

RUN --mount=type=bind,from=builder,source=/tmp/claudex-pkg,target=/tmp/claudex-pkg \
    npm install -g /tmp/claudex-pkg/*.tgz

RUN mkdir -p /home/node/.claude /workspace \
    && chown -R node:node /home/node /workspace

COPY --chown=node:node agent/settings.json /home/node/.claude/settings.json
COPY --chown=node:node agent/claude-config.json /home/node/.claude.json
COPY --chown=node:node agent/CLAUDE.md /home/node/.claude/CLAUDE.md
COPY agent/puna /usr/local/bin/puna
RUN chmod +x /usr/local/bin/puna

USER node
WORKDIR /workspace

ENV CLAUDE_CODE_USE_OPENAI=1
ENV OPENAI_BASE_URL=http://localhost:4000
ENV OPENAI_API_KEY=sk-puna-local
ENV OPENAI_MODEL=deepseek-chat
ENV NODE_TLS_REJECT_UNAUTHORIZED=1
ENV HOME=/home/node

CMD ["tail", "-f", "/dev/null"]
