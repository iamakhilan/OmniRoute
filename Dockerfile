# Render-optimized Docker image.
# The default OmniRoute image builds the full Next.js dashboard and also keeps
# runner-web/runner-cli stages. Render only needs the API gateway, so this image
# uses the project's backend-only build mode and a single Next.js page worker.

FROM node:26-trixie-slim AS base
WORKDIR /app

RUN --mount=type=cache,id=omniroute-apt-cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=omniroute-apt-lists,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends libsecret-1-0 ca-certificates \
    && rm -rf /var/lib/apt/lists/*

FROM base AS builder

ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production
ENV OMNIROUTE_USE_TURBOPACK=0
ENV OMNIROUTE_BUILD_BACKEND_ONLY=1
ENV OMNIROUTE_BUILD_PROFILE=backend
ENV OMNIROUTE_BUILD_MEMORY_MB=1536
ENV CIRCLE_NODE_TOTAL=2
ENV OMNIROUTE_MITM_STUB=1
ENV NPM_CONFIG_LEGACY_PEER_DEPS=true
ENV NEXT_DIST_DIR=/app/.build/next

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 make g++ \
    && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
COPY open-sse/package.json ./open-sse/package.json
COPY scripts/build/postinstall.mjs ./scripts/build/postinstall.mjs
COPY scripts/build/postinstallSupport.mjs ./scripts/build/postinstallSupport.mjs
COPY scripts/build/native-binary-compat.mjs ./scripts/build/native-binary-compat.mjs

RUN test -f package-lock.json \
    || (echo "package-lock.json is required for reproducible Docker builds" >&2 && exit 1)

RUN --mount=type=cache,id=omniroute-npm-cache,target=/root/.npm,sharing=locked \
    npm ci --include=optional --no-audit --no-fund --legacy-peer-deps --ignore-scripts \
    && (cd node_modules/better-sqlite3 \
        && node /usr/local/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js rebuild) \
    && node -e "require('better-sqlite3')(':memory:').close()" \
    && node -e "const wreq=require('wreq-js'); if(typeof wreq.createTransport!=='function') process.exit(1)"

COPY . ./

# Backend-only mode stubs the ~126 dashboard leaf pages and layouts during the
# build while preserving every route.ts API handler. This removes the heavy
# dashboard client graph (Monaco, Recharts, XYFlow, Mermaid, icon packs) from
# the production compilation and is specifically intended for headless/API
# deployments.
RUN mkdir -p /app/data \
    && npm run build:backend \
    && node --input-type=module -e "import { createRequire } from 'node:module'; import { pathToFileURL } from 'node:url'; const standaloneRoot = '/app/.build/next/standalone/node_modules/'; const require = createRequire('/app/.build/next/standalone/package.json'); for (const pkg of ['@atjsh/llmlingua-2', '@huggingface/transformers', 'js-tiktoken']) { const resolved = require.resolve(pkg); if (!resolved.startsWith(standaloneRoot)) throw new Error(pkg + ' resolved outside standalone: ' + resolved); await import(pathToFileURL(resolved).href); } const onnxRuntime = require.resolve('onnxruntime-node'); if (!onnxRuntime.startsWith(standaloneRoot)) throw new Error('onnxruntime-node resolved outside standalone: ' + onnxRuntime); await import(pathToFileURL(onnxRuntime).href);"

FROM base AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=20128
ENV HOSTNAME=0.0.0.0
ENV DATA_DIR=/app/data
ENV OMNIROUTE_MIGRATIONS_DIR=/app/migrations
ENV OMNIROUTE_MEMORY_MB=6144
ENV NODE_OPTIONS=--max-old-space-size=6144

RUN mkdir -p /app/data

COPY --from=builder /app/.build/next/standalone ./
COPY --from=builder /app/node_modules/better-sqlite3 ./node_modules/better-sqlite3
COPY --from=builder /app/scripts/dev/healthcheck.mjs ./healthcheck.mjs
COPY --from=builder /app/scripts/check-permissions.sh ./check-permissions.sh

RUN chown -R node:node /app
USER node

EXPOSE 20128

ENTRYPOINT ["/app/check-permissions.sh"]
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 CMD ["node", "healthcheck.mjs"]
CMD ["node", "dev/run-standalone.mjs"]
