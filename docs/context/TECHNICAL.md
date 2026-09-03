# VoiceX Móvil — Especificación Técnica (Android)

## Resumen

Lector EPUB con TTS neuronal para Android, distribuido como APK. Nació como
réplica de [VoiceX Desktop](https://github.com/PedroSolorzano/voicex)
(Python/tkinter) y hoy lo supera: tres motores de voz, descarga para escucha
sin conexión, controles en la pantalla de bloqueo y modo lectura estilo Kindle.

- **Plataforma:** Android 7.0+ (API 24)
- **Framework:** Flutter 3.x / Dart 3.x
- **Distribución:** APK sideload

Este documento describe *cómo está construido*. El historial de por qué cada
pieza es como es está en [RELEASES.md](../RELEASES.md).

---

## Stack

| Capa | Tecnología |
|------|-----------|
| UI | Flutter + Material 3 |
| Estado | Riverpod 2.x |
| Navegación | GoRouter |
| Motores TTS | Edge (WebSocket propio en Dart), Kokoro y Piper (HTTP) |
| Reproducción | just_audio + audio_service (MediaSession) |
| EPUB | epubx + html |
| Base de datos | sqflite (SQLite) |
| Configuración | shared_preferences |
| Red | http, connectivity_plus |

---

## Estructura

```
lib/
├── main.dart                  # Arranque: audio service + mantenimiento de caché
├── config/settings.dart       # AppSettings, voiceMap, resolveVoice
├── tts/
│   ├── tts_provider.dart      # Interfaz TTSProvider
│   ├── models.dart            # Voice, WordTimestamp, TTSResult
│   ├── edge_tts_provider.dart # WebSocket con protocolo de Edge
│   ├── kokoro_tts_provider.dart
│   ├── piper_tts_provider.dart
│   └── tts_factory.dart       # getProvider(settings, lang)
├── epub/
│   ├── models.dart            # Book, Chapter, Paragraph, Sentence
│   ├── parser.dart            # parseEpub(path) → Book
│   └── text_align.dart        # Alineado texto-audio por palabra y oración
├── audio/audio_player.dart    # VoiceXAudioHandler (audio_service)
├── services/dictionary.dart   # Wiktionary ES + diccionario EN
├── storage/
│   ├── database.dart          # Esquema SQLite y migraciones (v6)
│   └── repositories.dart      # LibraryRepo, ProgressRepo, BookmarkRepo, AudioCacheRepo
└── ui/
    ├── app.dart               # MaterialApp + GoRouter
    ├── providers/             # library, reader, settings, voices, share_import, app_info
    ├── screens/               # library, reader, settings
    └── widgets/               # book_card, book_info_sheet, highlighted_text,
                               # reader_theme, word_sheet

tools/kokoro/                  # Servidor Kokoro (Docker, puerto 8880)
tools/piper/                   # Servidor Piper (Docker, puerto 5000)
```

---

## Patrones

- **Strategy** — `TTSProvider` con cuatro implementaciones.
- **Factory** — `getProvider()` instancia según configuración e idioma.
- **Repository** — acceso a SQLite aislado por entidad.
- **Notifier** (Riverpod) — `ReaderNotifier` es el centro: posición, síntesis,
  caché, descargas y resaltado.

---

## Motores de voz

Los tres implementan `TTSProvider.synthesize()` y devuelven un `TTSResult`
con la ruta del audio y la lista de `WordTimestamp`.

| Motor | Transporte | Formato | Timestamps |
|---|---|---|---|
| **Edge** | WebSocket a `speech.platform.bing.com` | MP3 24 kHz 96 kbps | Por palabra (`WordBoundary`) |
| **Kokoro** | HTTP a servidor propio (`/dev/captioned_speech`) | AAC-LC 24 kHz ~94 kbps | Por palabra (`x-word-timestamps`) |
| **Piper** | HTTP a servidor propio (`/synthesize`) | WAV 22,05 kHz | Ninguno |

Ninguno de los tres funciona sin red: Edge necesita internet, Kokoro y Piper la
red local. Escuchar sin conexión se resuelve descargando por adelantado, no con
un motor local. El TTS del propio teléfono (`flutter_tts`) existió hasta 0.5.2 y
se retiró en 0.6.0: no marcaba palabras, sonaba a robot frente a las voces
neuronales y su WAV llenaba la caché.

Sin timestamps, `text_align.dart` reparte el tiempo entre oraciones de forma
aproximada y el resaltado baja de palabra a oración.

### Repliegue automático

Kokoro y Piper corren en una máquina de la red local que a menudo está apagada.
`ReaderNotifier._provider()` sondea el servidor antes de sintetizar y, si no
responde, sustituye el motor por Edge. Dos consecuencias que hay que respetar:

- La voz enviada al motor se resuelve con `voiceForEngine(motorActivo, idioma)`,
  no con `voiceFor(idioma)`. Pedirle `af_bella` a Edge devuelve audio vacío.
- La clave de caché nombra el motor que *produjo* el audio, no el seleccionado.

El motor realmente en uso aparece en la barra de estado del lector.

### Edge: detalles del protocolo

Mismo protocolo que la librería Python `edge-tts`. Requiere `TrustedClientToken`
en la URL, un token `Sec-MS-GEC` (SHA-256 sobre una ventana de 300 s con
corrección de desfase de reloj) y una cookie `muid`. El `HttpClient` se crea con
`userAgent = null` porque `WebSocket.connect()` aplica las cabeceras con
`add()`, no `set()`, y los duplicados provocan un 403. El historial completo de
esa investigación está en [`docs/bugs/EDGE_TTS_DEBUG.md`](../bugs/EDGE_TTS_DEBUG.md).

---

## Caché de audio y descargas

Dos niveles sobre la misma tabla, distinguidos por la columna `pinned`.

| | Caché (`pinned = 0`) | Descargas (`pinned = 1`) |
|---|---|---|
| Dónde | `getTemporaryDirectory()` | `getApplicationDocumentsDirectory()` |
| Origen | Se llena sola al reproducir | Botón "Descargar" o prefetch en WiFi |
| Caduca | 5 días sin usarse | Nunca |
| Evicción LRU | Sí, sobre el tope configurado | Nunca |
| "Limpiar caché" | La borra | No la toca |

**Regla que ninguna función puede romper:** una descarga solo la borra quien la
pidió, vía `deleteDownloads()`. Ni `pruneExpired()`, ni `evictLruUntilFit()`, ni
`clearAll()` pueden tocarla. Cubierto por `test/audio_cache_repo_test.dart`.

### Clave de caché

```
voice_id   = <motor>-<voz>[-<ritmo de Piper>]     # saneado a [A-Za-z0-9_-]
speed_hash = 'f96'                                 # generación del formato
```

Nombra el motor porque un repliegue a Edge guardado bajo la clave de Kokoro
serviría después audio de Edge diciendo que es de Kokoro. Piper añade el
`length_scale` porque el ritmo va grabado en las muestras. La velocidad de
reproducción **no** entra: se aplica en el reproductor, así que un solo archivo
sirve para todas las velocidades. El `speed_hash` es una generación de formato:
subirlo retira todo lo cacheado con el códec anterior.

La clave se incrusta en el nombre del archivo, de ahí el saneo.

### Búsqueda

`AudioCacheRepo.get()` ordena por `pinned DESC, id DESC` y recorre los
candidatos, descartando los que ya no están en disco o pesan menos de 512 bytes
(un audio truncado se reproduciría como "Source error" para siempre). Devuelve
el primero que sirva.

### Mantenimiento al arrancar

`main.dart` lanza, fuera del camino crítico:

1. `migrateCacheKeys()` — borra el audio de motores retirados, renombra claves
   de builds anteriores y elimina filas duplicadas, quedándose con la descarga
   o, si no la hay, con la más reciente. El borrado va primero: la regla
   catch-all del final etiqueta como `edge-` todo lo que no reconozca, y
   reetiquetaría un audio que ningún motor va a volver a pedir.
2. `pruneExpired()` — retira la caché temporal de más de 5 días.

> Las consultas SQL evitan funciones de ventana: Android 7 trae SQLite 3.9 y
> `ROW_NUMBER()` necesita 3.25.

---

## Base de datos

`getDatabasesPath()/voicex.db`, esquema en la versión 6. `PRAGMA foreign_keys`
se activa en `_onConfigure`: sqflite abre cada conexión con las claves ajenas
desactivadas, y sin esto los `ON DELETE CASCADE` nunca se disparan.

```sql
CREATE TABLE books (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    title            TEXT NOT NULL,
    author           TEXT NOT NULL,
    language         TEXT NOT NULL DEFAULT 'es',
    file_path        TEXT NOT NULL UNIQUE,
    added_at         TEXT NOT NULL DEFAULT (datetime('now')),
    cover_path       TEXT,
    description      TEXT,
    publisher        TEXT,
    published_date   TEXT,
    subject          TEXT,
    total_paragraphs INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE reading_progress (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    book_id         INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    chapter_index   INTEGER NOT NULL DEFAULT 0,
    paragraph_index INTEGER NOT NULL DEFAULT 0,
    sentence_index  INTEGER NOT NULL DEFAULT 0,
    offset_ms       INTEGER NOT NULL DEFAULT 0,
    global_index    INTEGER NOT NULL DEFAULT 0,
    updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(book_id)
);

CREATE TABLE bookmarks (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    book_id         INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
    chapter_index   INTEGER NOT NULL,
    paragraph_index INTEGER NOT NULL,
    sentence_index  INTEGER NOT NULL DEFAULT 0,
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
    pinned         INTEGER NOT NULL DEFAULT 0,
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    last_accessed  TEXT NOT NULL DEFAULT (datetime('now'))
);
```

`file_path` es la única columna `UNIQUE`, así que la unicidad por párrafo la
garantiza el código: `save()` y `savePin()` retiran la fila temporal que
sustituyen antes de insertar.

---

## Configuración (SharedPreferences)

| Campo | Default | Notas |
|---|---|---|
| `ttsProvider` | `edge` | `edge` · `kokoro` · `piper`. `AppSettings.resolveEngine()` devuelve a `edge` cualquier otro valor guardado por una versión anterior |
| `gender` | `female` | Solo para derivar la voz de Edge si no hay una explícita |
| `edgeVoiceEs` / `edgeVoiceEn` | `''` | Vacío = derivar de `gender` con `voiceMap` |
| `kokoroBaseUrl` | `''` | p. ej. `http://192.168.1.50:8880` |
| `kokoroVoiceEs` / `kokoroVoiceEn` | `af_bella` | El mismo default en ambos idiomas |
| `piperBaseUrl` | `''` | p. ej. `http://192.168.1.50:5000` |
| `piperVoiceEs` | `es_AR-daniela-high` | Un modelo por idioma: sus voces no son multilingües |
| `piperVoiceEn` | `en_US-lessac-high` | |
| `piperLengthScale` | `1.0` | Longitud de fonema; >1 más pausado. Va grabado en el audio |
| `playbackSpeed` | `1.0` | Se aplica al reproducir, no re-sintetiza |
| `edgeRate` / `edgeVolume` | `+0%` | Neutros a propósito, para que la caché no dependa de ellos |
| `highlightSentences` / `highlightWords` | `true` | |
| `prefetchOnWifi` | `true` | Descarga adelantada solo con WiFi y servidor propio |
| `prefetchChapters` | `3` | |
| `cacheMaxMb` | `150` | Mínimo 50 |
| `theme` | `dark` | `dark` · `light` · `system` |
| `fontSize` · `lineHeight` · `margin` · `readerFont` · `readerTheme` | 18 · 1.7 · 24 · serif · sepia | Ajustes del lector |
| `followAudioScroll` | `true` | El texto sigue al audio |

`voiceForEngine(engine, lang)` resuelve la voz de un motor concreto;
`voiceFor(lang)` es el atajo para el seleccionado. La distinción importa en el
repliegue: usar el atajo manda a Edge una voz que no existe en su catálogo.

---

## Reproducción en segundo plano

`VoiceXAudioHandler` (audio_service) publica la MediaSession con controles de
anterior / play-pausa / detener / siguiente. `MainActivity` **debe** extender
`AudioServiceActivity`: audio_service ejecuta el handler en su propio
FlutterEngine, y con `FlutterActivity` la app levanta un segundo motor aislado,
el servicio se queda sin handler y la notificación nunca llega a existir aunque
el audio suene con normalidad.

`skipToNext` y `skipToPrevious` delegan hoy en `nextParagraph` /
`previousParagraph`.

---

## Concurrencia

- El parseo de EPUB va en `compute()`: un libro grande bloquearía la UI.
- La síntesis es asíncrona y su resultado vuelve por el estado de Riverpod.
- El reproductor emite ticks periódicos que mueven el resaltado.
- El prefetch en WiFi es cancelable y se rinde al primer fallo, para no moler
  capítulos enteros contra un servidor caído.

---

## Seguridad

| Aspecto | Decisión |
|---------|----------|
| Claves API | Ninguna — Edge usa el token público del navegador |
| Permisos | `INTERNET`, `FOREGROUND_SERVICE`, scoped storage |
| Servidores propios | HTTP plano en red local, sin autenticación: no exponer fuera de la LAN |
| Datos del usuario | Los EPUB y el audio nunca salen del dispositivo |
| Analytics / telemetría | Ninguna |

---

## Tests

`flutter test` — cubre las funciones puras y los repositorios:

| Archivo | Cubre |
|---|---|
| `text_align_test.dart` | Alineado texto-audio |
| `parser_test.dart` | Troceado en oraciones, filtro de bloques cortos |
| `kokoro_test.dart` | `lang_code`, parseo de timestamps |
| `dictionary_test.dart` | Extracto de Wiktionary en español |
| `edge_tts_test.dart` | Locale de voz, troceado para síntesis |
| `audio_cache_repo_test.dart` | Caché y descargas sobre SQLite real (`sqflite_common_ffi`) |
| `cache_key_test.dart` | Construcción y saneo de la clave de caché |
| `settings_engine_test.dart` | Motor guardado por una versión que ofrecía más |

`lib/ui/` no tiene cobertura. Anotado en
[IMPROVEMENTS.md](../tasks/IMPROVEMENTS.md).
