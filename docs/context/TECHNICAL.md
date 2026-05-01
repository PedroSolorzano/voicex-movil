# VoiceX Móvil — Especificación Técnica (Android)

## Resumen

Replicación de VoiceX (lector EPUB con TTS neuronal) para Android. Distribuido vía APK. Todas las funcionalidades del prototipo de escritorio están contempladas, con mejoras propias del entorno móvil (caché de audio, modo offline parcial).

- **Plataforma:** Android (API 21+)
- **Framework:** Flutter 3.x / Dart 3.x
- **Distribución:** APK sideload (fase inicial), Google Play (futuro)
- **Prototipo base:** VoiceX Desktop (Python/customtkinter) en `../VoiceX/`

---

## Stack Tecnológico

| Capa | Tecnología | Equivalente en escritorio |
|------|-----------|--------------------------|
| UI | Flutter + Material 3 | customtkinter |
| Estado | Riverpod 2.x | Variables de instancia en vistas |
| TTS primario | Edge TTS WebSocket (Dart) | edge-tts (Python) |
| TTS offline | flutter_tts (Android nativo) | kokoro-onnx |
| Audio | just_audio | pygame.mixer |
| EPUB | epubx + html | ebooklib + beautifulsoup4 |
| Base de datos | sqflite (SQLite) | sqlite3 |
| Configuración | shared_preferences | Pydantic + JSON |
| Directorios | path_provider | tempfile / ~/.config |
| Archivos | file_picker | tkinter filedialog |

### Dependencias (pubspec.yaml)

```yaml
dependencies:
  flutter_riverpod: ^2.6.1       # State management
  sqflite: ^2.3.3                # SQLite
  path: ^1.9.0
  path_provider: ^2.1.4          # Rutas de sistema (temp, docs, cache)
  shared_preferences: ^2.3.3     # Persistencia de settings
  just_audio: ^0.9.40            # Reproducción MP3/WAV
  web_socket_channel: ^3.0.1     # WebSocket para Edge TTS
  http: ^1.2.2
  epubx: ^3.0.1                  # Parseo EPUB
  html: ^0.15.4                  # Parseo HTML (equivalente a bs4)
  file_picker: ^8.1.3            # Selector de archivos EPUB
  flutter_tts: ^4.0.2            # Android TTS nativo
  uuid: ^4.4.0                   # IDs para mensajes Edge TTS

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
```

---

## Estructura del Proyecto

```
VoiceXMovil/
├── lib/
│   ├── main.dart
│   ├── config/
│   │   └── settings.dart                 # AppSettings (SharedPreferences)
│   ├── tts/
│   │   ├── tts_provider.dart             # Interfaz abstracta TTSProvider
│   │   ├── models.dart                   # Voice, WordTimestamp, TTSResult
│   │   ├── edge_tts_provider.dart        # Edge TTS vía WebSocket
│   │   ├── android_tts_provider.dart     # Android TTS nativo (offline)
│   │   └── tts_factory.dart             # Factory: getProvider(settings, lang)
│   ├── epub/
│   │   ├── models.dart                   # Book, Chapter, Paragraph, Sentence
│   │   └── parser.dart                   # parseEpub(path) → Book
│   ├── audio/
│   │   └── audio_player.dart            # AudioPlayer (IDLE/PLAYING/PAUSED)
│   ├── storage/
│   │   ├── database.dart                # Schema SQLite + initDb()
│   │   └── repositories.dart            # LibraryRepo, ProgressRepo, BookmarkRepo, AudioCacheRepo
│   └── ui/
│       ├── app.dart                      # MaterialApp + GoRouter
│       ├── providers/
│       │   ├── library_provider.dart
│       │   ├── reader_provider.dart
│       │   └── settings_provider.dart
│       ├── screens/
│       │   ├── library_screen.dart
│       │   ├── reader_screen.dart
│       │   └── settings_screen.dart
│       └── widgets/
│           ├── book_card.dart
│           └── highlighted_text.dart
├── android/
│   └── app/src/main/AndroidManifest.xml
├── test/
├── pubspec.yaml
└── docs/
    ├── context/TECHNICAL.md              # Este archivo
    ├── tasks/TRACKING.md                 # Control de implementación
    └── RELEASES.md                       # Historial de versiones
```

---

## Arquitectura

### Capas del Sistema

```
┌─────────────────────────────────────────────┐
│              UI Layer                        │
│   Flutter Screens · Widgets · Riverpod      │
├─────────────────────────────────────────────┤
│         Application Logic Layer             │
│   TTS Providers · AudioPlayer · EPUB Parser │
├─────────────────────────────────────────────┤
│         Data Access Layer                   │
│   LibraryRepo · ProgressRepo · BookmarkRepo │
│   AudioCacheRepo                            │
├─────────────────────────────────────────────┤
│         Config & Models                     │
│   AppSettings · EPUB Models · TTS Models    │
└─────────────────────────────────────────────┘
```

### Patrones de Diseño

- **Strategy**: `TTSProvider` abstracto → `EdgeTtsProvider` / `AndroidTtsProvider`
- **Factory**: `tts_factory.dart:getProvider()` instancia el proveedor según config
- **Repository**: acceso a SQLite aislado por entidad
- **Observer**: stream de ticks del `AudioPlayer` → `ReaderProvider` → `HighlightedText`
- **State Notifier** (Riverpod): reemplaza las variables de instancia del escritorio

---

## Modelo de Concurrencia

```
[Main Thread — Flutter UI]
        │
        ├─ Tap ▶ en párrafo
        │       └─> Isolate / compute()
        │               ├─> AudioCacheRepo.get() → hit o miss
        │               ├─> [miss] evictLruUntilFit() → EdgeTtsProvider.synthesize()
        │               └─> notifyProvider → UI reproduce audio
        │
        └─> AudioPlayer (just_audio)
                ├─ Stream.periodic(50ms) → onTick(elapsedMs)
                └─ playerStateStream → onEnd()
```

- Toda síntesis TTS corre fuera del main thread (`compute()` o `Isolate`)
- Los resultados se devuelven al main thread vía Riverpod state
- Regla: ninguna operación costosa toca el main thread

---

## TTS: Edge TTS en Dart (WebSocket)

El protocolo es el mismo que usa la librería Python `edge-tts` — cliente WebSocket que imita al navegador.

**Endpoint:**
```
wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1
    ?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4
    &ConnectionId={uuid_v4}
```

**Flujo de síntesis:**
1. Conectar con cabeceras `Origin` y `User-Agent` de Chrome
2. Enviar mensaje de configuración: formato `audio-24khz-48kbitrate-mono-mp3`
3. Enviar SSML con voz, rate y texto
4. Recibir chunks binarios (audio MP3) + mensajes `WordBoundary` (timestamps)
5. Escribir audio a archivo en caché
6. Retornar `TTSResult(filePath, [WordTimestamp(...)])`

**Bitrate:** 48 kbps → 6 KB/segundo de audio → ~240 KB por párrafo promedio

## TTS: Android TTS (fallback offline)

- Usa `flutter_tts` que envuelve el motor TTS del sistema Android
- Genera WAV sin timestamps (igual que Kokoro en el escritorio)
- Voces disponibles: dependen del dispositivo y del idioma instalado
- Sin internet requerido

---

## Caché de Audio

Los archivos sintetizados se conservan para re-reproducción instantánea.

### Parámetros

| Parámetro | Valor |
|-----------|-------|
| TTL | 5 días desde `last_accessed` |
| Tope default | 150 MB (configurable sin máximo fijo) |
| Mínimo configurable | 50 MB |
| Evicción | LRU — dos momentos: startup + antes de cada síntesis |
| Garantía | El usuario nunca recibe error por caché lleno |

### Clave de caché

```
{book_id}_{chapter_idx}_{para_idx}_{voice_id}_{speed_hash}.mp3
```

Cambiar voz o velocidad produce claves distintas — los archivos anteriores quedan huérfanos y son eviccionados por LRU/TTL.

### Tabla SQLite

```sql
CREATE TABLE audio_cache (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    book_id        INTEGER NOT NULL,
    chapter_idx    INTEGER NOT NULL,
    para_idx       INTEGER NOT NULL,
    voice_id       TEXT NOT NULL,
    speed_hash     TEXT NOT NULL,
    file_path      TEXT NOT NULL UNIQUE,
    file_size_kb   INTEGER NOT NULL,
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    last_accessed  TEXT NOT NULL DEFAULT (datetime('now'))
);
```

### Flujo de reproducción con caché

```
Tap ▶ en párrafo
  ↓
AudioCacheRepo.get(book, chapter, para, voice, speed)
  ├─ HIT  → touch(last_accessed) → reproducir (instantáneo, sin datos)
  └─ MISS → estimar tamaño (~6 KB × seg estimados)
               ↓
             evictLruUntilFit(estimado, maxMb)  ← borra LRU si necesario
               ↓
             EdgeTtsProvider.synthesize() → guardar en caché
               ↓
             reproducir
```

### Limpieza al iniciar la app (background Isolate)

1. `pruneExpired()` — elimina entradas con `last_accessed` > 5 días
2. `evict(maxMb)` — si supera el tope, elimina LRU hasta quedar al 80%

### Beneficio offline

Párrafos ya sintetizados con Edge TTS funcionan sin internet mientras estén en caché.

---

## Base de Datos SQLite

**Ubicación:** `getDatabasesPath()/voicex.db`

```sql
CREATE TABLE books (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT NOT NULL,
    author      TEXT NOT NULL,
    language    TEXT NOT NULL DEFAULT 'es',
    file_path   TEXT NOT NULL UNIQUE,
    added_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE reading_progress (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    book_id         INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    chapter_index   INTEGER NOT NULL DEFAULT 0,
    paragraph_index INTEGER NOT NULL DEFAULT 0,
    updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(book_id)
);

CREATE TABLE bookmarks (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    book_id         INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    chapter_index   INTEGER NOT NULL,
    paragraph_index INTEGER NOT NULL,
    note            TEXT,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE audio_cache (
    id             INTEGER PRIMARY KEY AUTOINCREMENT,
    book_id        INTEGER NOT NULL,
    chapter_idx    INTEGER NOT NULL,
    para_idx       INTEGER NOT NULL,
    voice_id       TEXT NOT NULL,
    speed_hash     TEXT NOT NULL,
    file_path      TEXT NOT NULL UNIQUE,
    file_size_kb   INTEGER NOT NULL,
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    last_accessed  TEXT NOT NULL DEFAULT (datetime('now'))
);
```

---

## Configuración (AppSettings)

**Almacenamiento:** `SharedPreferences`

| Campo | Tipo | Default | Notas |
|-------|------|---------|-------|
| `ttsProvider` | String | `"edge"` | `"edge"` \| `"android"` |
| `gender` | String | `"female"` | `"female"` \| `"male"` |
| `edgeRate` | String | `"+0%"` | `-50%` a `+50%` |
| `edgeVolume` | String | `"+0%"` | `-50%` a `+50%` |
| `androidSpeed` | double | `1.0` | `0.5` a `2.0` |
| `highlightSentences` | bool | `true` | |
| `theme` | String | `"dark"` | `"dark"` \| `"light"` \| `"system"` |
| `cacheMaxMb` | int | `150` | Mínimo 50, sin máximo |

**VOICE_MAP** (idéntico al prototipo de escritorio):
```dart
const voiceMap = {
  'edge': {
    'es': {'female': 'es-MX-DaliaNeural', 'male': 'es-MX-JorgeNeural'},
    'en': {'female': 'en-US-JennyNeural', 'male': 'en-US-GuyNeural'},
  },
  'android': {
    'es': {'female': 'es-ES', 'male': 'es-ES'},
    'en': {'female': 'en-US', 'male': 'en-US'},
  },
};
```

---

## Seguridad

| Aspecto | Decisión |
|---------|----------|
| Claves API | Ninguna — Edge TTS usa token público del navegador |
| Permisos Android | `INTERNET`, `READ_EXTERNAL_STORAGE` (scoped storage API 29+) |
| Caché de audio | Directorio privado de la app, no accesible por otras apps |
| Datos del usuario | EPUBs y audio nunca salen del dispositivo |
| Analytics | Ninguno |
| Telemetría | Ninguna |

---

## Pantallas y Funcionalidades

### Biblioteca (`/library`)
- Lista scrollable de libros con tarjetas
- Cada tarjeta: título, autor, badge idioma (ES/EN), botón Leer, botón eliminar
- Toggle de idioma por libro
- FAB "+ Agregar EPUB" con file picker
- Estado vacío con instrucciones
- Detección de archivo faltante + diálogo para relocalizar

### Lector (`/reader/:bookId`)
- Navegación entre capítulos y párrafos
- Área de texto con fuente serif y fondo sepia
- Resaltado de oración activa durante reproducción (RichText + TextSpan)
- Controles: ▶ Reproducir / ⏸ Pausar / ▶ Continuar / ⏹ Detener
- Selección de género de voz (♀ / ♂)
- Auto-avance al terminar párrafo → siguiente párrafo → siguiente capítulo
- Marcadores: agregar (🔖), listar/saltar/eliminar (BottomSheet)
- Guardado de progreso al navegar o salir
- Barra de estado: "Sintetizando…", "Reproduciendo…", errores de red

### Ajustes (`/settings`)
- Selector de proveedor TTS (Edge / Android)
- Grilla de voces: ES♀, ES♂, EN♀, EN♂ con botón "Probar" por voz
- Slider de velocidad: 0.5× → 2.0× (15 pasos)
- Toggle de resaltado de oraciones
- Selector de tema: dark / light / system
- **Sección caché:** uso actual (ej. "87 MB / 150 MB"), campo para ajustar tope, botón "Limpiar caché"
- Botón Guardar

---

## Equivalencias Escritorio → Android

| Desktop Python | Android Flutter |
|---------------|-----------------|
| `asyncio` en thread daemon | `compute()` / `Isolate` |
| `widget.after(0, fn)` | `ref.read(notifier).state = ...` |
| `pygame.mixer` | `just_audio` |
| `CTkTextbox` + highlight tag | `RichText` + `TextSpan` |
| `CTkScrollableFrame` | `ListView.builder` |
| `tempfile.mkdtemp()` | `getTemporaryDirectory()` |
| `~/.config/voicex/library.db` | `getDatabasesPath()/voicex.db` |
| Modal `CTkToplevel` | `showModalBottomSheet()` |
| `filedialog.askopenfilename()` | `FilePicker.platform.pickFiles()` |
| Settings JSON en `~/.config` | `SharedPreferences` |
