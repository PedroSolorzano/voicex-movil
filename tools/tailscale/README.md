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

Desde 0.7.0 la dirección **no se escribe en Ajustes**: va compilada en el APK y
apunta al proxy, que es quien valida el token (ver
[`tools/proxy/README.md`](../proxy/README.md) y
[`tools/release/README.md`](../release/README.md)). Kokoro y Piper ya solo
escuchan en loopback, así que `100.x.y.z:8880` no responde a nadie.

El teléfono necesita Tailscale instalado, logueado con la misma cuenta **y con
la VPN encendida**.

### `tailscale status` no prueba que el teléfono encamine

Comprobado en la práctica, y engaña: `tailscale status` decía
`active; relay "mia"` y `tailscale ping` respondía en 83 ms, y aun así el
teléfono no alcanzaba ni un puerto del servidor. Su interfaz estaba caída:

```
37: tun0: <POINTOPOINT> mtu 1280 ... state DOWN
    inet 100.78.120.70/32
```

El proceso de Tailscale sigue hablando con el relevo —de ahí el ping y el
"active"— mientras la VPN de Android está apagada. Con la interfaz caída,
Android enruta las direcciones `100.x` por el WiFi normal, salen a internet y se
pierden. El síntoma es un **timeout limpio**, no una conexión rechazada, que es
justo lo que despista: parece el servidor y es el teléfono.

Para saberlo, pregúntale al teléfono y no al servidor:

```bash
adb shell ip -4 addr show tun0        # tiene que decir UP
adb shell ip route get 100.91.42.26   # tiene que salir por tun0, no por wlan0
```

Si dice `via 192.168.x.1 dev wlan0`, la VPN está apagada por mucho que el panel
de Tailscale diga lo contrario.

## Parar

```bash
docker compose -f tools/tailscale/docker-compose.yml down
```
