# VoiceX Móvil — Acceso remoto a los servidores de voz

Kokoro y Piper corren en la computadora, y hoy el teléfono solo los alcanza
dentro de la misma red WiFi. Fuera de casa la app se repliega a Edge o tira del
audio descargado por adelantado. Este documento compara las formas de llegar a
esos servidores desde cualquier red —túneles, VPN de malla y despliegue en la
nube—, todas gratuitas, y explica cuál encaja con cómo está escrita la app.

**El resumen, por si no lees más:** la recomendación es **Tailscale**, y no un
túnel tipo ngrok. La razón no es el precio ni la velocidad, sino que los
servidores no tienen autenticación y un túnel los publica en internet abierto.

---

## Lo que el código exige de cualquier solución

Antes de comparar nada, cuatro hechos de la app condicionan la elección.

**1. Los providers no mandan autenticación de ninguna clase.** Kokoro envía una
sola cabecera, `Content-Type: application/json`
([`kokoro_tts_provider.dart:159`](../../lib/tts/kokoro_tts_provider.dart)), y
Piper lo mismo ([`piper_tts_provider.dart:105`](../../lib/tts/piper_tts_provider.dart)).
Tampoco el servidor la exige: la "API key" de Kokoro-FastAPI es la cadena
`not-needed`, que existe solo porque el cliente de OpenAI obliga a mandar algo,
no porque se compruebe. **Cualquier opción que ponga el servidor en una URL
pública deja tu CPU a disposición de quien la encuentre**, y no hay forma de
evitarlo sin tocar código. Este es el eje que ordena toda la comparativa.

**2. El health check tiene 3 segundos de plazo.** Antes de cada síntesis la app
comprueba `GET /health` en Kokoro
([`kokoro_tts_provider.dart:86-109`](../../lib/tts/kokoro_tts_provider.dart)) o
`GET /info` en Piper
([`piper_tts_provider.dart:47-69`](../../lib/tts/piper_tts_provider.dart)), con
tres segundos de tope y el resultado cacheado 30 s. Si el rodeo por el túnel más
la latencia de la red móvil se comen ese plazo, la app **se repliega a Edge en
silencio** y parece que el servidor está caído. La síntesis en sí va holgada
—180 s en Kokoro, 120 s en Piper—, así que el cuello de botella es el saludo, no
el trabajo.

**3. La respuesta se identifica por su `content-type`**
([`kokoro_tts_provider.dart:181-182`](../../lib/tts/kokoro_tts_provider.dart)):
JSON con el audio en base64 si el servidor es v0.8 o superior, y audio crudo si
no. Cualquier intermediario que interponga una página HTML de aviso rompe ese
parseo aunque el servidor esté perfecto. No es hipotético: es exactamente lo
que hace hoy el plan gratuito de ngrok.

**4. La clave de caché no incluye la dirección del servidor.** `_cacheKeyFor`
([`reader_provider.dart:434-442`](../../lib/ui/providers/reader_provider.dart))
se compone de motor, voz y ritmo. Es la buena noticia del asunto: **el audio
descargado en casa se reutiliza tal cual desde fuera**, y cambiar de dirección,
de túnel o de proveedor no invalida ni un párrafo de lo ya descargado.

Y un matiz honesto antes de seguir: **Edge ya funciona en cualquier red, es
gratis y también da tiempos por palabra.** El motivo para montar acceso remoto
es la calidad de voz de Kokoro y la velocidad de Piper, no la disponibilidad.

---

## Las opciones, de un vistazo

| Opción | Necesita dominio | Expone a internet | Qué habría que cambiar en la app |
|---|---|---|---|
| **Tailscale** | No | **No** | Nada |
| Cloudflare Tunnel rápido | No | Sí, sin auth | Reescribir la URL en cada reinicio |
| Cloudflare Tunnel + Access | **Sí** | Protegido por token | Cabecera de auth (no existe hoy) |
| ngrok gratuito | No | Sí, sin auth | Cabecera para saltar el aviso |
| DDNS + port forwarding | No | Sí, sin auth | Nada, pero cae con CGNAT |
| Hugging Face Spaces | No | Sí, sin auth | Nada si el Space es público |
| Google Cloud Run | No | Sí, sin auth | Health check más tolerante |
| Oracle Cloud Always Free | No | Sí, sin auth | Nada |

Todas son gratuitas. Las tres últimas exigen tarjeta de crédito para darse de
alta, aunque no lleguen a cobrar.

---

## Tailscale — la recomendación

Tailscale monta una **red privada en malla** sobre WireGuard entre tus propios
dispositivos. No es un túnel: no hay URL pública que nadie pueda encontrar. El
teléfono ve la computadora en una dirección `100.x.x.x` reservada para la red, o
por nombre si activas MagicDNS, y **solo tus dispositivos llegan ahí**.

Eso resuelve el problema de fondo. Como el servidor nunca sale a internet, que
Kokoro y Piper no tengan autenticación deja de importar: es el único camino de
esta lista que no obliga ni a escribir código nuevo ni a aceptar un riesgo.

El plan Personal gratuito da **dispositivos ilimitados** y hasta 6 usuarios, sin
tope de ancho de banda, y **atraviesa CGNAT sin abrir un solo puerto** en el
router — que es justo donde se estrella el port forwarding clásico.

**Montarlo:**

1. Instalar Tailscale en la computadora y en el teléfono, e iniciar sesión con
   la misma cuenta en los dos.
2. Averiguar la dirección de la computadora dentro de la red:

   ```bash
   tailscale ip -4
   ```

3. La dirección **no se escribe en Ajustes**: desde la 0.7.0 va compilada
   (ver [`tools/release/README.md`](../../tools/release/README.md)).
   `KOKORO_URL` apunta al **proxy**, no al servidor directo —por ejemplo
   `http://100.x.y.z:8080/kokoro` (o `http://<nombre-del-pc>.<tailnet>.ts.net:8080/kokoro`
   con MagicDNS)— y vive en [`tools/release/kokoro.json`](../../tools/release/kokoro.json),
   trackeado en git porque esa dirección es igual para cualquier compilación;
   lo que no se comparte es `TTS_TOKEN`, que se queda en el `.json` personal
   de cada quien junto con `PIPER_URL` si también lo quiere.
4. Compilar con ese archivo y, ya instalado el APK, pulsar **Probar conexión**
   en Ajustes → Motor de voz para confirmar que responde.

**Kokoro y Piper siguen en loopback** a propósito
([`tools/kokoro/docker-compose.yml:17`](../../tools/kokoro/docker-compose.yml),
[`tools/piper/docker-compose.yml:23`](../../tools/piper/docker-compose.yml)):
ninguno de los dos sabe autenticar, así que lo único alcanzable desde la
interfaz de Tailscale (o la WiFi) es el proxy, que sí escucha en `0.0.0.0` y
exige el token de cada probador
([`tools/proxy/nginx.conf:136-140`](../../tools/proxy/nginx.conf)). Si aun así
no responde, el sospechoso es el firewall de Windows: hay que permitir el
tráfico entrante en la interfaz de Tailscale.

**Ojo con dos cosas.** Android admite **una sola VPN activa a la vez**: si ya
usas otra, tendrás que alternar. Y el cliente queda corriendo en segundo plano,
con el gasto de batería que eso supone —modesto, pero no nulo.

**Estado actual: ya montado.** El cliente de la computadora corre en
[`tools/tailscale`](../../tools/tailscale) (contenedor Docker, no instalación
nativa, para no tocar el sistema operativo) con hostname `voicex-server`. En la
consola de Tailscale (`login.tailscale.com/admin`) ya están activados
**MagicDNS** y **HTTPS Certificates** (`admin/dns`), y el ACL declara el
atributo `funnel` para este nodo (`admin/acls/file`, bloques `hosts` y
`nodeAttrs`) — eso solo lo autoriza para el futuro, **Funnel sigue apagado**:
correrlo (`tailscale funnel <puerto>`) es un paso aparte, deliberadamente no
dado todavía.

---

## Segundo nodo: la laptop con GPU (Chatterbox)

`voicex-server` no tiene GPU (Radeon Vega, fuera de la matriz de soporte de
ROCm — ver [`TTS_ESPANOL.md`](TTS_ESPANOL.md)), así que Chatterbox no puede
vivir ahí. Corre en una laptop personal (RTX 4050) que entra a la misma
tailnet como un nodo aparte.

**Diferencia clave con Kokoro/Piper: acá el contenedor Docker de Tailscale no
sirve.** En Docker Desktop para Windows, `network_mode: host` ata la interfaz
`tailscale0` a la VM interna de WSL2, no a la red real de Windows —
verificado: el propio Windows no podía alcanzar la IP de tailnet que ese
contenedor se asignó (`curl` daba timeout), así que mucho menos el teléfono.
En esta máquina el cliente tiene que ser la **app nativa de Tailscale para
Windows** (tailscale.com/download), logueada con la misma cuenta.

Una vez con Tailscale nativo corriendo, el contenedor de Chatterbox
(`docker-compose-cu130.yml` en el clon de
[devnen/Chatterbox-TTS-Server](https://github.com/devnen/Chatterbox-TTS-Server),
fuera de este repo) ya publica el puerto 8004 en todas las interfaces, así que
queda alcanzable directo por la IP de tailnet de la laptop — sin proxy y sin
token, porque este nodo no se reparte a probadores. Como con Kokoro/Piper: no
alcanza con que la consola diga "Connected", hay que confirmar tráfico real
(`curl` desde el teléfono al puerto 8004).

**Confirmado funcionando**: con Tailscale nativo, la laptop entra como nodo
`g14` en `100.102.250.94`, y `curl http://100.102.250.94:8004/api/model-info`
responde 200 con el modelo cargado. La dirección vive en
[`tools/release/chatterbox.json`](../../tools/release/chatterbox.json) como
`CHATTERBOX_URL` — a diferencia de `KOKORO_URL`/`PIPER_URL`, ese archivo **sí
está trackeado en git**: sin proxy y sin token no hay nada que revocar, y la
tailnet ya es la barrera de seguridad. Si la IP cambia (reinicio de
Tailscale, reinstalación), hay que actualizar ese archivo y recompilar.

Esta laptop es un nodo **intermitente**, no un servidor 24/7: cuando está
apagada o dormida, el sondeo de salud de la app (`ChatterboxTtsProvider.healthOf`)
falla y el repliegue a Edge es automático y silencioso, igual que con
Kokoro/Piper.

---

## Cloudflare Tunnel

Sin dominio propio solo cabe el **túnel rápido**, que no pide ni cuenta:

```bash
cloudflared tunnel --url http://localhost:8880
```

Devuelve un subdominio en `trycloudflare.com` con HTTPS de verdad y sin límite
de ancho de banda. El problema es que **ese subdominio cambia en cada
reinicio**, lo que obliga a reescribir la dirección en Ajustes cada vez que
levantas el túnel; la propia documentación de Cloudflare lo declara no apto para
uso permanente. Y el servidor queda accesible para cualquiera que dé con la URL.

**Con dominio propio la cosa cambia por completo**: nombre fijo
(`tts.tudominio.com`), y sobre todo **Cloudflare Access con token de servicio**,
que sí sería autenticación real. Es la ruta a tomar el día que compres un
dominio; a cambio habría que enseñar a los providers a mandar las cabeceras
`CF-Access-Client-Id` y `CF-Access-Client-Secret`, que hoy no mandan.

---

## ngrok — descartar

Es la opción que primero viene a la cabeza y hoy es de las peores. El plan
gratuito quedó en **sesiones de 2 horas**, 1 GB de tráfico al mes, URL aleatoria
y **una página de aviso HTML delante de cada visitante**.

Esa página es el golpe fatal: es HTML, y la app decide cómo parsear la respuesta
mirando el `content-type`. El servidor respondería perfecto y la app vería
basura. Se puede saltar mandando la cabecera `ngrok-skip-browser-warning`, pero
los providers no mandan cabeceras propias, así que no funcionaría sin tocar
código. Y aunque se arreglara, el corte de sesión cada 2 h te deja mudo a mitad de un
capítulo, con una URL nueva que escribir a mano.

---

## DDNS + port forwarding

Abrir el puerto 8880 en el router y apuntarle un nombre gratuito de DuckDNS es
lo más directo de todo, y lo menos aconsejable: **publica un servidor sin
autenticación en tu IP doméstica**, atado a tu casa.

Además puede que ni siquiera funcione. Si el ISP te tiene detrás de **CGNAT**
—varios clientes compartiendo una misma IP pública— las conexiones entrantes no
llegan nunca, y ningún servicio de DNS dinámico arregla eso: el reenvío de
puertos del router no tiene efecto porque el NAT del operador, aguas arriba, no
reenvía nada.

**Cómo saberlo:** compara la IP que muestra la sección WAN del router con la que
te dice cualquier servicio de "cuál es mi IP". Si no coinciden, estás detrás de
CGNAT y esta opción está descartada de entrada. Tailscale, en cambio, atraviesa
CGNAT sin enterarse.

---

## Hugging Face Spaces

La opción "nube completa" más accesible: un Docker Space con la imagen
`kokoro-fastapi-cpu`, en el plan gratuito, que da **2 vCPU y 16 GB** con HTTPS
público y sin necesidad de dominio ni tarjeta.

Los inconvenientes son dos. **El Space se duerme a las 48 h sin uso**, y el
primer acceso después lo despierta con un arranque en frío de entre 30 y 90
segundos: con el health check en 3 s, la app se repliega a Edge esa primera vez
y hay que insistir. Y un Space público es un servidor sin autenticación abierto
al mundo; ponerlo privado exige mandar un token de Hugging Face en la cabecera,
que la app hoy no manda.

Sirve bien como respaldo para el día que la computadora no pueda quedarse
encendida. Como opción principal, sale perdiendo frente a Tailscale.

---

## Google Cloud Run

El cupo permanente es holgado: 2 millones de peticiones, 180 000 vCPU-segundos y
360 000 GiB-segundos al mes, con escalado a cero. Con un contenedor de 2 vCPU
eso son unas **25 horas de cómputo al mes**, y como solo consume mientras
sintetiza, da para bastante más escucha de la que parece.

El problema es el arranque en frío. Una imagen con PyTorch y el modelo pesa
varios gigas, y escalar desde cero se lleva por delante los 3 segundos del
health check una y otra vez, porque el contenedor vuelve a apagarse entre
capítulos.
Mantener una instancia mínima siempre viva lo arreglaría, pero eso ya se cobra.

---

## Oracle Cloud Always Free

Un VPS ARM encendido permanentemente, gratis de por vida y con espacio de sobra
para llevar Kokoro y Piper a la vez. Sobre el papel, la mejor nube de la lista.

**Cuidado con tres cosas.** En junio de 2026 Oracle recortó la asignación
gratuita de ARM de 4 OCPU y 24 GB a **2 OCPU y 12 GB, sin anuncio público**.
La capacidad
ARM está a menudo agotada, y depende de la **región de origen de la cuenta, que
no se puede cambiar después** de crearla. Y exige tarjeta, con una retención
temporal de verificación.

Si consigues capacidad, es una solución definitiva. Si no, es una tarde perdida.
En cualquier caso seguiría siendo un servidor sin autenticación en una IP
pública, así que conviene combinarlo con un cortafuegos que solo admita tu
propia red de Tailscale.

---

## APIs de TTS gestionadas — descartar

Por completitud, porque es lo primero que aparece al buscar "TTS gratis": no hay
nada que aporte sobre lo que Edge ya da. ElevenLabs regala 10 000 caracteres al
mes, cuando una novela son varios millones. El millón de caracteres de Google
Cloud TTS es de prueba, no permanente. Y PlayHT, que se citaba mucho, cerró en
diciembre de 2025.

---

## Consumo de datos

Decide si el acceso remoto es usable con datos móviles, y la diferencia entre
motores es de un orden de magnitud, porque **Piper devuelve WAV sin comprimir**
([`piper_tts_provider.dart:93-95`](../../lib/tts/piper_tts_provider.dart))
mientras **Kokoro devuelve MP3**
([`kokoro_tts_provider.dart:147-149`](../../lib/tts/kokoro_tts_provider.dart)).

Para Piper la cifra es aritmética, no estimación: los modelos `high` sintetizan
a 22 050 Hz, 16 bits y un canal, o sea 44 100 bytes por segundo de audio.

**Kokoro ya está medido** (2026-09-02, v0.8.1, voz `ef_dora`, mismo párrafo en
todos los formatos). El servidor **no expone ningún parámetro de bitrate**: su
API solo acepta `response_format`, así que la única palanca es el códec.

| Formato | kbps | Por hora de audio | En la red, por hora |
|---|---|---|---|
| **AAC-LC** ← el que usa la app | **94** | ~40 MB | **~54 MB** |
| MP3 (lo anterior) | 130 | ~56 MB | ~74 MB |
| Opus | 140 | ~60 MB | ~80 MB |
| FLAC | 198 | ~85 MB | ~113 MB |
| WAV | 386 | ~166 MB | ~221 MB |
| Piper (WAV, sin opción) | 353 | ~159 MB | ~159 MB |

Tres cosas que la medición dejó claras, y ninguna era la esperada:

- **El encoder iba a 131 kbps, no a 64.** La cifra estimada de ~29 MB por hora
  que traía este documento era menos de la mitad de la real.
- **Opus sale peor que MP3**, que es exactamente lo contrario de lo que se
  supone del formato más eficiente para voz: el servidor lo codifica también a
  tasa fija alta y su ventaja se pierde. Además viaja en Ogg, que no se
  concatena por tramas como necesita el troceado de párrafos largos.
- **AAC es la única mejora real**, un 28 % menos, y sin coste: AAC-LC a 94 kbps
  rinde por encima de MP3 a 130, y es ADTS igual que el MP3, así que se
  concatena igual. Verificado: dos respuestas unidas dan 148 tramas sin
  desincronizar.

Y una parte que ningún códec arregla: **por la red viaja un 33 % más**. Desde
v0.8 el audio llega en base64 dentro de un JSON
([`kokoro_tts_provider.dart:175-184`](../../lib/tts/kokoro_tts_provider.dart)),
y esa expansión no está en el tamaño del audio. Es el precio del endpoint que
devuelve los timestamps.

**Ojo con los datos móviles.** Piper se lleva 159 MB por hora, y un plan de 5 GB
da para unas 31 horas contando solo el audio; Kokoro, 54 MB por hora, da para
unas 95. Ninguno de los dos es un motor para escuchar por 4G sin mirar el
contador. Es la razón principal por la que **Piper no va al reparto** a los
probadores: mandarle WAV sin comprimir al plan de datos de otra persona no es
razonable.

Y un matiz operativo: **la descarga por adelantado está atada al WiFi por
diseño**. `maybePrefetchAhead`
([`reader_provider.dart:1146-1173`](../../lib/ui/providers/reader_provider.dart))
comprueba la conectividad antes de empezar y no arranca con datos móviles. El
acceso remoto sirve para **escuchar sobre la marcha**, no para descargar
capítulos desde la calle.

---

## Recomendación

**Tailscale.** Es la única opción que no obliga ni a exponer un servidor sin
autenticación ni a escribir una línea de código: no necesita dominio, es gratis
sin tope de ancho de banda, atraviesa CGNAT, y encaja con dejar la computadora
encendida al salir de casa. La configuración se agota en instalar dos clientes y
escribir una dirección en Ajustes.

Dos rutas alternativas, por si las circunstancias cambian:

- **Cloudflare Tunnel con dominio propio y Access**, el día que quieras una URL
  pública estable. Es la mejor opción de esa familia, y exigiría añadir
  cabeceras de autenticación a los providers.
- **Oracle Cloud Always Free**, el día que la computadora deje de poder quedarse
  encendida. Con Hugging Face Spaces como respaldo si no hay capacidad ARM.

Todo esto —trackear `KOKORO_URL`/`CHATTERBOX_URL` en git, y no tratar el token
como secreto— da por sentado que **este repositorio se queda privado**. Es la
razón por la que `TTS_TOKEN`, en cambio, nunca se comitea (ver
[`tools/release/README.md`](../../tools/release/README.md), "Configurar una
segunda PC propia"): git no olvida, y una vez en el historial no hay forma
barata de sacarlo. Si este repo se abriera algún día, o el proyecto escalara
más allá de hobby, tocaría reconsiderar tanto eso como la elección de
Tailscale por algo con autenticación real —Cloudflare Access, de esta misma
lista— en vez de confiar en que el servidor nunca sale de la red privada.

---

## Lo que quedaría pendiente en la app

Nada de esto hace falta para Tailscale. Es lo que habría que construir si algún
día se elige una opción de URL pública:

- Un campo de **token** en Ajustes, junto al de la dirección del servidor.
- Que los dos providers manden ese token como cabecera —`Authorization`,
  `CF-Access-Client-Id` o la que toque— en la síntesis, el health check y el
  listado de voces.
- Un **health check más tolerante que 3 s**, o un reintento, para que un
  arranque en frío o una red móvil lenta no provoquen un repliegue a Edge
  injustificado.
