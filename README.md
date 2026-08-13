# Despliegue en OpenShift — namespace backstage-poc

Checklist de archivos que deben estar en la raíz de `enterprise-service-inventory/`
antes de construir la imagen:

- [ ] `package.json` con `"resolutions": { "undici": "7.16.0", ... }` agregado
      (evita el bug de compilación nativa que topamos en local)
- [ ] `catalog/api-rest-consultarproducto.yaml`
- [ ] `catalog/api-soap-calculator.yaml`
- [ ] `app-config.production.yaml` (el de este set, con rutas `./catalog/...`)
- [ ] `Dockerfile` (el de este set, Node 22 + herramientas de compilación)
- [ ] `"engines": { "node": "22 || 24" }` ya viene en tu package.json — coincide
      con la imagen base del Dockerfile, no hace falta tocarlo

## Paso 1 — Construir la imagen

Desde la raíz de `enterprise-service-inventory/`:

```bash
docker build -t backstage-esi:latest .
```

Tarda varios minutos (compila los mismos módulos nativos que vimos en local:
better-sqlite3, isolated-vm, etc. — con las herramientas ya incluidas en el
Dockerfile no debería fallar).

## Paso 2 — Subir la imagen al registry de OpenShift

```bash
oc login <tu-cluster>
oc new-project backstage-poc   # si aún no existe

# Habilita push directo al registry interno (una sola vez)
oc registry login   # o docker login con el token, según tu setup

docker tag backstage-esi:latest \
  image-registry.openshift-image-registry.svc:5000/backstage-poc/backstage:latest
docker push image-registry.openshift-image-registry.svc:5000/backstage-poc/backstage:latest
```

Si no tienes acceso directo al registry interno desde tu red, alternativa:
`oc image build` o subir a un registry externo (Docker Hub, Quay) y ajustar
la referencia de imagen en `openshift/backstage.yaml`.

## Paso 3 — Aplicar los manifiestos

```bash
oc project backstage-poc
oc apply -f openshift/postgres.yaml
oc apply -f openshift/backstage.yaml
```

Antes de este paso, revisa:
- `openshift/postgres.yaml`: cambia la contraseña de ejemplo en el `Secret`
- `openshift/backstage.yaml`: confirma que la ruta de imagen coincide con el paso 2

## Paso 4 — Obtener la URL y ajustar la config

```bash
oc get route backstage -n backstage-poc
```

Copia el host que te da (ej. `backstage-backstage-poc.apps.tu-cluster.com`),
reemplázalo en `app-config.production.yaml` donde dice `BACKSTAGE_ROUTE_HOST`
(tres apariciones), y repite el Paso 1 y 2 para reconstruir la imagen con la
URL correcta (Backstage necesita conocer su propia URL pública para CORS/CSP).

## Qué deberías ver

Lo mismo que validamos en local: el catálogo con `adrianahoyos-productos-service`
(REST, con Swagger UI) y `calculator-soap-service` (SOAP, con el WSDL), esta vez
accesible desde la URL del Route en vez de `localhost`.

## Siguiente paso después de validar en OpenShift

Repetir el mismo patrón de `catalog-info.yaml` con los servicios reales del
ambiente de QA de la empresa, y registrar esas rutas en `catalog.locations`
de `app-config.production.yaml` en vez de los dos ejemplos públicos.
