FROM node:20-alpine AS builder

RUN apk add --no-cache bash curl unzip

RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

WORKDIR /build
COPY claudex-src/ .

RUN bun install --frozen-lockfile
RUN bun run build
RUN npm pack --pack-destination /tmp/claudex-pkg

FROM node:20-alpine

RUN apk add --no-cache bash git jq

RUN --mount=type=bind,from=builder,source=/tmp/claudex-pkg,target=/tmp/claudex-pkg \
    npm install -g /tmp/claudex-pkg/*.tgz

RUN addgroup -S puna && adduser -S -G puna -u 1000 puna

RUN mkdir -p /home/puna/.claude /workspace \
    && chown -R puna:puna /home/puna /workspace

COPY --chown=puna:puna agent/settings.json /home/puna/.claude/settings.json
COPY --chown=puna:puna agent/CLAUDE.md /workspace/CLAUDE.md
COPY agent/puna /usr/local/bin/puna
RUN chmod +x /usr/local/bin/puna

USER puna
WORKDIR /workspace

ENV CLAUDE_CODE_USE_OPENAI=1
ENV OPENAI_BASE_URL=http://localhost:4000
ENV OPENAI_API_KEY=sk-puna-local
ENV OPENAI_MODEL=deepseek-chat
ENV NODE_TLS_REJECT_UNAUTHORIZED=1
ENV HOME=/home/puna

CMD ["puna"]
