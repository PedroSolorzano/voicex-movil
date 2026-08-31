# VoiceX Móvil — Control de Implementación

**Proyecto:** Lector EPUB con TTS neuronal para Android
**Stack:** Flutter / Dart
**Inicio:** 2026-04-29
**Referencia técnica:** [TECHNICAL.md](../context/TECHNICAL.md)

---

## Estado General

Las diez fases del plan original están cerradas. Lo que se construyó después
—Kokoro, Piper, descargas offline, diccionario, modo lectura— no estaba en ese
plan y se documenta versión a versión en [RELEASES.md](../RELEASES.md).

| Fase | Descripción | Estado | Cerrada |
|------|-------------|--------|---------|
| 1 | Setup y arquitectura base | Completado | 2026-04-29 |
| 2 | Capa EPUB | Completado | 2026-04-29 |
| 3 | Capa de almacenamiento | Completado | 2026-04-29 |
| 4 | Capa TTS | Completado | 2026-04-29 |
| 5 | Reproductor de audio | Completado | 2026-04-29 |
| 6 | Pantalla Biblioteca | Completado | 2026-04-29 |
| 7 | Pantalla Lectora | Completado | 2026-04-29 |
| 8 | Pantalla Ajustes | Completado | 2026-04-29 |
| 9 | Seguridad y rendimiento | Completado | 2026-04-29 |
| 10 | Build y distribución APK | Completado | 2026-04-30 |

El trabajo pendiente vive en [IMPROVEMENTS.md](IMPROVEMENTS.md).

---

## Verificación pendiente en teléfono físico

Lo que el emulador no puede reproducir. Todo lo demás se confirmó en 0.5.0 y
0.5.1 sobre un teléfono real.

- [ ] Botones de auriculares con cable (play/pausa, siguiente)
- [ ] Controles de un mando Bluetooth o del coche
- [ ] Pausa automática ante llamada entrante, y reanudación al colgar
- [ ] La reproducción sobrevive con la pantalla apagada un rato largo
- [ ] Una descarga completa de capítulo con Kokoro sin que el sistema mate el
      proceso a mitad

---

## Decisiones Técnicas Registradas

| Fecha | Decisión | Motivo |
|-------|----------|--------|
| 2026-04-29 | Flutter + Dart como framework | Similitud de Dart con C#, mejor rendimiento que React Native para audio |
| 2026-04-29 | Riverpod como gestor de estado | Más robusto que Provider, tipado estricto similar a C# |
| 2026-04-29 | Edge TTS vía WebSocket (reimplementado en Dart) | Paridad total con el prototipo de escritorio, mismas voces neuronales |
| 2026-04-29 | Android TTS nativo como fallback | Cero dependencias externas, funciona offline |
| 2026-04-29 | Caché de audio 5 días + LRU + 150 MB default | Re-escuchar párrafos sin re-síntesis ni consumo de datos |
| 2026-04-29 | Evicción inline antes de síntesis | El usuario nunca recibe un error por caché lleno |
| 2026-08-30 | Kokoro y Piper como motores auto-alojados, con repliegue a Edge | Mejor voz y funcionamiento sin internet, sin quedarse mudo cuando el servidor no está |
| 2026-08-30 | La clave de caché nombra el motor, no solo la voz | Un repliegue a Edge guardado bajo la clave de Kokoro servía audio de Edge diciendo que era de Kokoro |
| 2026-08-30 | Las descargas (`pinned`) solo las borra quien las pidió | Ni la evicción LRU, ni "Limpiar caché", ni la purga de 5 días pueden tocarlas |
| 2026-08-30 | Nada de funciones de ventana en SQL | Android 7, el mínimo soportado (API 24), trae SQLite 3.9; `ROW_NUMBER()` necesita 3.25 |

---

## Problemas Conocidos / Pendientes de Investigación

| # | Descripción | Estado |
|---|-------------|--------|
| 1 | Verificar que el protocolo WebSocket de Edge TTS no requiera token de sesión renovable | Pendiente |
| 2 | Confirmar que `epubx` maneja EPUBs con codificación no UTF-8 | Pendiente |
| 3 | Investigar comportamiento de just_audio con archivos MP3 parciales (síntesis en streaming) | Pendiente |
