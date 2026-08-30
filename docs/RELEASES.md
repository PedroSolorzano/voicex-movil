# VoiceX Movil — Release History

Esquema de versiones: `MAJOR.MINOR.PATCH-PHASE.N+BUILD`
- `MAJOR` 0 = pre-release, 1 = estable publico
- `MINOR` features nuevas
- `PATCH` bug fixes
- `PHASE` preview → beta → rc → (omitido en estable)
- `BUILD` Android versionCode, siempre incrementa

---

## 0.4.0-preview.1 — 2026-08-30

Motores de voz auto-alojados y funciones para practicar inglés.

### Motores nuevos
- **Kokoro** en un servidor propio de la red local. Mejor calidad de voz que
  Edge, con tiempos por palabra intactos.
- **Piper**, con voces entrenadas en cada idioma. `es_AR-daniela-high` resultó
  la preferida en español. Es el más rápido: ~1,7 s para generar 26 s de audio.
- Ambos se repliegan **automáticamente a Edge** cuando el servidor no responde,
  así que tener la computadora apagada nunca deja la app muda. El motor
  realmente en uso se ve en la barra de estado del lector.
- `tools/kokoro/` y `tools/piper/` con compose y documentación.

### El problema del idioma en Kokoro
Kokoro deduce el idioma de la primera letra de la voz, así que `af_bella` leía
español con reglas inglesas: el mismo párrafo salía en 17 s en vez de 27,5 s,
ininteligible. Se corrige mandando `lang_code` explícito en cada petición.

### Descarga previa
- Al abrir un libro en WiFi, con el servidor accesible, se descargan por delante
  los siguientes capítulos. Nunca con datos móviles.
- Menú de descarga: este capítulo, los próximos N, o el libro completo con
  confirmación por tamaño.
- Así se escucha con la calidad del servidor de casa estando fuera.

### Practicar pronunciación
- **Repetir la oración** y modo bucle, para shadowing.
- **Pulsación larga sobre una palabra**: oírla, ver su definición, o mandarla a
  otra app. El audio se recorta del clip ya descargado, así que es instantáneo
  y funciona sin conexión.
- **Diccionario** de inglés vía dictionaryapi.dev. Es la única función del
  proyecto que necesita conexión; sin ella quedan pronunciar y "Otra app".

### Notas
- Piper no devuelve tiempos por palabra: su API contempla alineaciones por
  fonema pero los modelos españoles las devuelven vacías. El resaltado cae a la
  estimación por oración. Aceptado a propósito, porque el uso principal es
  escuchar conduciendo, donde la sincronización no aporta.
- El ritmo de Piper (`length_scale`) va grabado en el audio, así que cambiarlo
  invalida lo ya descargado. Para variar la velocidad sobre la marcha está el
  control de reproducción, que no re-sintetiza.

---

## 0.3.0-preview.1 — 2026-08-30

Tres frentes: naturalidad de la voz, la app como lector y no solo como
reproductor, y ~20 bugs.

### Voz y audio
- Audio de Edge TTS a 96 kbit/s (antes 48). Verificado contra el servidor que
  160 y 192 kbit/s devuelven cero bytes: 96 es el techo del endpoint gratuito.
- **Prefetch del párrafo siguiente**: desaparece el silencio de 1-2 s que había
  entre párrafos, que era lo que más rompía la ilusión de un narrador.
- El SSML ya no fija `xml:lang='en-US'` al hablar español.
- Catálogo completo de voces (300+) con caché de 7 días, buscador y prueba que
  ahora sí suena. Antes `listVoices()` devolvía lista vacía y el preview
  sintetizaba el audio para tirarlo.
- La velocidad se aplica al reproducir y sale de la clave de caché: cambiarla ya
  no re-sintetiza el libro ni gasta datos.
- Los párrafos largos se trocean por oración antes de sintetizar.

### Segundo plano y pantalla de bloqueo
- Servicio en primer plano con `audio_service`: la reproducción queda protegida
  de que el sistema la mate, y aparecen controles de play/pausa/anterior/
  siguiente en la pantalla de bloqueo, notificaciones, auriculares y Bluetooth.
- Sesión de audio 'speech': pausa en llamadas y baja volumen en notificaciones.

### Lector
- Modo inmersivo: el texto ocupa la pantalla completa y las barras se ocultan al
  tocar el centro. Antes el texto vivía aplastado entre cinco barras fijas.
- **Una sola posición compartida** entre leer y escuchar (modelo Kindle+Audible).
  El scroll ahora guarda posición, así que leer en silencio ya no se pierde.
- Reanuda a mitad de párrafo (oración + milisegundo) en vez de reiniciarlo.
- Tamaño de letra, interlineado, márgenes y tipografía configurables. La serif
  por fin se aplica: se pedía 'Georgia', que no existe en Android.
- Fondos sepia/claro/oscuro reales; antes el sepia estaba incrustado e ignoraba
  el tema oscuro.
- Progreso como "68% · faltan ~4 h" en vez de "Cap. 12 / 40".
- Resaltado por palabra además del de oración.

### Biblioteca
- Progreso por libro, búsqueda por título/autor y orden configurable.
- Los EPUB se copian a almacenamiento de la app: se acabaron las rutas rotas por
  scoped storage.
- "Abrir con VoiceX" desde el gestor de archivos y compartir hacia la app.

### Bugs resueltos
- El filtro de 20 caracteres descartaba diálogos cortos. En el EPUB de prueba se
  recuperan **633 párrafos** que no se leían ni se mostraban.
- El resaltado se desincronizaba sin recuperarse: se repartían los timestamps
  por conteo de palabras. Ahora cada palabra se ancla a su posición de carácter,
  así un token que no casa se descarta y el siguiente vuelve a anclar.
- El corte de oraciones rompía en abreviaturas ("Sr.") e iniciales ("J. R. R.").
- La pantalla de Ajustes existía pero no era alcanzable desde ninguna parte.
- El slider de velocidad de Android no hacía nada, y encima invalidaba la caché.
- El TTS de Android esperaba a que el archivo existiera, no a que la síntesis
  terminara: podía reproducir un WAV truncado.
- `PRAGMA foreign_keys` nunca se activaba, así que `ON DELETE CASCADE` no
  disparaba y borrar un libro dejaba progreso, marcadores y caché huérfanos.
- Fugas de archivos: temporales de síntesis y sidecars `.ts.json` se acumulaban
  para siempre.
- El EPUB se parseaba en el hilo de UI, y dos veces al importar.
- Deep link a `/reader/:id` reventaba por un cast sin validar.
- Faltaba el bloque `<queries>` con `TTS_SERVICE`, sin el cual flutter_tts no
  descubre motores en Android 11+.
- `existsSync()` dentro de `build()` en la lista de libros.
- Doble `Expanded` en la hoja de marcadores vacía.

### Base de datos
- v5: `sentence_index` y `offset_ms` en `reading_progress`; limpieza de filas
  huérfanas heredadas.
- v6: `books.total_paragraphs` y `reading_progress.global_index`, para el
  progreso de la biblioteca sin reparsear cada EPUB.

### Tests
- De un placeholder a 32 tests sobre corte de oraciones, filtro de bloques
  cortos, troceado para síntesis y anclaje de timestamps.

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
