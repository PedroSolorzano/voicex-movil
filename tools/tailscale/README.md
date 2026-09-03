# Cliente Tailscale

Deja la computadora dentro de una red privada (tailnet) para que el teléfono
llegue a Kokoro y Piper desde cualquier red, sin exponerlos a internet — ver
`docs/context/ACCESO_REMOTO.md` para el porqué. No hace falta cuenta previa:
se crea con el primer login (SSO con Google/Microsoft/GitHub/Apple o email),
gratis.

## Arrancar

```bash
docker compose -f tools/tailscale/docker-compose.yml up -d
docker exec voicex-tailscale tailscale up --hostname=voicex-server
```

El segundo comando imprime una URL de login. Abrila en el navegador y hacé el
SSO — la primera vez, eso mismo crea la tailnet.

## Verificar

```bash
docker exec voicex-tailscale tailscale status
docker exec voicex-tailscale tailscale ip -4   # IP 100.x.y.z de este nodo
```

## Configurar la tailnet (consola web, una sola vez)

Estos tres pasos son de `login.tailscale.com/admin`, no de la terminal.

1. **MagicDNS y certificados HTTPS** — `admin/dns`: activar **Enable
   MagicDNS** y **HTTPS Certificates**. Habilitan `tailscale cert` y son
   requisito para poder usar Funnel más adelante.
2. **ACL — autorizar (no encender) Funnel para este nodo** — `admin/acls/file`.
   Un dispositivo no se referencia por hostname corto directamente en
   `target`: hay que declararlo primero en `"hosts"` con la IP del paso
   anterior, y recién ahí usarlo en `nodeAttrs`:
   ```json
   "hosts": {
     "voicex-server": "100.x.y.z"
   },
   "nodeAttrs": [
     {
       "target": ["voicex-server"],
       "attr": ["funnel"]
     }
   ],
   ```
   Esto solo autoriza el uso futuro de Funnel — no lo activa. Encenderlo es un
   paso aparte (`tailscale funnel <puerto>`), deliberadamente no incluido acá.

## Conectar el teléfono

En la app: **Ajustes → Motor de voz**, dirección
`http://voicex-server.<tu-tailnet>.ts.net:8880` (Kokoro) o `:5000` (Piper) —
con MagicDNS activado no hace falta memorizar la IP `100.x.y.z`. El teléfono
necesita tener Tailscale instalado y logueado con la misma cuenta.

## Parar

```bash
docker compose -f tools/tailscale/docker-compose.yml down
```
