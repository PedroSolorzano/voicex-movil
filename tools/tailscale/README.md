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

### Ni "Connected" ni `tailscale ping` prueban que el teléfono encamine

Comprobado en la práctica, y engaña en cuatro sitios a la vez. La consola web
decía **Connected** en las dos máquinas; la app del teléfono decía
**Connected**; `tailscale status` daba `active; relay "mia"`; `tailscale ping`
respondía en 83 ms; y hasta el handshake de WireGuard se renovaba. Con todo eso,
el teléfono no alcanzaba **ni un solo puerto** del servidor.

La VPN estaba a medio establecer: Android la daba por conectada y declaraba la
ruta, pero **el kernel no tenía ninguna ruta instalada hacia el túnel**.

Por qué cada señal miente:

- **`tailscale ping` viaja por magicsock**, el canal de control, y ni siquiera
  pasa por la interfaz. Responde aunque el camino de datos esté muerto. Es la
  trampa más cara de las cuatro.
- **"Connected" y el handshake** solo dicen que los dos nodos se conocen y
  tienen sesión, no que el sistema operativo meta tráfico dentro.
- **`ip addr show tun0` puede decir `DOWN`** en Android incluso cuando la VPN
  funciona: el interfaz lo gestiona `VpnService` por descriptor, no por netlink.
  No sirve como prueba en ninguno de los dos sentidos.

Las dos comprobaciones que sí valen. En el **servidor**, los contadores del
interfaz: si `RX` está en unos pocos paquetes mientras `TX` sube, no entra nada.

```bash
ip -s link show tailscale0
```

Y en el **teléfono**, las rutas de verdad, no las declaradas:

```bash
adb shell ip route show table all | grep tun0
```

Si lo único que sale es `local 100.x.y.z dev tun0 ... scope host`, la VPN no ha
instalado ninguna ruta y **nada va por el túnel**, diga lo que diga el panel. El
síntoma en la app es un timeout limpio, no una conexión rechazada, que es justo
lo que hace parecer que el problema está en el servidor.

**Cómo se arregla:** apagar y encender Tailscale en el teléfono. Al reconectar
vuelve a instalar las rutas.

## Parar

```bash
docker compose -f tools/tailscale/docker-compose.yml down
```
