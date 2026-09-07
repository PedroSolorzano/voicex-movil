# VoiceX Móvil — notas para Claude

Lector EPUB con TTS neuronal en Flutter, para Android. El [README](README.md)
cubre estructura, build y comandos; acá va solo lo que no está escrito ahí.

## Flujo de trabajo

Cerrar los cambios de código con:

```bash
flutter analyze && flutter test
```

**Para compilar un APK, `tools/release/compilar.ps1` y nada más.** Nunca
`flutter build apk` a mano: sin `--dart-define-from-file` la build sale sin
servidores y en Ajustes quedan dos motores en vez de cinco. No falla, no avisa
y el APK se instala igual — solo que F5, Kokoro y Piper no existen dentro
(`lib/config/server_config.dart:26-33`, filtrado en `settings_screen.dart:185`).
El script pasa los tres `.json` y después comprueba las URLs dentro de
`libapp.so`, así que un archivo incompleto también se cae ahí. Detalles en
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
| `docs/tasks/IMPROVEMENTS.md` | Mejoras pendientes |
| `docs/bugs/` | Investigaciones de bugs concretos |
| `docs/bugs/REPORTES_TESTERS.md` | Reportes crudos de testers, sin triar (lo escribe `tools/reportes/procesar.py`, automático) |

Al subir de versión: `versionName` sale de `pubspec.yaml` y hay que registrar el
cambio en `RELEASES.md` y en la tabla de versiones del `README.md`.

## Motores de voz

Cinco providers bajo `lib/tts/` (Edge, Kokoro, Piper, F5, Teléfono), con
Strategy + Factory: agregar uno toca `tts_provider.dart` (la interfaz), el
provider nuevo, `tts_factory.dart` y `models.dart`.

Cinco invariantes que ya causaron bugs y conviene no romper:

- **Un motor nuevo tiene que sumarse a la exclusión de `migrateCacheKeys`**
  (`lib/storage/repositories.dart`). La regla comodín de esa migración
  reetiqueta como Edge toda clave sin prefijo conocido, y olvidarla **no falla
  ruidosamente**: la clave deja de coincidir con la que calcula la
  reproducción y cada descarga se vuelve inalcanzable en silencio, con el
  archivo intacto en el disco. Le pasó a Chatterbox entero
  (`docs/bugs/CHATTERBOX_DESCARGAS.md`).
- **La clave de caché no incluye el host del servidor**
  (`_cacheKeyFor` en `lib/ui/providers/reader_provider.dart`): es motor + voz +
  ritmo. Cambiar de dirección de servidor no invalida lo descargado — es
  deliberado. Meter el host ahí tiraría toda la caché de los usuarios.
- **El health check tiene 5 s de tope y un reintento de 8 s**
  (`TtsTimeouts.probe`/`probeRetry`), cacheado 60 s en éxito y solo 5 s en
  fallo. Si se agota, la app se repliega a Edge **en silencio**. Cualquier
  cosa que agregue latencia (túnel, VPN, arranque en frío) se manifiesta como
  "el servidor no responde" — y un servidor **ocupado** también, si comparte
  hilo entre síntesis y sondeo: por eso `tools/f5` atiende `/tts` en otro
  hilo.
- **Tras comprobar el 200, la respuesta se distingue por su `content-type`**: JSON
  con base64 en Kokoro ≥ v0.8, audio crudo si no. Un intermediario que conteste
  200 con HTML cae por la rama de "audio crudo" y rompe el parseo aunque el
  servidor esté bien.
- Ningún provider manda cabeceras de autenticación. Kokoro y Piper **no tienen
  auth**: por eso el acceso remoto va por Tailscale y no por un túnel público
  (`docs/context/ACCESO_REMOTO.md`).

## Detalles del entorno

- `analysis_options.yaml` excluye `build/**` y `android/**`. Si `flutter analyze`
  empieza a reportar ruido de esas carpetas, es que se perdió el `analyzer:`.
- Los servidores de voz son opcionales y viven en `tools/kokoro`, `tools/piper`
  y `tools/f5` (este último necesita GPU y corre en la laptop, no en
  `voicex-server`)
  (Docker, puertos 8880 y 5000). La app funciona sin ellos con Edge.
