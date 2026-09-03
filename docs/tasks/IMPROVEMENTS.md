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
  Kokoro entraría como proveedor adicional para no depender de internet.
  Medido: Kokoro da timestamps por palabra
  (cabecera `x-word-timestamps`), va a ~5x tiempo real en CPU, y solo tiene 3
  voces en español frente a las 11 de Edge.
- [ ] `medio` 2026-09-02 — **Reconsiderar el TTS nativo del teléfono.** Se
  retiró en 0.6.0 por no marcar palabras, sonar peor y llenar la caché con WAV.
  Un lector de la competencia lo usa con la voz de fabricante del propio Samsung
  y ofrece control de tono, que ningún motor actual expone. Es además la única
  forma de leer sin red **ni** servidor: hoy Edge necesita internet, y Kokoro y
  Piper la red local o Tailscale. Antes de decidir hay que oír la voz de Samsung
  en el teléfono al lado de Edge: si la distancia es la que se supuso al
  retirarlo, la decisión queda cerrada; si no, vuelve como motor de respaldo
  sin conexión. Ver `docs/RELEASES.md` 0.6.0 para el razonamiento original.
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

## Experiencia de lectura

La app nació para escuchar, y se nota: casi todo lo de aquí existe ya en
cualquier lector de la competencia. Leer en silencio es hoy el flujo peor
atendido.

- [ ] `alto` 2026-09-02 — **Ajustar el tamaño del texto sin salir del libro.**
  Los controles existen —tamaño 12-32, interlineado, márgenes, tipografía y
  fondo— pero viven en la pantalla global de Ajustes
  (`settings_screen.dart:398-450`), entre el motor TTS y la caché: el botón de
  la barra del lector hace `context.push('/settings')`
  (`reader_screen.dart:304`). Ajustar la letra obliga a abandonar la lectura,
  volver, y repetir hasta acertar. Hace falta una hoja inferior en el propio
  lector con esos mismos ajustes, viendo el texto cambiar detrás. Y un
  pellizco para el tamaño: hoy no hay ningún gesto de escala en `lib/`, solo
  `onTap` y `onLongPressStart`.
- [ ] `alto` 2026-09-02 — **Subrayar y anotar.** No existe nada persistente que
  elija el usuario: lo único resaltado es la oración o la palabra que suena, y
  se borra al parar. Los marcadores guardan solo una posición
  (`bookmarks(chapter_index, paragraph_index, sentence_index)`,
  `database.dart:71-81`), no un rango de texto. La mitad del camino ya está
  hecha y muerta: la columna `bookmarks.note` existe y `BookmarkRepo.add` la
  acepta (`repositories.dart:151`), pero **ningún llamador la rellena** —
  `addBookmark` (`reader_provider.dart:990-1000`) la omite, y la hoja de
  marcadores la mostraría si estuviera (`reader_screen.dart:1090`). Falta:
  rango de caracteres y color en el esquema, y una UI para crear el subrayado.
- [ ] `alto` 2026-09-02 — **Seleccionar texto.** No se puede: los párrafos son
  `Text` plano (`reader_screen.dart:568,580`) y no hay `SelectableText`,
  `SelectionArea` ni `Clipboard` en todo `lib/`. La pulsación larga resuelve
  **una sola palabra** por hit-test sobre el `RenderParagraph`
  (`reader_screen.dart:539-552`) y ofrece pronunciar, diccionario y "otra app".
  No hay copiar una cita, ni compartirla, ni seleccionar una frase. Es el
  cimiento del subrayado: conviene hacerlo antes.
- [ ] `medio` 2026-09-02 — **Más formatos: PDF, MOBI y compañía.** Hoy solo
  EPUB, y el filtro es duro en los dos caminos de entrada:
  `allowedExtensions: ['epub']` (`library_screen.dart:167`) y
  `if (!path.toLowerCase().endsWith('.epub')) return;`
  (`share_import_provider.dart:42`). El parser depende de `epubx` y del spine
  OPF (`parser.dart:13-30`), así que cada formato nuevo necesita su propio
  extractor detrás de una interfaz común que devuelva `Book`. Por dificultad:
  **TXT** es casi gratis; **MOBI/AZW3** es un formato hermano y hay paquetes
  Dart; **FB2** es XML directo; **PDF** es harina de otro costal —maquetado por
  coordenadas, sin párrafos lógicos— y romper un PDF en oraciones limpias para
  TTS es un proyecto en sí mismo, no una importación más.
- [ ] `medio` 2026-09-02 — **Buscar dentro del libro.** No existe. La única
  búsqueda es por título y autor en la biblioteca
  (`library_screen.dart:59-82`). Con el libro ya troceado en párrafos y
  oraciones en memoria, buscar y saltar al resultado es barato.
- [ ] `medio` 2026-09-02 — **La barra de progreso no se puede arrastrar.** Es un
  `LinearProgressIndicator` (`reader_screen.dart:740-744`), un indicador y no un
  control: para moverte por el libro solo queda el índice de capítulos o ir
  párrafo a párrafo. Falta arrastrar, o un "ir al %".
- [ ] `medio` 2026-09-02 — **El texto pierde el formato del libro.** El parser
  aplana a texto plano: se descartan imágenes, tablas y notas al pie, y el CSS
  del EPUB se ignora entero (`parser.dart:131-186`), así que cursivas, negritas
  y versos desaparecen. Para escuchar da igual; leyendo, un libro con énfasis o
  ilustraciones se lee peor que en cualquier otro lector.
- [ ] `bajo` 2026-09-02 — **La pantalla se apaga leyendo en silencio.** El
  `WAKE_LOCK` del manifest (`AndroidManifest.xml:13`) mantiene viva la CPU para
  el audio, no la pantalla, y no hay ningún control de brillo ni bloqueo de
  orientación. Leer sin tocar la pantalla acaba a oscuras.
- [ ] `bajo` 2026-09-02 — **Abrir un marcador arranca el audio.**
  `jumpToBookmark` llama a `play()` incondicionalmente
  (`reader_provider.dart:1012-1017`): consultar un pasaje marcado mientras lees
  en silencio te pone a sonar el TTS de golpe.
- [ ] `bajo` 2026-09-02 — **Sin estadísticas de lectura.** No se registra tiempo
  leído, sesiones ni rachas; no hay tabla que lo soporte. Lo único cuantitativo
  es el `%` y una estimación del **tiempo de escucha** restante
  (`reader_screen.dart:876-894`).

---

## Acceso remoto a Kokoro y Piper

Análisis completo en [`docs/context/ACCESO_REMOTO.md`](../context/ACCESO_REMOTO.md).
La opción recomendada, Tailscale, **no necesita nada de esto**: es red privada,
no URL pública. Lo de aquí solo hace falta el día que se elija exponer el
servidor a internet.

- [ ] `medio` 2026-09-02 — **El health check de 3 s es demasiado estricto.**
  `kokoro_tts_provider.dart:94-98` y `piper_tts_provider.dart:54-58` dan tres
  segundos al saludo y cachean el resultado 30 s. La síntesis va holgada (180 s
  y 120 s), así que el cuello de botella es el saludo, no el trabajo. Una red
  móvil lenta o un servidor recién despertado agotan ese plazo y la app **se
  repliega a Edge en silencio**, indistinguible de un servidor caído. Un
  reintento o un plazo mayor. Es el único de esta sección que vale la pena
  aunque nunca se salga de Tailscale.
- [ ] `bajo` 2026-09-02 — **Campo de token en Ajustes**, junto a la dirección
  del servidor. Sin él, ninguna opción con autenticación real es viable.
- [ ] `bajo` 2026-09-02 — **Que los providers manden ese token como cabecera**
  (`Authorization`, `CF-Access-Client-Id`, o la que pida el proveedor elegido)
  en la síntesis, el health check y el listado de voces. Hoy solo mandan
  `Content-Type` (`kokoro_tts_provider.dart:159`, `piper_tts_provider.dart:105`),
  y ninguno de los dos servidores exige nada: la "API key" de Kokoro-FastAPI es
  la cadena literal `not-needed`. Cualquier URL pública deja la CPU de casa a
  disposición de quien la encuentre.
- [ ] `bajo` 2026-09-02 — **Medir el consumo real de Kokoro.** La tabla de datos
  móviles da ~29 MB por hora de escucha suponiendo 64 kbps, pero el bitrate del
  encoder no está documentado: a 128 kbps serían ~58 MB. Piper sí está medido y
  es aritmética, no estimación: WAV sin comprimir, ~159 MB/hora. Los dos `curl`
  para medirlo están al final de `ACCESO_REMOTO.md`.

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
