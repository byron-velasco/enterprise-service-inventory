# Dockerfile para desplegar Backstage en OpenShift (namespace backstage-poc)
# Ejecutar desde la raiz de tu app (enterprise-service-inventory), despues de:
#  1) Tener el package.json con "resolutions": { "undici": "7.16.0", ... } ya agregado
#  2) Tener la carpeta catalog/ con los catalog-info.yaml en la raiz
#  3) Tener app-config.production.yaml (el de este mismo set) en la raiz

FROM node:22-bookworm AS build

WORKDIR /app

# Herramientas necesarias para compilar los modulos nativos
# (better-sqlite3, isolated-vm, keytar, etc.) - mismas que usamos en la POC local
RUN apt-get update && apt-get install -y \
    python3 make g++ pkg-config libsecret-1-dev \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

COPY . .

RUN corepack enable
RUN yarn install
RUN yarn build:backend --config /app/app-config.yaml --config /app/app-config.production.yaml

FROM node:22-bookworm-slim

WORKDIR /app

# libsecret es requerido en runtime tambien (no solo en build) por @backstage/backend-defaults
RUN apt-get update && apt-get install -y \
    libsecret-1-0 \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /app/packages/backend/dist/bundle.tar.gz .
COPY --from=build /app/catalog ./catalog
COPY --from=build /app/app-config.yaml ./
COPY --from=build /app/app-config.production.yaml ./

RUN tar xzf bundle.tar.gz && rm bundle.tar.gz

# OpenShift corre contenedores con UID aleatorio, no root: aseguramos permisos de grupo
RUN chgrp -R 0 /app && chmod -R g=u /app

ENV NODE_ENV=production
EXPOSE 7007

ENTRYPOINT ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
