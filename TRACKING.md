# VoiceX Móvil — Control de Implementación

**Proyecto:** Lector EPUB con TTS neuronal para Android  
**Stack:** Flutter / Dart  
**Inicio:** 2026-04-29  
**Referencia técnica:** [TECHNICAL.md](./TECHNICAL.md)

---

## Estado General

| Fase | Descripción | Estado | Inicio | Fin |
|------|-------------|--------|--------|-----|
| 1 | Setup y arquitectura base | Pendiente | — | — |
| 2 | Capa EPUB | Pendiente | — | — |
| 3 | Capa de almacenamiento | Pendiente | — | — |
| 4 | Capa TTS | Pendiente | — | — |
| 5 | Reproductor de audio | Pendiente | — | — |
| 6 | Pantalla Biblioteca | Pendiente | — | — |
| 7 | Pantalla Lectora | Pendiente | — | — |
| 8 | Pantalla Ajustes | Pendiente | — | — |
| 9 | Seguridad y rendimiento | Pendiente | — | — |
| 10 | Build y distribución APK | Pendiente | — | — |

**Leyenda de estado:** `Pendiente` · `En progreso` · `Completado` · `Bloqueado`

---

## Fase 1 — Setup y arquitectura base

**Estimado:** 3–4 días

- [ ] Instalar Flutter SDK y configurar entorno Android (Android Studio / SDK)
- [ ] Crear proyecto: `flutter create voicex_movil`
- [ ] Configurar `pubspec.yaml` con todas las dependencias
- [ ] Crear estructura de carpetas (`lib/config/`, `lib/tts/`, `lib/epub/`, etc.)
- [ ] Configurar navegación con GoRouter (rutas: `/library`, `/reader/:bookId`, `/settings`)
- [ ] Implementar tema visual (Material 3, colores dark/light, fondo sepia para lector)
- [ ] Verificar que la app arranca en emulador Android

**Notas:**
> _(espacio para anotar decisiones, problemas encontrados o cambios de rumbo)_

---

## Fase 2 — Capa EPUB

**Estimado:** 2–3 días

- [ ] Implementar modelos: `Sentence`, `Paragraph`, `Chapter`, `Book` en `epub/models.dart`
- [ ] Implementar `parseEpub(String path) → Book` usando `epubx` + `html`
- [ ] Replicar pipeline de limpieza: eliminar tags inútiles, filtro 20 chars, normalizar espacios
- [ ] Implementar `_splitSentences(text)` con regex `(?<=[.!?…])\s+`
- [ ] Detección de idioma (normaliza a `"es"` o `"en"`)
- [ ] Tests unitarios del parser con un EPUB real

**Notas:**

---

## Fase 3 — Capa de almacenamiento

**Estimado:** 2–3 días

- [ ] Implementar `database.dart`: schema SQLite completo (books, reading_progress, bookmarks, audio_cache)
- [ ] Implementar `LibraryRepo` (add, all, get, delete, updateLanguage, updateFilePath)
- [ ] Implementar `ProgressRepo` (save, get)
- [ ] Implementar `BookmarkRepo` (add, listForBook, delete)
- [ ] Implementar `AudioCacheRepo` (get, save, touch, totalSizeKb, evictLruUntilFit, evict, pruneExpired)
- [ ] Implementar `AppSettings` con SharedPreferences (todos los campos + `cacheMaxMb: 150`)
- [ ] `VOICE_MAP` y `resolveVoice()` idénticos al prototipo de escritorio
- [ ] Tests de repositorios con SQLite en memoria

**Notas:**

---

## Fase 4 — Capa TTS

**Estimado:** 4–5 días

- [ ] Definir clase abstracta `TTSProvider` con métodos `synthesize` y `listVoices`
- [ ] Implementar modelos `Voice`, `WordTimestamp`, `TTSResult` en `tts/models.dart`
- [ ] Implementar `EdgeTtsProvider`: protocolo WebSocket, audio MP3, word timestamps
- [ ] Implementar `AndroidTtsProvider`: flutter_tts, audio WAV, timestamps vacíos
- [ ] Implementar `tts_factory.dart`: `getProvider(settings, lang) → TTSProvider`
- [ ] Caché de lista de voces Edge: TTL 7 días en SharedPreferences
- [ ] Test de integración: sintetizar frase corta en español e inglés con cada proveedor

**Notas:**

---

## Fase 5 — Reproductor de audio

**Estimado:** 1–2 días

- [ ] Implementar `AudioPlayer` con just_audio
- [ ] Máquina de estados: `IDLE → PLAYING → PAUSED → IDLE`
- [ ] Stream de ticks cada 50 ms con `elapsedMs`
- [ ] Callbacks `onTick(int elapsedMs)` y `onEnd()`
- [ ] Manejo de audio en background (Android foreground service + notificación)

**Notas:**

---

## Fase 6 — Pantalla Biblioteca

**Estimado:** 2–3 días

- [ ] `LibraryScreen` con `ListView.builder` de `BookCard`
- [ ] `BookCard`: título, autor, badge idioma ES/EN, botón Leer, botón eliminar
- [ ] Toggle de idioma por libro (actualiza DB)
- [ ] FAB "+ Agregar EPUB" con `file_picker`
- [ ] Estado vacío con mensaje de instrucciones
- [ ] Detección de archivo faltante + diálogo para relocalizar el EPUB

**Notas:**

---

## Fase 7 — Pantalla Lectora

**Estimado:** 5–7 días

- [ ] Layout completo (AppBar, nav capítulo, área texto, nav párrafo, controles, barra estado)
- [ ] Widget `HighlightedText`: `RichText` con `TextSpan` para resaltado de oración activa
- [ ] Controles: ▶ Reproducir / ⏸ Pausar / ▶ Continuar / ⏹ Detener
- [ ] Selección de género de voz (♀ Femenina / ♂ Masculina)
- [ ] Navegación entre capítulos y párrafos
- [ ] Auto-avance: al terminar párrafo → siguiente; al terminar capítulo → siguiente
- [ ] Guardado de progreso al navegar o salir
- [ ] Marcadores: agregar (🔖), listar/saltar/eliminar (BottomSheet)
- [ ] Barra de estado: "Sintetizando…", "Reproduciendo…", "Fin del libro", errores

**Notas:**

---

## Fase 8 — Pantalla Ajustes

**Estimado:** 2–3 días

- [ ] Selector de proveedor TTS (Edge / Android)
- [ ] Grilla de voces: ES♀, ES♂, EN♀, EN♂ con botón "Probar" por cada una
- [ ] Slider de velocidad: 0.5× → 2.0× (15 pasos)
- [ ] Toggle de resaltado de oraciones
- [ ] Selector de tema: dark / light / system
- [ ] Sección caché: indicador de uso ("87 MB / 150 MB"), campo para ajustar tope (mín. 50 MB), botón "Limpiar caché"
- [ ] Botón Guardar con feedback visual

**Notas:**

---

## Fase 9 — Seguridad y rendimiento

**Estimado:** 2–3 días

- [ ] Permisos Android en `AndroidManifest.xml` (INTERNET, scoped storage API 29+)
- [ ] Limpieza de caché al iniciar: `pruneExpired()` + `evict(cacheMaxMb)` en Isolate background
- [ ] Lógica hit/miss: consultar caché antes de sintetizar; si hay hit → `touch()` + reproducir
- [ ] Evicción inline antes de síntesis: `evictLruUntilFit(estimado, maxMb)`
- [ ] Parseo de EPUBs grandes en `compute()` para no bloquear UI
- [ ] Liberar recursos TTS al cambiar de proveedor
- [ ] Manejo de errores de red: si Edge TTS falla → intentar caché → si no hay, mostrar mensaje claro
- [ ] Debounce en botón de play para evitar síntesis doble

**Notas:**

---

## Fase 10 — Build y distribución APK

**Estimado:** 1 día

- [ ] Configurar `build.gradle`: `applicationId`, `versionCode`, `versionName`
- [ ] Generar keystore: `keytool -genkey -v -keystore voicex.keystore ...`
- [ ] Configurar `key.properties` (agregarlo a `.gitignore`)
- [ ] Build release: `flutter build apk --release`
- [ ] Instalar APK en dispositivo Android físico y verificar funcionamiento completo
- [ ] Verificación end-to-end (ver checklist abajo)

**Notas:**

---

## Checklist de Verificación Final

- [ ] Abrir app → pantalla biblioteca vacía
- [ ] Agregar EPUB en español → aparece en lista
- [ ] Abrir libro → va al capítulo y párrafo guardado (o cap 1, pár 1 si es nuevo)
- [ ] Tap ▶ → sintetiza con Edge TTS → reproduce con resaltado de oración
- [ ] Tap ⏸ → pausa. Tap ▶ Continuar → reanuda desde posición exacta
- [ ] Al terminar párrafo → avanza automáticamente al siguiente
- [ ] Tap 🔖 → guarda marcador. Tap 📋 → lista marcadores, saltar a uno funciona
- [ ] Salir y volver → libro retoma donde se dejó
- [ ] Cambiar a Android TTS en ajustes → leer sin internet → funciona
- [ ] Volver a Edge TTS → el caché del párrafo anterior se reutiliza (sin re-síntesis)
- [ ] Ajustar tope de caché → limpiar caché → indicador muestra 0 MB
- [ ] APK instalable en dispositivo físico sin errores

---

## Decisiones Técnicas Registradas

| Fecha | Decisión | Motivo |
|-------|----------|--------|
| 2026-04-29 | Flutter + Dart como framework | Similitud de Dart con C#, mejor rendimiento que React Native para audio |
| 2026-04-29 | Riverpod como gestor de estado | Más robusto que Provider, tipado estricto similar a C# |
| 2026-04-29 | Edge TTS vía WebSocket (reimplementado en Dart) | Paridad total con el prototipo de escritorio, mismas voces neuronales |
| 2026-04-29 | Android TTS nativo como fallback | Cero dependencias externas, funciona offline |
| 2026-04-29 | Caché de audio 5 días + LRU + 150 MB default | El usuario necesita re-escuchar párrafos sin re-síntesis ni consumo de datos |
| 2026-04-29 | Evicción inline antes de síntesis | Garantiza que el usuario nunca reciba error por caché lleno |

---

## Problemas Conocidos / Pendientes de Investigación

| # | Descripción | Estado |
|---|-------------|--------|
| 1 | Verificar que el protocolo WebSocket de Edge TTS no requiera token de sesión renovable | Pendiente |
| 2 | Confirmar que `epubx` maneja EPUBs con codificación no UTF-8 | Pendiente |
| 3 | Investigar comportamiento de just_audio con archivos MP3 parciales (síntesis en streaming) | Pendiente |
