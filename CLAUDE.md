# VoiceX Móvil — notas para Claude

Lector EPUB con TTS neuronal en Flutter, para Android. El [README](README.md)
cubre estructura, build y comandos; acá va solo lo que no está escrito ahí.

## Flujo de trabajo

Cerrar los cambios de código con:

```bash
flutter analyze && flutter test
```

**Para compilar un APK, `tools/release/compilar.sh` (macOS/Linux) o
`compilar.ps1` (Windows), y nada más.** Hacen lo mismo. Nunca
`flutter build apk` a mano: sin `--dart-define-from-file` la build sale sin
servidores y en Ajustes quedan dos motores en vez de cuatro. No falla, no avisa
y el APK se instala igual — solo que Qwen3 y Chatterbox no existen dentro
(`TtsServerConfig.availableEngines` en `lib/config/server_config.dart`, filtrado
en `settings_screen.dart`). El script pasa los `.json` y después comprueba las
URLs dentro de `libapp.so`, así que un archivo incompleto también se cae ahí. Detalles en
[`tools/release/README.md`](tools/release/README.md).

## Cómo se escribe acá

- **El código va en inglés**: identificadores, comentarios y doc-comments `///`.
  Son 662 líneas de comentario y prácticamente ninguna en español; no romper esa
  consistencia al agregar código.
- **La documentación va en español con tildes**: README, `docs/**` y los mensajes
  de commit. (El repo de SENASA usa ASCII sin tildes. Este sí las lleva.)
- **Los textos que ve el usuario van en español**, aunque estén dentro del código:
  mensajes de error, etiquetas de UI (`'Kokoro respondió ${resp.statusCode}'`).
- Los mensajes de commit siguen **Conventional Commits**: `tipo(área opcional):
  descripción`. La descripción sigue describiendo **el problema resuelto o el
  resultado**, no la mecánica, en minúscula después de los dos puntos. Tipos
  que se usan acá: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`.
  - `fix: un audio vacío ya no se cachea y deja el párrafo mudo para siempre`
  - `fix(piper): un modelo por idioma, porque sus voces no son multilingües`
  - `docs(readme): resumen de versiones en vez de la tabla de tareas vacía`
- La documentación explica **por qué**, con el archivo y la línea que lo respalda.
  Ver `docs/context/ACCESO_REMOTO.md` como referencia del tono.

## Dónde va cada cosa

| Archivo | Qué recibe |
|---|---|
| `docs/RELEASES.md` | Todo cambio visible al usuario, con su causa |
| `docs/context/TECHNICAL.md` | Especificación técnica |
| `docs/context/USO_HERRAMIENTAS.md` | Cómo correr las herramientas del Mac: ruta, PATH, comandos |
| `docs/tasks/IMPROVEMENTS.md` | Mejoras pendientes |
| `docs/bugs/` | Investigaciones de bugs concretos |
| `docs/bugs/REPORTES_TESTERS.md` | Reportes crudos de testers, sin triar (lo escribe `tools/reportes/procesar.py`, automático) |

Al subir de versión: `versionName` sale de `pubspec.yaml` y hay que registrar el
cambio en `RELEASES.md` y en la tabla de versiones del `README.md`.

## Motores de voz

Tres providers bajo `lib/tts/`: Edge, el del teléfono y `VoiceServerTtsProvider`,
que sirve **dos motores** (`qwen3` y `chatterbox2`) desde un mismo servidor, el
Mac de `tools/mlx`. Strategy + Factory: un motor del servidor nuevo toca
`TtsServerConfig.serverEngines`, `ttsEngines` en `settings.dart`, `_cacheKeyFor`
y el servidor; no hace falta un provider nuevo. Kokoro, Piper y F5 se retiraron
con el servidor de casa que los alojaba, y sus carpetas se borraron (siguen en
el historial de git).

Invariantes que ya causaron bugs y conviene no romper:

- **Un motor nuevo tiene que sumarse a la exclusión de `migrateCacheKeys`**
  (`lib/storage/repositories.dart`). La regla comodín de esa migración
  reetiqueta como Edge toda clave sin prefijo conocido, y olvidarla **no falla
  ruidosamente**: la clave deja de coincidir con la que calcula la
  reproducción y cada descarga se vuelve inalcanzable en silencio, con el
  archivo intacto en el disco. Le pasó a Chatterbox entero
  (`docs/bugs/CHATTERBOX_DESCARGAS.md`).
- **Un motor retirado se declara en `_dropRetiredEngineRows`, y su prefijo no
  se reutiliza.** Esa función borra en cada arranque toda fila con el prefijo
  de un motor que se fue. Por eso el Chatterbox de hoy se llama `chatterbox2`:
  con el id viejo la app borraría sus descargas la siguiente vez que abriera.
  Y por eso `android-` **no** está ahí: el motor del teléfono volvió en 0.7.0 con
  ese prefijo, y listarlo borraba lo descargado con él en cada arranque.
- **La clave de caché no incluye el host del servidor**
  (`_cacheKeyFor` en `lib/ui/providers/reader_provider.dart`): es motor + voz.
  Cambiar de dirección de servidor no invalida lo descargado — es
  deliberado. Meter el host ahí tiraría toda la caché de los usuarios. La
  velocidad tampoco entra: se aplica al reproducir, y un mismo archivo sirve a
  todas.
- **El health check tiene 5 s de tope y un reintento de 8 s**
  (`TtsTimeouts.probe`/`probeRetry`), cacheado 60 s en éxito y solo 5 s en
  fallo. Si se agota, la app se repliega a Edge **en silencio**. Cualquier
  cosa que agregue latencia (túnel, VPN, arranque en frío) se manifiesta como
  "el servidor no responde" — y un servidor **ocupado** también, si comparte
  hilo entre síntesis y sondeo: por eso `tools/mlx` atiende `/health` fuera del
  hilo de la GPU y dice `busy`.
- **El servidor valida su propio token** (`VOICE_TOKEN`, el de
  `tools/mlx/.token`) y `applyRequestHeaders` (`lib/tts/tts_endpoint.dart`) lo
  manda en la síntesis, el sondeo y el catálogo. **Los reportes** ("Contar un
  problema") van al mismo servidor y con el mismo token (`POST /report`,
  `PUT /report/audio/…`): no tienen dirección ni credencial propias, y sin
  `VOICE_URL` `Reporter.canDeliver` es falso y Ajustes no ofrece la sección. Lo
  recibido se vuelca a `docs/` con `tools/reportes/procesar.sh`. El acceso al Mac
  va por Tailscale (`tools/release/voz.json`), no por un túnel público.
- **El token de Edge (`Sec-MS-GEC`) lo cambia Microsoft sin avisar.** La versión
  2 es `<CS64>-<SHA256 propio>` y vive en `lib/tts/edge_drm.dart`, portada de
  `rany2/edge-tts`, que es la fuente de verdad; la versión 1 (un SHA-256 simple)
  da 403 en el WebSocket **y** en la lista de voces. Si Edge deja de funcionar y
  el servicio responde a `edge-tts`, es esto: ver `docs/bugs/EDGE_TTS_DEBUG.md`.

## Detalles del entorno

- `analysis_options.yaml` excluye `build/**` y `android/**`. Si `flutter analyze`
  empieza a reportar ruido de esas carpetas, es que se perdió el `analyzer:`.
- El servidor de voz vive en `tools/mlx` y corre en un Mac con Apple Silicon
  (`./arrancar.sh`, puerto 8765). Es opcional: la app funciona sin él con Edge.
