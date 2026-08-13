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

# libsecret y herramientas de compilacion son requeridas en runtime tambien,
# porque yarn workspaces focus puede necesitar recompilar modulos nativos
RUN apt-get update && apt-get install -y \
    libsecret-1-0 python3 make g++ pkg-config libsecret-1-dev \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*

# El bundle.tar.gz NO incluye node_modules - hay que instalarlos aqui usando
# el skeleton.tar.gz (contiene todos los package.json del monorepo) para que
# yarn instale solo las dependencias de produccion, sin devDependencies pesadas
COPY --from=build /app/yarn.lock ./
COPY --from=build /app/package.json ./
COPY --from=build /app/.yarnrc.yml ./
COPY --from=build /app/.yarn ./.yarn
COPY --from=build /app/packages/backend/dist/skeleton.tar.gz ./
RUN tar xzf skeleton.tar.gz && rm skeleton.tar.gz

RUN corepack enable
# umask 0002: los archivos que yarn instale ya nacen con permisos de grupo=owner,
# evitando tener que recorrer node_modules completo despues con chmod -R (esa
# operacion sobre miles de archivos pequenos es la que agota la memoria del build)
RUN umask 0002 && yarn workspaces focus --all --production

COPY --from=build /app/packages/backend/dist/bundle.tar.gz .
COPY --from=build /app/catalog ./catalog
COPY --from=build /app/app-config.yaml ./
COPY --from=build /app/app-config.production.yaml ./

RUN tar xzf bundle.tar.gz && rm bundle.tar.gz

# OpenShift corre contenedores con UID aleatorio, no root: aseguramos permisos de grupo.
# Ya NO tocamos node_modules aqui (nacio con permisos correctos gracias al umask arriba),
# solo las carpetas/archivos que SI se generaron despues sin ese umask.
RUN chgrp -R 0 /app/packages /app/catalog /app/app-config.yaml /app/app-config.production.yaml \
    && chmod -R g=u /app/packages /app/catalog /app/app-config.yaml /app/app-config.production.yaml

ENV NODE_ENV=production
EXPOSE 7007

ENTRYPOINT ["node", "packages/backend", "--config", "app-config.yaml", "--config", "app-config.production.yaml"]
