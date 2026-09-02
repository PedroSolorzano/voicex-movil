# VoiceX Móvil — notas para Claude

Lector EPUB con TTS neuronal en Flutter, para Android. El [README](README.md)
cubre estructura, build y comandos; acá va solo lo que no está escrito ahí.

## Flujo de trabajo

**El commit lo hace el usuario, no Claude.** Hay un hook a nivel de usuario que
bloquea `git commit`. Al terminar un cambio: dejarlo en `git add` y proponer el
mensaje. No intentar rodear el hook.

Cerrar los cambios de código con:

```bash
flutter analyze && flutter test
```

## Cómo se escribe acá

- **El código va en inglés**: identificadores, comentarios y doc-comments `///`.
  Son 662 líneas de comentario y prácticamente ninguna en español; no romper esa
  consistencia al agregar código.
- **La documentación va en español con tildes**: README, `docs/**` y los mensajes
  de commit. (El repo de SENASA usa ASCII sin tildes. Este sí las lleva.)
- **Los textos que ve el usuario van en español**, aunque estén dentro del código:
  mensajes de error, etiquetas de UI (`'Kokoro respondió ${resp.statusCode}'`).
- Los mensajes de commit describen **el problema resuelto o el resultado**, no la
  mecánica. En minúscula después del primer carácter, sin prefijos tipo
  `feat:`/`fix:`. Opcionalmente con área delante:
  - `Un audio vacío ya no se cachea y deja el párrafo mudo para siempre`
  - `Piper: un modelo por idioma, porque sus voces no son multilingües`
  - `README: resumen de versiones en vez de la tabla de tareas vacía`
- La documentación explica **por qué**, con el archivo y la línea que lo respalda.
  Ver `docs/context/ACCESO_REMOTO.md` como referencia del tono.

## Dónde va cada cosa

| Archivo | Qué recibe |
|---|---|
| `docs/RELEASES.md` | Todo cambio visible al usuario, con su causa |
| `docs/context/TECHNICAL.md` | Especificación técnica |
| `docs/tasks/IMPROVEMENTS.md` | Mejoras pendientes |
| `docs/bugs/` | Investigaciones de bugs concretos |

Al subir de versión: `versionName` sale de `pubspec.yaml` y hay que registrar el
cambio en `RELEASES.md` y en la tabla de versiones del `README.md`.

## Motores de voz

Cuatro providers bajo `lib/tts/`, con Strategy + Factory: agregar uno toca
`tts_provider.dart` (la interfaz), el provider nuevo, `tts_factory.dart` y
`models.dart`.

Cuatro invariantes que ya causaron bugs y conviene no romper:

- **La clave de caché no incluye el host del servidor**
  (`_cacheKeyFor` en `lib/ui/providers/reader_provider.dart`): es motor + voz +
  ritmo. Cambiar de dirección de servidor no invalida lo descargado — es
  deliberado. Meter el host ahí tiraría toda la caché de los usuarios.
- **El health check tiene 3 s de tope** (Kokoro `GET /health`, Piper `GET /info`),
  cacheado 30 s. Si se agota, la app se repliega a Edge **en silencio**. Cualquier
  cosa que agregue latencia (túnel, VPN, arranque en frío) se manifiesta como
  "el servidor no responde".
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
- Los servidores de voz son opcionales y viven en `tools/kokoro` y `tools/piper`
  (Docker, puertos 8880 y 5000). La app funciona sin ellos con Edge.
