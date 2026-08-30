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

## Encontrado probando en teléfono (2026-08-30)

- [x] `urgente` — **No aparecían los controles en la pantalla de bloqueo ni al
  bajar la barra de estado.** Causa: `MainActivity` extendía `FlutterActivity`
  en vez de `AudioServiceActivity`. audio_service ejecuta el handler en un
  FlutterEngine propio, y la Activity debe engancharse a ese mismo motor; con
  FlutterActivity la app creaba un segundo motor aislado, el servicio se
  quedaba sin handler, y la notificación no llegaba a existir aunque el audio
  sonara con normalidad. Se rompió al reescribir la Activity para el intent de
  compartir. **Corregido, falta confirmarlo en el teléfono.**
- [ ] `urgente` — **El audio descargado no se reproduce: al dar play sintetiza
  con Edge.** La interfaz dice que hay descargas de Kokoro y Piper, pero la
  búsqueda en caché no las encuentra, así que vuelve a sintetizar y —sin
  servidor alcanzable— cae a Edge. Sospechas: (a) se descargaron con el formato
  de clave anterior al cambio de esta sesión, (b) se guardaron bajo la clave de
  Edge porque el servidor no respondía al iniciar la descarga, o (c) los
  archivos ya no están donde dice la base de datos. Hay un diagnóstico temporal
  añadido que vuelca claves buscadas y guardadas; queda ejecutarlo.

## UX / Interfaz — pendientes

- [ ] `medio` 2026-08-30 — **Estimar el tiempo de descarga.** Hoy la barra dice
  "Descargando 73 / 1350 párrafos", que no informa de nada útil. Debería mostrar
  el tiempo restante, como ya hace el lector con "faltan ~3 h 18 min".
  Contexto: *El Instituto* tiene 6.289 párrafos en 14 capítulos, ~450 por
  capítulo, así que un capítulo cuesta ~15 min con Piper y ~37 min con Kokoro.
  Descargar "los próximos 3 capítulos" con Kokoro son casi 2 horas, y ahora
  mismo nada lo advierte. Medido: ~2 s/párrafo en Piper, ~5 s/párrafo en Kokoro.
  Conviene además avisar del tamaño estimado antes de empezar.

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
  reproduce: controles en pantalla de bloqueo, botones de auriculares y
  Bluetooth, pausa y reanudación ante llamada entrante, y supervivencia de la
  reproducción con la pantalla apagada.
- [ ] `bajo` 2026-08-30 — Decidir si el botón "siguiente" de la pantalla de
  bloqueo debe saltar de párrafo (actual) o de capítulo. Por párrafo puede
  resultar demasiado granular para un botón físico del coche.

## Ideas / Futuro

- [x] `medio` 2026-04-30 — Descarga de capítulos para escucha offline. La infraestructura de caché ya existe (AudioCacheRepo + SQLite). Falta: (1) guardar en `getApplicationDocumentsDirectory()` en vez de `getTemporaryDirectory()` para que el OS no lo borre, (2) botón "Descargar capítulo" que pre-sintetice todos los párrafos en background con progreso visible, (3) columna `pinned` en `audio_cache` para que el LRU eviction no toque los descargados, (4) detección de red offline para ir directo al caché. Peso estimado: ~3-5 MB por capítulo.
