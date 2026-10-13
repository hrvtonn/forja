# syntax=docker/dockerfile:1.7

# ---------- Estágio 1: build (dependências de desenvolvimento + compilação TS) ----------
FROM node:26-alpine3.24 AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build \
 && npm prune --omit=dev

# ---------- Estágio 2: runtime (Alpine puro + binário do Node, sem npm/yarn) ----------
FROM alpine:3.24 AS runtime

ENV NODE_ENV=production \
    PORT=3000

# libstdc++/libgcc: dependências do binário do Node | tini: init que repassa SIGTERM
RUN apk add --no-cache libstdc++ libgcc tini \
 && addgroup -g 1000 node \
 && adduser -u 1000 -G node -s /sbin/nologin -D node

COPY --from=build /usr/local/bin/node /usr/local/bin/node

WORKDIR /app

# Arquivos pertencem ao root e são apenas lidos pelo usuário "node" (sem escrita em runtime)
COPY --from=build /app/package.json ./package.json
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist

USER 1000:1000
EXPOSE 3000

HEALTHCHECK --interval=15s --timeout=3s --start-period=20s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:3000/health || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/server.js"]
