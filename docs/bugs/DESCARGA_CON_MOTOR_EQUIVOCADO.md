# Un capítulo entero descargado con el motor equivocado, sin decirlo

**2026-09-06.** Reportado desde el teléfono: se descargó un capítulo de ~100
párrafos, tardó un tiempo razonable, **no apareció ningún error**, y al ponerse
a escuchar sonó la voz de Edge en vez de la de F5. En la pantalla de
almacenamiento: 104 párrafos y unos 9 MB, cifras que "no hacían sentido".

## Los 9 MB no eran la pista

Los dos motores emiten **MP3 mono a 96 kbps** — Edge pide
`audio-24khz-96kbitrate-mono-mp3` (`lib/tts/edge_tts_provider.dart:23`) y el
servidor de F5 comprime con `-b:a 96k` (`tools/f5/server.py:184`). Son 12 KB por
segundo de audio en ambos casos.

9 MB ÷ 104 párrafos = 88 KB por párrafo ≈ **7,4 s de audio cada uno**, unos 13
minutos de capítulo. Consistente para un capítulo de párrafos cortos, y idéntico
con cualquiera de los dos motores: **el tamaño no distingue el motor**. La única
señal real era la voz.

## El log del servidor: la petición nunca llegó

El contenedor `voicex-f5` vivió de **06:12 a 14:44 UTC** y ahí se cortó en seco.
En toda su vida:

| Petición | Cantidad |
|---|---|
| `POST /tts` → 200 | 24 |
| `POST /tts` → 400 | 1 (una prueba temprana) |
| `GET /health` → 200 | 1031 |

Un capítulo de 104 párrafos deja **unos 104 `POST /tts`**. El último que existe
es tres horas anterior a la descarga. De los 1031 `/health`, **1016 son el
healthcheck del propio Docker** (`127.0.0.1`, cada 30 s durante 8,5 h); solo 15
vinieron de afuera —del teléfono— y las 15 contestaron 200.

O sea: del lado del servidor no hay nada que investigar. Todo lo que entró se
procesó y contestó bien. Simplemente **no estaba corriendo** cuando se pidió la
descarga.

## Por qué no estaba: dos interruptores, no uno

La laptop se reinició a las **09:02 local**, 18 minutos después del último
`POST /tts`. El contenedor no volvió, y el `restart: unless-stopped` del compose
no tiene nada que ver: solo actúa mientras el demonio de Docker corre.

Docker Desktop tenía el arranque automático desactivado **en dos sitios a la
vez**, y arreglar uno solo no habría bastado:

- `%APPDATA%\Docker\settings-store.json` → `"AutoStart": false`.
- `HKCU\...\Explorer\StartupApproved\Run` → la entrada `Docker Desktop` con el
  primer byte en `03`, o sea **deshabilitada** desde "Aplicaciones de inicio" de
  Windows. La clave en `...\CurrentVersion\Run` existía, pero Windows la estaba
  ignorando.

Se corrigieron los dos. El `settings-store.json` hay que editarlo con Docker
Desktop **detenido**: al salir reescribe ese archivo con lo que tiene en
memoria y revierte el cambio.

## El defecto de la app

El repliegue a Edge hizo exactamente lo que debía; lo que falló es que **no dejó
rastro**. `downloadEngineNotice` (`reader_provider.dart`) solo se dibuja dentro
del texto de la barra de progreso, y al terminar la barra desaparece. El mensaje
final solo hablaba de párrafos fallidos, que aquí fueron cero: Edge sintetizó los
104 sin un solo error. Una descarga que cambió de motor terminaba **idéntica a
una limpia**.

Peor: ese audio queda guardado bajo la clave de Edge, y la reproducción busca por
el motor **seleccionado** (`_ensureAudio`), así que en cuanto F5 vuelva, los 104
párrafos descargados no se usan y hay que rehacerlos. Nadie se entera hasta que
la descarga que creía tener no aparece.

Arreglado en 0.9.1 por los dos extremos:

- **Antes de empezar:** `resolveDownloadEngine()` sondea al pulsar "Descargar",
  no en el primer párrafo. Si el motor real no es el elegido, el diálogo lo dice
  y deja cancelar, siempre —no solo cuando el estimado pasa de dos minutos—,
  porque el costo no es el tiempo sino el audio inservible. El estimado se
  calcula con el motor que va a correr de verdad.
- **Al terminar:** `downloadSummary` sobrevive a la barra y sale como mensaje:
  "Descargados 104 párrafos con F5", o "Descargado con Edge: F5 no estaba
  disponible, así que este audio no se usará cuando vuelva".

## Lo que queda anotado para la próxima

El anillo de diagnóstico del teléfono distingue los dos casos que producen el
mismo síntoma:

- **Servidor caído** (este): hay entradas `unreachable` en `/health`.
- **Libro no marcado como español**: `_resolveEngineKind` manda F5 a Edge **sin
  sondear** (`reader_provider.dart`), y `_detectLanguage` (`lib/epub/parser.dart`)
  marca `en` con que el `<dc:language>` empiece por "en" —cosa que muchos EPUB
  traen mal—. En ese caso el anillo no tiene **ninguna** entrada de esa
  descarga.
