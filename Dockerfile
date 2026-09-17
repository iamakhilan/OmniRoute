# Render-optimized Docker image.
# Render only needs the OmniRoute API gateway, so use the project's backend-only
# Next.js build mode and keep the builder deliberately memory-constrained.

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

# The Next.js config imports build-time tooling such as fumadocs-mdx. NODE_ENV=production
# would make npm ci omit devDependencies, causing the build to fail before Next can compile.
# Include dev dependencies in the builder; the final runtime image only copies the standalone
# production bundle and the native SQLite binding.
RUN --mount=type=cache,id=omniroute-npm-cache,target=/root/.npm,sharing=locked \
    npm ci --include=dev --include=optional --no-audit --no-fund --legacy-peer-deps --ignore-scripts \
    && (cd node_modules/better-sqlite3 \
        && node /usr/local/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js rebuild) \
    && node -e "require('better-sqlite3')(':memory:').close()" \
    && node -e "const wreq=require('wreq-js'); if(typeof wreq.createTransport!=='function') process.exit(1)"

COPY . ./

# The environment above already enables backend-only mode, so invoke the build
# script directly instead of npm run build:backend (which requires cross-env).
RUN mkdir -p /app/data \
    && node --input-type=module -e "import c from './next.config.mjs'; console.log('=== EFFECTIVE NEXT CONFIG ==='); console.log('OMNIROUTE_BUILD_PROFILE=', process.env.OMNIROUTE_BUILD_PROFILE); console.log('OMNIROUTE_BUILD_BACKEND_ONLY=', process.env.OMNIROUTE_BUILD_BACKEND_ONLY); console.log('NEXT_DIST_DIR=', process.env.NEXT_DIST_DIR); console.log('config.output=', c.output); console.log('config.distDir=', c.distDir); console.log('config.outputFileTracingRoot=', c.outputFileTracingRoot); console.log('=== END EFFECTIVE NEXT CONFIG ===')" \
    && node scripts/build/build-next-isolated.mjs \
    && find /app/.build/next -maxdepth 4 -type d -name standalone -print \
    && find /app/.build/next -maxdepth 3 -type f -name '*.nft.json' -print | head -40 \
    && node --input-type=module -e "import { existsSync, lstatSync, realpathSync, readlinkSync } from 'node:fs'; const paths=['/app/.build/next/standalone','/app/.build/next/standalone/node_modules','/app/.build/next/standalone/node_modules/@atjsh','/app/.build/next/standalone/node_modules/@atjsh/llmlingua-2','/app/.build/next/standalone/node_modules/@atjsh/llmlingua-2/dist','/app/.build/next/standalone/node_modules/@atjsh/llmlingua-2/dist/index.js','/app/node_modules/@atjsh/llmlingua-2','/app/node_modules/@atjsh/llmlingua-2/dist']; console.log('=== STANDALONE TOPOLOGY ==='); for (const p of paths) { console.log('PATH:',p); if (!existsSync(p) && !(() => { try { return lstatSync(p).isSymbolicLink(); } catch { return false; } })()) { console.log('MISSING'); continue; } try { const s=lstatSync(p); console.log('isSymlink:',s.isSymbolicLink()); if (s.isSymbolicLink()) console.log('link:',readlinkSync(p)); console.log('realpath:',realpathSync(p)); } catch(e) { console.log('ERROR:',e.message); } } console.log('=== NODE RESOLUTION ==='); import { createRequire } from 'node:module'; const req=createRequire('/app/.build/next/standalone/package.json'); console.log('standalone node_modules paths:',req.resolve.paths('@atjsh/llmlingua-2')); try { console.log('resolved package:',req.resolve('@atjsh/llmlingua-2')); } catch(e) { console.log('RESOLVE ERROR:',e.message); } console.log('=== END TOPOLOGY ===');" \
    && node --input-type=module -e "import { colocateLlmlinguaOptionals, SEED_PACKAGES } from './scripts/build/colocateOptionals.mjs'; colocateLlmlinguaOptionals({ rootDir: '/app', targetNodeModulesDir: '/app/.build/next/standalone/node_modules', seeds: [...SEED_PACKAGES, '@huggingface/transformers'], log: (message) => console.log('[docker-standalone-repair] ' + message.trim()) });" \
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
