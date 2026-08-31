# VoiceX Movil — Mejoras pendientes

Prioridades: `urgente` | `alto` | `medio` | `bajo`

Formato: `- [ ] [prioridad] YYYY-MM-DD — descripción`

Lo que ya se entregó vive en [`docs/RELEASES.md`](../RELEASES.md), con su causa
y su arreglo. Aquí solo queda lo que no está hecho.

---

## Pendiente de decisión

- [ ] `alto` 2026-08-30 — **Elegir motor de voz definitivo.** Hay 9 muestras del
  mismo párrafo en `muestras_voz/` (6 de Edge, 3 de Kokoro) con un LEEME que
  explica cómo compararlas. Edge se queda como motor principal pase lo que pase;
  Kokoro entraría como proveedor adicional para funcionar sin internet, que hoy
  solo cubre el TTS nativo de Android. Medido: Kokoro da timestamps por palabra
  (cabecera `x-word-timestamps`), va a ~5x tiempo real en CPU, y solo tiene 3
  voces en español frente a las 11 de Edge.
- [ ] `medio` 2026-08-30 — **Probar en teléfono físico** lo que el emulador no
  reproduce: botones de auriculares y Bluetooth, pausa y reanudación ante
  llamada entrante, y supervivencia de la reproducción con la pantalla apagada.
  Los controles de pantalla de bloqueo ya se confirmaron en 0.5.0.
- [ ] `bajo` 2026-08-30 — Decidir si el botón "siguiente" de la pantalla de
  bloqueo debe saltar de párrafo (actual, `reader_provider.dart` `onNext =
  nextParagraph`) o de capítulo. Por párrafo puede resultar demasiado granular
  para un botón físico del coche. `navigateChapter` ya existe; habría que
  separar el handler del servicio de audio del de los botones en pantalla.

---

## TTS / Audio

- [ ] `medio` 2026-08-30 — **La clave de caché de Kokoro no lleva el idioma.**
  `kokoroVoiceEs` y `kokoroVoiceEn` valen `af_bella` por defecto, así que un
  libro con el idioma cambiado de ES a EN reutiliza el audio ya cacheado
  aunque el `lang_code` enviado al servidor sea distinto — y con reglas
  inglesas el español sale en ~17 s en vez de ~27 s, ininteligible. Lo mismo
  aplica a Piper si se configura la misma voz en ambos idiomas. Edge se libra
  porque el nombre de la voz ya lleva el locale. Arreglar significa meter
  `book.language` en la clave y migrar las filas existentes leyendo
  `books.language`; si no, se huerfanizan todas las descargas hechas hasta hoy.
  Documentado en `test/cache_key_test.dart`.

---

## Calidad de código

- [ ] `bajo` 2026-08-30 — **Código muerto:** `AudioCacheRepo.debugKeys` no tiene
  ningún llamador. Es lo que quedó del diagnóstico que resolvió el bug de caché
  de 0.5.0. Borrarlo o engancharlo a un botón en Ajustes.
- [ ] `bajo` 2026-08-30 — **Dos `catch` que apagan la señal.** En
  `edge_tts_provider.dart`, el parseo de los `WordBoundary` está envuelto en un
  `catch (_) {}`: si Microsoft cambia el formato del JSON se pierden todas las
  marcas de palabra sin que nada lo diga. En `reader_provider.dart`,
  `_readSidecar` devuelve `[]` ante un `.ts.json` corrupto, indistinguible de un
  audio sin timestamps. Basta un `dev.log` en cada uno.
- [ ] `bajo` 2026-08-30 — **Sin tests de UI ni de widgets.** `lib/ui/` son 3.379
  líneas con cobertura cero, `reader_provider.dart` incluido. Los repositorios y
  la clave de caché sí quedaron cubiertos en 0.5.2.

---

## Mantenimiento

- [ ] `medio` 2026-08-30 — **Dependencias.** 10 directas desactualizadas.
  Seguras de subir ya: `html`, `path_provider`, `uuid`, `sqflite`. Requieren
  probar la reproducción en el teléfono: `just_audio` 0.9→0.10 junto con
  `audio_session` 0.1→0.2. Van cuatro majors por detrás `go_router` (14→18) y
  `file_picker` (8→12). `flutter_riverpod` 2→3 se aparca: migración de calado
  sin beneficio inmediato. `epubx` frena `archive`, `image` y `xml`.
- [ ] `bajo` 2026-08-30 — **`main` va por detrás y no hay tags.** `develop`
  acumula toda la historia desde 0.1.0 y `main` sigue en el commit inicial.
  `docs/RELEASES.md` documenta el procedimiento de tag y no se ha aplicado
  nunca.
