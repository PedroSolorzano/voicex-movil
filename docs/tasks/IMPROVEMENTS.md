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
- [x] `medio` 2026-09-02 — **Reconsiderar el TTS nativo del teléfono.** Se
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

- [x] `medio` 2026-08-30 — **La clave de caché de Kokoro no lleva el idioma.**
  `kokoroVoiceEs` y `kokoroVoiceEn` valen `af_bella` por defecto, así que un
  libro con el idioma cambiado de ES a EN reutiliza el audio ya cacheado
  aunque el `lang_code` enviado al servidor sea distinto — y con reglas
  inglesas el español sale en ~17 s en vez de ~27 s, ininteligible. Lo mismo
  aplica a Piper si se configura la misma voz en ambos idiomas. Edge se libra
  porque el nombre de la voz ya lleva el locale. Arreglar significa meter
  `book.language` en la clave y migrar las filas existentes leyendo
  `books.language`; si no, se huerfanizan todas las descargas hechas hasta hoy.
  Documentado en `test/cache_key_test.dart`.
- [x] `medio` 2026-09-03 — **Reemplazar Piper por algo que suene en español —
  veredicto: Chatterbox Multilingual, integración en curso.** Reportado desde
  la app: *"no me gusta ese modelo, buscar una alternativa que tenga
  entrenamiento de voces en español, pero que sea mejor"*. Probado en la
  laptop con la RTX 4050 contra Kokoro y Piper
  ([`docs/context/TTS_ESPANOL.md`](../context/TTS_ESPANOL.md)): ganó
  **Chatterbox Multilingual clonando una voz** — la predefinida en inglés
  arrastraba el idioma de la síntesis a pesar de pedir `language: es`, pero con
  una referencia en español (probado con la voz de Piper `es_MX-claude-high` y
  con una grabación propia) el resultado es correcto. Dos voces clonadas
  elegidas: `piper-mx-clon.wav` y `voz-propia.mp3`.
  - Contras medidos: ~55-75 s de síntesis por párrafo de ~25 s de audio (más
    lento que tiempo real, a diferencia de Kokoro/Piper), y solo sirve para
    español — el modelo no da marcas por palabra, igual que Piper.
  - Requiere GPU, así que no reemplaza a Kokoro/Piper en `voicex-server` (sin
    GPU): corre en una laptop personal, como segundo nodo intermitente de la
    tailnet (se apaga con la laptop, la app cae a Edge en silencio).
  - `ChatterboxTtsProvider` ya integrado en `lib/tts/`, con su caso en
    `tts_factory.dart`, `settings.dart` y `reader_provider.dart`. Falta:
    Tailscale nativo en la laptop (el contenedor Docker con `network_mode:
    host` no expone una interfaz real en Docker Desktop para Windows — ver
    intento fallido en el historial de esta tarea) y compilar con
    `CHATTERBOX_URL` para probar de punta a punta.
  - La voz `es_MX-claude-high` de Piper directamente (sin Chatterbox) se
    volvió a confirmar con errores de lectura (`tools/piper/README.md`): no es
    la solución barata que este ítem sugería probar primero.
  - **Superado por el ítem siguiente:** Chatterbox queda descartado por
    velocidad, no por calidad.
- [x] `alto` 2026-09-06 — **Cambiar Chatterbox por F5-Spanish, y sacar
  Chatterbox de la app.** **Hecho en 0.8.0.** Chatterbox gana en calidad pero es inviable para un
  audiolibro: medido en la RTX 4050, **0.089x tiempo real** — un capítulo de 37
  párrafos son ~2.9 horas de GPU. Peor: el servidor completa el audio y el
  cliente ya se rindió, así que se tira a la basura (ver
  [`docs/bugs/CHATTERBOX_DESCARGAS.md`](../bugs/CHATTERBOX_DESCARGAS.md)).
  - **F5-Spanish ([`jpgallegoar/F5-Spanish`](https://huggingface.co/jpgallegoar/F5-Spanish),
    CC0) va por encima de tiempo real en la misma tarjeta con `nfe_step 64`**:
    1.26x en un párrafo suelto y 0.60x en texto largo, donde el troceo en
    lotes pesa. El capítulo baja de 2.9 horas a ~26 minutos. La razón es
    arquitectónica y contradice lo que suponía
    [`TTS_ESPANOL.md`](../context/TTS_ESPANOL.md) al descartarlo ("en la 4050
    competirían de igual a igual"): F5 no es autoregresivo, genera en un
    número fijo de pasos en paralelo. Arquitectura F5TTS_Base, verificada
    contra el `transformer_config.yaml` del propio checkpoint.
  - Calidad juzgada de oído contra Chatterbox por quien reportó el problema:
    **igualada**, con una referencia de voz limpia de 11 s (36.9 dB de SNR).
  - `nfe_step` **64 en vez de 32 no es opcional**: con el valor por defecto
    aparecen tartamudeos y repeticiones (`trabajo` → "trabajo abajo"),
    verificado transcribiendo la salida y comparándola con el texto pedido.
    A 64 la lectura sale al 100 %. Cuesta la mitad de velocidad y aun así
    queda por encima de tiempo real.
  - **Hace falta una tabla de sustituciones fonéticas antes de sintetizar**,
    y cubre dos casos distintos:
    - *Palabras españolas sueltas*: el modelo pronuncia "quizá" como
      "guizás"; reescrito `kizá` sale perfecto. **No es sistemático de la
      "qu"** — probado con pares mínimos (*quiso/guiso*, *quita/guita*): el
      resto sale bien. Pasado un corpus de 378 palabras de prosa real, **no
      apareció ningún otro error en español**, así que la lista es corta.
    - *Nombres propios extranjeros*: es el defecto que sí aparece seguido en
      novela traducida. `Jack Sawyer` → "jakq sayer", `New Hampshire` →
      "neuampa re", `Speedy` → "spady". Reescritos `Yac Sóyer`, `Niu
      Jámpshir`, `Spidi` suenan mejor, confirmado de oído. Diez entradas por
      libro cubren la mayoría, porque los nombres que importan se repiten
      cientos de veces.
    - Se descartó detectar automáticamente las palabras extranjeras contra un
      diccionario español: el riesgo de falso positivo (conjugaciones,
      nombres propios españoles) es peor que el problema que resuelve.
  - Detectarlas requiere un reconocedor **sin** modelo de lenguaje — Whisper
    las tapa porque las "corrige" al transcribir. Herramientas dejadas en
    `muestras_voz/`: `_detectar.py` (CTC + normalización fonética del
    español, para no marcar el seseo como error), `_analyze.py` y `_bands.py`
    (calidad de una grabación), `_cortar.py` (ventana de 12 s), `_verificar.py`
    (inserciones y omisiones con Whisper).
  - Segundo defecto anotado: la **primera palabra** de cada generación sale
    inestable ("Él" → "Gul"). Afecta el arranque de cada párrafo.
  - El ritmo de la referencia **fija el ritmo de todo lo generado**: la misma
    voz leyendo más lento dio 42 s contra 32 s para el mismo párrafo.
  - Trabajo pendiente: servidor HTTP para F5 (el CLI no expone uno usable),
    transcodificar a MP3 —F5 emite WAV a 24 kHz y el WAV ya descalificó a
    Piper por consumo de datos—, `F5TtsProvider` nuevo, y **borrar
    `ChatterboxTtsProvider`** de `lib/tts/`, `tts_factory.dart`,
    `settings.dart`, `reader_provider.dart` y `server_config.dart`.
- [ ] `alto` 2026-09-03 — **La previsualización de voz del motor Teléfono se
  cuelga para siempre tras el primer fallo del motor nativo.** Reportado por
  un tester: *"no me funcionan los previos de las voces, solo me funcionó
  como 10 veces y después dejaron de funcionar"*
  (`docs/bugs/REPORTES_TESTERS.md`, 2026-09-03 21:40). Investigado en
  [`docs/bugs/ANDROID_TTS_PREVIEW.md`](../bugs/ANDROID_TTS_PREVIEW.md): el
  plugin `flutter_tts` no resuelve el `Future` de `synthesizeToFile` cuando el
  motor nativo reporta error (solo lo hace en `onDone`), así que el `await` en
  `_preview()` (`settings_screen.dart:786`) cuelga sin excepción y deja
  `_previewing` fijo -- el guardián de reentrada de la línea 774 vuelve mudo
  cualquier botón de previsualizar de ahí en más. Arreglo probable: un
  `.timeout(...)` alrededor de esa síntesis para que el cuelgue caiga por el
  mismo `catch` que ya maneja los demás fallos. Sin reproducir en banco
  todavía, solo rastreado por código.
- [x] `alto` 2026-09-06 — **`resetServerHealthCache` borra `_busyUntil` junto
  con el caché de red, y sigue pasando con F5.** Detectado en la recaída del
  2026-09-06 de `docs/bugs/CHATTERBOX_DESCARGAS.md` (dos reportes desde la
  app sobre descargas de *La Odisea* que volvían a fallar tras el primer
  arreglo). `_busyUntil` (`server_health.dart:41`) es lo que la app sabe del
  *servidor* — que sigue ocupado terminando una síntesis que el cliente
  abandonó por timeout (`markServerBusy`, ahora usado por
  `f5_tts_provider.dart:99`, antes por Chatterbox) — y `resetServerHealthCache`
  (`server_health.dart:44-47`) lo limpia igual que el caché de *conexión*, sin
  distinguir uno de otro. Dos llamadores ajenos a la descarga lo disparan sin
  condición: el botón "Probar conexión" (`settings_screen.dart:83`) y cada
  evento de `Connectivity().onConnectivityChanged`
  (`reader_provider.dart:298`, que Android puede emitir varias veces por
  transición de red). Un tester frustrado con una descarga probando la
  conexión, o un simple cambio de red a mitad de descarga, reabre la ventana
  contra un servidor que sigue ocupado y encadena el mismo patrón de
  `unreachable` en los párrafos siguientes. La migración a F5 no lo evita
  porque reusa el mismo mecanismo de `busyUntil`. Ajuste propuesto en el bug:
  separar el reset de `server_health.dart:44-47` para que
  `resetServerHealthCache` no toque `_busyUntil`, o exponer un reset aparte
  para los dos call sites de arriba; de paso, darle a `maybePrefetchAhead`
  (`reader_provider.dart:1416`) una guardia de reentrada propia, en vez de
  depender solo de `state.isDownloading`.

  Hecho en 0.9.0, y por un lado que no estaba propuesto: el servidor F5 ya
  publicaba `"busy"` en `/health` (`tools/f5/server.py:146`) y la app tiraba el
  cuerpo de la respuesta. Ahora lo lee, así que la ventana de ocupado deja de
  ser una conjetura del teléfono y pasa a ser lo que el servidor dice de sí
  mismo. Encima de eso van las tres piezas propuestas: el reset ya no toca
  `_busyUntil`, `downloadChapters` levanta su bandera sincrónicamente y los
  eventos de conectividad tienen debounce. Ver `RELEASES.md` 0.9.0.
- [x] `medio` 2026-09-03 — **"Descargar este capítulo" no sabe por dónde vas
  leyendo.** `downloadChapters(from, count)`
  (`reader_provider.dart:1180`) sintetiza el capítulo completo desde su
  párrafo 0; "Descargar → Este capítulo"
  (`_DownloadScope.chapter`, `reader_screen.dart:361`) le pasa
  `from = reader.chapterIndex` sin ningún desplazamiento. Si alguien lee en
  silencio hasta la mitad de un capítulo y ahí decide pasar a escuchar,
  descarga de nuevo lo que ya leyó. Arreglar significa que `downloadChapters`
  acepte un párrafo inicial opcional, y que el botón de "este capítulo" lo
  use con `reader.paragraphIndex` en vez de 0 -- las otras dos opciones
  ("los próximos capítulos", "el resto del libro") siguen empezando en 0,
  porque ahí no hay "por dónde vas" dentro del capítulo siguiente.

  Hecho en 0.9.0, con una diferencia: en vez de cambiar "Este capítulo" se
  agregó "Desde aquí hasta el final del capítulo" al lado, porque quien leyó en
  silencio a veces sí quiere el capítulo entero para escucharlo desde el
  principio. La opción nueva solo aparece si hay algo que saltarse.

---

## Experiencia de lectura

La app nació para escuchar, y se nota: casi todo lo de aquí existe ya en
cualquier lector de la competencia. Leer en silencio es hoy el flujo peor
atendido.

- [x] `alto` 2026-09-03 — **El diccionario en inglés casi nunca respondía.**
  El fallo no era de red: `api.dictionaryapi.dev` tardaba ~19,5 s en seis de
  cada seis consultas y una devolvió 522, mientras la app le concedía 8 s. En
  pantalla salía la excepción de Dart en crudo.

  Resuelto yendo a la fuente: el inglés pasa a Wikcionario, el mismo endpoint de
  extractos que ya usaba el español, pidiendo `exsectionformat=wiki` para que
  las marcas `== English ==` y `=== Noun ===` digan qué sección es un idioma y
  cuál una categoría, sin adivinarlo. Diez palabras medidas de nuevo: entre 201
  y 380 ms, ninguna falla, e incluso `waterbag`, que dictionaryapi.dev no tenía.

  De paso, los tres agravantes: los fallos transitorios ya no se cachean (una
  palabra que falla deja de fallar para siempre), la lectura del cuerpo tiene
  plazo, y el mensaje de error dejó de ser el objeto de Dart.

- [x] `alto` 2026-09-02 — **Ajustar el tamaño del texto sin salir del libro.**
  Los controles existen —tamaño 12-32, interlineado, márgenes, tipografía y
  fondo— pero viven en la pantalla global de Ajustes
  (`settings_screen.dart:398-450`), entre el motor TTS y la caché: el botón de
  la barra del lector hace `context.push('/settings')`
  (`reader_screen.dart:304`). Ajustar la letra obliga a abandonar la lectura,
  volver, y repetir hasta acertar. Hace falta una hoja inferior en el propio
  lector con esos mismos ajustes, viendo el texto cambiar detrás. Y un
  pellizco para el tamaño: hoy no hay ningún gesto de escala en `lib/`, solo
  `onTap` y `onLongPressStart`.
- [ ] `alto` 2026-09-03 — **Paginar en vez de desplazar.** Kindle y Play Books
  pasan página; esta app tiene scroll continuo por capítulo
  (`reader_screen.dart:249-286`, un `ScrollablePositionedList`), que es lo
  normal en una app web y raro en un lector. Pasar página da tres cosas de
  golpe: saber cuánto falta para acabar el capítulo de un vistazo, una unidad
  de lectura estable a la que volver, y que el pulgar no arrastre de más al
  reposicionar. No es un cambio de widget sino de modelo: hay que medir el
  texto contra el alto disponible con el tamaño y el interlineado actuales, y
  rehacerlo al cambiarlos. Es la diferencia estructural más grande frente a la
  competencia, y por eso encabeza la lista.
- [ ] `medio` 2026-09-03 — **Decir cuánto falta en tiempo, no en porcentaje.**
  «Te quedan 14 minutos en este capítulo» es la cifra que Kindle acertó a
  poner y que la gente usa para decidir si sigue. La app ya tiene la mitad
  hecha: estima el tiempo de escucha restante (`reader_screen.dart:876-894`, a
  14 caracteres por segundo). Falta la estimación de **lectura** en silencio,
  que necesita medir la velocidad real de cada persona en vez de suponerla, y
  mostrarla por capítulo además de por libro.
- [ ] `medio` 2026-09-03 — **Brillo y temperatura desde el propio lector.** Un
  gesto vertical en el borde izquierdo, como Kindle. Hoy no hay ningún control
  de brillo (`reader_screen.dart` solo consulta `platformBrightnessOf` para
  elegir paleta), así que leer de noche obliga a salir a los ajustes del
  sistema. El modo cálido —bajar el azul al anochecer— es lo que más se agradece
  y no existe en ninguna de las tres paletas actuales.
- [ ] `bajo` 2026-09-03 — **Volver atrás después de un salto.** Al tocar una nota
  al pie, una entrada del índice o un marcador, Kindle deja un botón para
  regresar exactamente a donde estabas. Aquí un salto es definitivo: hay que
  recordar el capítulo y buscarlo a mano. Basta con una pila de una posición y
  un botón flotante que aparezca solo después de saltar.
- [ ] `bajo` 2026-09-03 — **Recordar la posición entre dispositivos.** Es lo que
  hace que Kindle se sienta un servicio y no una app. Hoy todo es SQLite local
  (`database.dart:11`) y no hay sincronización de ninguna clase. Con el proxy ya
  montado y un token por persona, el esqueleto existe; lo que falta es decidir
  si esto quiere ser un servicio, con lo que eso arrastra.
- [ ] `bajo` 2026-09-03 — **Cerrar el ciclo del diccionario.** Play Books guarda
  las palabras que consultas y las convierte en una lista para repasar. La app
  ya resuelve la definición (`services/dictionary.dart`) y la tira; guardarla
  costaría una tabla. Tiene sentido sobre todo leyendo en inglés, que es cuando
  se consulta de verdad.

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
- [ ] `medio` 2026-09-03 — **La app solo habla español.** Toda la interfaz está
  en castellano y escrita a mano en los widgets: no hay `flutter_localizations`,
  ni ficheros ARB, ni `AppLocalizations`. Cambiar de idioma hoy significa editar
  el código.

  **Lo que hay que investigar antes de decidir**, porque el coste está repartido
  y no todo es traducir:

  - **La interfaz**: unas cuantas docenas de cadenas sueltas por las pantallas.
    Es el trabajo mecánico y el más barato; `flutter_localizations` con ARB es
    el camino estándar.
  - **Los mensajes de error, que son la mitad del valor.** `_friendlyError`
    (`reader_provider.dart`), los cuatro estados del sondeo y los del
    diccionario están redactados para explicar, no solo para nombrar. Traducir
    eso conservando el tono cuesta más que traducir botones.
  - **El diccionario ya es bilingüe** y no cambia: elige fuente según el idioma
    del *libro*, que es independiente del idioma de la app.
  - **Las voces por defecto** (`voiceMap`) están fijadas a español y a inglés.
    Un tercer idioma de interfaz no implica un tercer idioma de lectura, pero
    conviene decidir si se atan o no.
  - **El parser del Wikcionario español** (`parseSpanishExtract`) reconoce
    categorías gramaticales por nombre en castellano. Solo importa si algún día
    se lee en un idioma más.
  - **Lo que NO hay que traducir**: los comentarios del código y esta
    documentación. Son para quien mantiene, y cambiarlos no aporta.

  Lo razonable es empezar por **inglés**, que es el otro idioma que la app ya
  lee, y ver cuánto duele antes de prometer más. Y hacerlo **antes** de que la
  interfaz crezca: cada pantalla nueva escrita a mano es deuda que se paga
  después.

- [ ] `bajo` 2026-09-02 — **Más formatos: PDF, MOBI y compañía.** Hoy solo
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

  Bajado a `bajo` el 2026-09-03 a petición explícita: no corre prisa, queda
  anotado para no perderlo de vista. Si algún día entra, el orden sensato es
  TXT primero —que valida la interfaz común con casi ningún esfuerzo— y PDF el
  último, o nunca.
- [ ] `medio` 2026-09-02 — **Buscar dentro del libro.** No existe. La única
  búsqueda es por título y autor en la biblioteca
  (`library_screen.dart:59-82`). Con el libro ya troceado en párrafos y
  oraciones en memoria, buscar y saltar al resultado es barato.
- [x] `medio` 2026-09-02 — **La barra de progreso no se puede arrastrar.** Es un
  `LinearProgressIndicator` (`reader_screen.dart:740-744`), un indicador y no un
  control: para moverte por el libro solo queda el índice de capítulos o ir
  párrafo a párrafo. Falta arrastrar, o un "ir al %".
- [ ] `medio` 2026-09-02 — **El texto pierde el formato del libro.** El parser
  aplana a texto plano: se descartan imágenes, tablas y notas al pie, y el CSS
  del EPUB se ignora entero (`parser.dart:131-186`), así que cursivas, negritas
  y versos desaparecen. Para escuchar da igual; leyendo, un libro con énfasis o
  ilustraciones se lee peor que en cualquier otro lector.
- [x] `bajo` 2026-09-02 — **La pantalla se apaga leyendo en silencio.** El
  `WAKE_LOCK` del manifest (`AndroidManifest.xml:13`) mantiene viva la CPU para
  el audio, no la pantalla, y no hay ningún control de brillo ni bloqueo de
  orientación. Leer sin tocar la pantalla acaba a oscuras.
- [x] `bajo` 2026-09-02 — **Abrir un marcador arranca el audio.**
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

- [ ] `medio` 2026-09-03 — **Probar la cola de reportes sin servidor.** Es la
  pieza que justifica que exista la cola y la única de la fase 5 que no se ha
  verificado en el teléfono. Lo demás sí quedó comprobado el 2026-09-03 con la
  build 60: permiso pedido solo al pulsar grabar, nota de voz de 81 kB entregada
  como M4A válido, y el reporte escrito llegando con libro, capítulo, párrafo,
  motor y las dos últimas líneas de diagnóstico.

  Falta el caso que importa: generar un fallo con el proxy parado, comprobar que
  el reporte se queda en la tabla `reports`, levantar el proxy y ver que sale
  solo sin tocar nada. Hay tests unitarios que cubren el encolado y el tope,
  pero no el ciclo completo contra el servidor real.

- [ ] `bajo` 2026-09-03 — **Confirmar los plazos con Funnel, no solo con la
  tailnet.** Medido ya por la malla y con relevo DERP: un sondeo completo tarda
  ~0,84 s desde el teléfono, así que el presupuesto de 5 s va seis veces
  sobrado y el reintento no llegó a hacer falta ni una vez en quince síntesis.
  Falta repetirlo por Funnel, que mete TLS y un salto más.
- [x] `medio` 2026-09-02 — **El health check de 3 s es demasiado estricto.**
  `kokoro_tts_provider.dart:94-98` y `piper_tts_provider.dart:54-58` dan tres
  segundos al saludo y cachean el resultado 30 s. La síntesis va holgada (180 s
  y 120 s), así que el cuello de botella es el saludo, no el trabajo. Una red
  móvil lenta o un servidor recién despertado agotan ese plazo y la app **se
  repliega a Edge en silencio**, indistinguible de un servidor caído. Un
  reintento o un plazo mayor. Es el único de esta sección que vale la pena
  aunque nunca se salga de Tailscale.
- [x] `bajo` 2026-09-02 — **Un token que los providers mandan como cabecera**
  en la síntesis, el sondeo y el listado de voces. Resuelto de otra forma que la
  prevista: no hay campo en Ajustes, porque el token no lo escribe el usuario
  sino que va compilado por probador (`TtsServerConfig`), y quien lo valida es
  el proxy de `tools/proxy`, ya que ni Kokoro ni Piper saben hacerlo.
- [ ] `bajo` 2026-09-05 — **Repensar Tailscale (y trackear las URLs en git) si
  el repo deja de ser privado.** `KOKORO_URL` y `CHATTERBOX_URL` van
  comiteadas (`tools/release/kokoro.json`, `tools/release/chatterbox.json`)
  porque hoy el repo no se comparte con nadie; `TTS_TOKEN` justamente por eso
  se quedó fuera de git y viaja por USB entre las dos PCs propias (ver
  `tools/release/README.md`, "Configurar una segunda PC propia"). Si el repo
  se abriera algún día, o el proyecto escalara más allá de hobby, tocaría
  reconsiderar ambas cosas por algo con autenticación real (Cloudflare
  Access, ver `docs/context/ACCESO_REMOTO.md`). Poco probable: es un proyecto
  de hobby, no algo pensado para monetizar.

---

## Calidad de código

- [x] `medio` 2026-09-03 — **Elegir una voz con Piper la guarda en Edge.** El
  `onPick` de la hoja de voces solo distingue `kokoro` de todo lo demás
  (`settings_screen.dart:302-304` y `:313-315`), así que con Piper seleccionado
  la voz elegida se escribe en `edgeVoiceEs`/`edgeVoiceEn`. `piperVoiceEs` y
  `piperVoiceEn` no se escriben desde ningún punto de la interfaz: para cambiar
  la voz de Piper hay que editar el compose y reconstruir. Solo afecta a la
  compilación propia, porque Piper no va al reparto.
- [x] `bajo` 2026-09-03 — **`voicesProvider` pide el catálogo de más.** Es un
  `FutureProvider.family<List<Voice>, AppSettings>` (`voices_provider.dart:13`)
  y `AppSettings` no implementa `==`, así que la clave es la identidad del
  objeto: cada cambio de ajuste crea una entrada nueva y una petición nueva. Y
  no es `autoDispose`, así que las viejas se retienen. Quitar el campo de
  dirección en 0.7.0 mató el síntoma peor -una petición por pulsación de tecla-
  pero no la causa. El arreglo es una clave de valor pequeña
  (`engine`, `baseUrl`, `token`) con `==` propio, más `.autoDispose`;
  implementar `==` en `AppSettings` entero no sirve, porque cambiar el tamaño de
  letra volvería a invalidar el catálogo.
- [ ] `bajo` 2026-09-03 — **Kokoro y Piper no cachean su catálogo de voces.**
  Edge guarda el suyo siete días en SharedPreferences
  (`edge_tts_provider.dart:376-403`); los otros dos preguntan al servidor cada
  vez que se abre Ajustes, y por el túnel eso es un viaje de ida y vuelta que no
  hace falta.


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
- [ ] `medio` 2026-09-06 — **El proyecto está justo en el suelo de versiones que
  Flutter todavía acepta: Gradle, AGP y Kotlin.** La build de 0.9.1 imprime tres
  avisos de "will soon be dropped". No es cosmético: el validador de Flutter
  (`DependencyVersionChecker.kt` en el SDK) tiene dos umbrales por dependencia, y
  el de abajo **tira `DependencyValidationException` y aborta la compilación**.
  Las tres versiones del proyecto coinciden **exactamente** con ese umbral de
  error, no están por encima:

  | Dependencia | Aquí | Falla si es menor que | Avisa si es menor que | Plantilla de Flutter |
  |---|---|---|---|---|
  | AGP | 8.11.1 (`android/settings.gradle.kts:24`) | 8.11.1 | 9.0.1 | 9.1.0 |
  | Kotlin | 2.2.20 (`android/settings.gradle.kts:25`) | 2.2.20 | 2.3.20 | 2.4.0 |
  | Gradle | 8.14 (`gradle-wrapper.properties`) | 8.14.0 | 9.1.0 | — |
  | Java | 17 | 17 | 17 | — |

  Con Flutter 3.47.2 eso se traduce en avisos. El día que una stable suba el
  suelo —y la plantilla de proyecto nuevo ya va en AGP 9.1.0 y Kotlin 2.4.0, dos
  majors por delante— el mismo `flutter build apk` que hoy funciona deja de
  compilar. El disparador es `flutter upgrade`, así que el momento lo elegimos
  nosotros; el riesgo real es descubrirlo con un APK que hay que mandar a un
  tester esa misma tarde.

  `--android-skip-build-dependency-validation` (lo sugiere el propio aviso)
  desactiva la comprobación, no el problema: salta el guardia y deja que AGP y
  Gradle fallen por su cuenta, más abajo y peor explicado. Sirve para
  desbloquear una release urgente, no como estado permanente.

  Lo que hay que mirar antes de subir, que es donde está el coste de verdad: los
  plugins traen su propio `compileSdk` congelado y tres van claramente atrasados
  — `audio_session` 0.1.25 y `just_audio` 0.9.46 en `compileSdk 34` (AGP 8.1.0 y
  8.5.0 en su `buildscript`), `file_picker` 8.3.7 en 34 con AGP 7.4.2, y
  `audio_service` 0.18.19 en 35. Son los mismos que el ítem de **Dependencias**
  de arriba ya marca como "requieren probar la reproducción en el teléfono":
  conviene hacer las dos cosas en la misma sesión de pruebas en vez de tocar el
  audio dos veces. Los demás (`flutter_tts`, `record_android`, `wakelock_plus`,
  `connectivity_plus`) ya están en Kotlin 2.2.x y AGP 8.12+.

  Orden sensato: Gradle primero (solo el wrapper, no toca código), después AGP y
  Kotlin juntos, y compilar release + instalar en el teléfono en cada paso. Java
  17 ya cumple el mínimo y no hay que tocarlo.
- [ ] `bajo` 2026-08-30 — **`main` va por detrás y no hay tags.** `develop`
  acumula toda la historia desde 0.1.0 y `main` sigue en el commit inicial.
  `docs/RELEASES.md` documenta el procedimiento de tag y no se ha aplicado
  nunca.
