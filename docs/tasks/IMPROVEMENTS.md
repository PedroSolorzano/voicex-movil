# VoiceX Movil — Mejoras pendientes

Prioridades: `urgente` | `alto` | `medio` | `bajo`

Formato: `- [ ] [prioridad] YYYY-MM-DD — descripción`

---

## UX / Interfaz

- [x] `medio` 2026-04-30 — Selector de velocidad de lectura en el reproductor (4 niveles: Lento -20%, Normal +0%, Rápido +25%, Veloz +50%). Requiere también corregir el cache key que ignora `edgeRate` y guarda el MP3 viejo cuando cambia la velocidad.
- [x] `bajo` 2026-04-30 — Mostrar consumo de datos móviles acumulado durante la sesión de escucha directamente en la pantalla del reproductor (en MB). Útil para saber cuánto se gasta en una escucha sin WiFi.

---

## TTS / Audio

- [x] `alto` 2026-04-30 — El highlight de palabra no funciona durante la reproducción. Los `WordTimestamp` llegan del servidor pero el texto en pantalla no refleja la palabra activa en tiempo real.
- [x] `alto` 2026-04-30 — Auto-continuar lectura: al terminar un párrafo/capítulo el texto cambia en pantalla pero el audio se detiene. Debería iniciar automáticamente la síntesis y reproducción del siguiente párrafo sin intervención del usuario, como un audiolibro.

---

## Rendimiento

---

## Bugs menores

---

## Biblioteca

- [x] `medio` 2026-04-30 — Portada y metadatos del EPUB (editorial, fecha, materia, descripción) visibles desde la biblioteca. Implementado en v0.2.0.

## Ideas / Futuro

- [x] `medio` 2026-04-30 — Descarga de capítulos para escucha offline. La infraestructura de caché ya existe (AudioCacheRepo + SQLite). Falta: (1) guardar en `getApplicationDocumentsDirectory()` en vez de `getTemporaryDirectory()` para que el OS no lo borre, (2) botón "Descargar capítulo" que pre-sintetice todos los párrafos en background con progreso visible, (3) columna `pinned` en `audio_cache` para que el LRU eviction no toque los descargados, (4) detección de red offline para ir directo al caché. Peso estimado: ~3-5 MB por capítulo.
