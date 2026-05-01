# VoiceX Movil — Release History

Esquema de versiones: `MAJOR.MINOR.PATCH-PHASE.N+BUILD`
- `MAJOR` 0 = pre-release, 1 = estable publico
- `MINOR` features nuevas
- `PATCH` bug fixes
- `PHASE` preview → beta → rc → (omitido en estable)
- `BUILD` Android versionCode, siempre incrementa

---

## 0.2.0-preview.1+3 — 2026-04-30

Feature: portadas y metadatos de EPUB en la biblioteca.

### Funcionalidades nuevas
- Portada del libro extraída del EPUB (thumbnail en la lista, imagen grande en hoja de info)
- Hoja de información del libro: portada, título, autor, idioma, editorial, fecha de publicación, materia, descripción
- Botón de info (ⓘ) en cada tarjeta de la biblioteca
- Migración de base de datos v4: columnas `cover_path`, `description`, `publisher`, `published_date`, `subject` en `books`

### Bugs resueltos
- Marcadores solo guardaban desde el inicio de sección → ahora guardan el índice de oración exacta
- Libros con capítulos anidados (SubChapters) solo mostraban los capítulos raíz → ahora se aplana el árbol completo
- Contenido duplicado: selector CSS `p, div, li` seleccionaba contenedores padre e hijos `<p>` → ahora solo `p, li, blockquote, h1-h6` con fallback a divs hoja

---

## 0.1.0-preview.1+2 — 2026-04-30

Primera release de preview funcional.

### Funcionalidades
- Lector de EPUBs con navegacion por capitulos y parrafos
- TTS neural con Edge TTS (Microsoft) — voces en-US y es-MX, generos femenino/masculino
- TTS Android como fallback
- Highlight de oracion sincronizado con los WordTimestamp reales del servidor
- Auto-continuar lectura al terminar cada parrafo (flujo de audiolibro)
- Selector de velocidad: Lento (-20%), Normal (+0%), Rapido (+25%), Veloz (+50%)
- Controles: play / pausa / continuar / detener
- Cache LRU de audio con limite configurable (default 150 MB)
- Descarga de capitulos para escucha offline (almacenamiento permanente, no evictable)
- Marcadores por capitulo/parrafo
- Progreso de lectura persistido por libro
- Medidor de datos consumidos por sesion
- Tema oscuro/sepia

### Bugs resueltos en esta fase
- Edge TTS 403: headers duplicados por `WebSocket.connect()` usando `add()` en vez de `set()`
  → Fix: `HttpClient()..userAgent = null` como `customClient`
- Audio extraction: `_extractAudioChunk` buscaba `\r\n\r\n` en formato binario que usa `[uint16 header_len][header][audio]`
  → Fix: leer los 2 bytes de header length
- Pausa sin efecto: `just_audio 0.9.x` `play()` retorna Future que completa al terminar el audio,
  bloqueando el metodo antes de setear `state = playing`
  → Fix: `unawaited(_player.play())`, estado y ticker antes del play
- Cache key ignoraba `edgeRate` para Edge TTS → audio en velocidad incorrecta al cambiar velocidad
  → Fix: `speedHash = edgeRate` para provider edge

---

## Como hacer un nuevo release

1. Incrementar version en `pubspec.yaml`:
   - Bug fix: subir PATCH  →  `0.1.1-preview.1+3`
   - Feature nueva: subir MINOR, resetear PATCH  →  `0.2.0-preview.1+4`
   - Cambiar fase: preview → beta  →  `0.2.0-beta.1+5`
   - BUILD siempre sube +1

2. Documentar en este archivo bajo una nueva seccion `## VERSION — FECHA`

3. Compilar: `flutter build apk --release`

4. Tag git: `git tag v0.1.0-preview.1`
