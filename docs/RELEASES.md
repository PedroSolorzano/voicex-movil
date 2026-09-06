# VoiceX Movil — Release History

Esquema de versiones: `MAJOR.MINOR.PATCH-PHASE.N+BUILD`
- `MAJOR` 0 = pre-release, 1 = estable publico
- `MINOR` features nuevas
- `PATCH` bug fixes
- `PHASE` preview → beta → rc → (omitido en estable)
- `BUILD` Android versionCode, siempre incrementa

---

## 0.7.2-preview.1 — 2026-09-05

Dos correcciones que salen del mismo incidente, investigado cruzando el
diagnóstico del teléfono contra el log del contenedor de Chatterbox.

### Un servidor ocupado no es un servidor caído

Reportado como "está fallando las descargas a Chatterbox" leyendo La Odisea.
El log del servidor descarta la hipótesis que había quedado escrita en
`docs/bugs/CHATTERBOX_DESCARGAS.md` —la laptop reconectándose en la tailnet—:
el contenedor nunca se reinició (`RestartCount: 0`, uptime continuo). Lo que
pasó es que Chatterbox tiene **un solo worker**, y mientras la GPU genera
audio no puede contestar ninguna otra petición, ni siquiera su propio
endpoint de salud. Un párrafo cuyo chunk 2 de 11 tardó 70 s dejó los cuatro
health-checks siguientes cayendo exactamente dentro de esa ventana.

Peor: el trabajo entero superó los 240 s del cliente, así que la app abandonó
ese párrafo mientras el servidor lo seguía cocinando —nada le avisa que la
conexión se cortó—, y eso tumbó en cascada los sondeos de los párrafos
siguientes de la misma descarga, cada uno quemando 13 s en fallar por la
misma razón.

Ahora, al agotarse el presupuesto de síntesis, la app asume que el servidor
sigue ocupado un rato (`TtsTimeouts.busyCooldown`) y deja de sondearlo: le da
aire para terminar en vez de tocarle la puerta cada 13 s, y el resto de la
descarga cae a Edge de inmediato en vez de arrastrar un timeout por párrafo.

### El techo de espera se calibra con la máquina que toca

Los 240 s por defecto salen de medir ~55-75 s por párrafo. En una GPU justa
un párrafo tarda varias veces eso, y rendirse antes de tiempo produce el peor
desperdicio posible: **el servidor termina el audio y el cliente ya lo tiró a
la basura**. En el incidente medido, una generación de 4 m 37 s se perdió por
abandonarla a los 4 m.

Durante una descarga el presupuesto pasa a ser cinco veces el promedio real
de esa máquina (`TtsTimeouts.adaptiveSynthesis`), medido solo sobre párrafos
de Chatterbox exitosos —los tiempos de Edge son un orden de magnitud menores
y dejarían el techo corto justo cuando el servidor propio vuelve—. El suelo
son los 240 s de siempre, así que esto solo puede volver la app más paciente;
el tope son 20 minutos.

La lectura en vivo conserva el presupuesto fijo a propósito: esperar minutos
por un párrafo mientras alguien escucha no sirve de nada, ahí el repliegue
rápido a Edge es lo correcto. Es la primera vez que descarga y reproducción
tienen presupuestos distintos, y el motivo es ese: la paciencia útil no es la
misma cuando dejás el capítulo bajando que cuando estás escuchando.

---

## 0.7.1-preview.1 — 2026-09-05

Un tester bajó un capítulo entero con Chatterbox, lo escuchó, y al día
siguiente la app lo daba por perdido y volvía a Edge. Reproducirlo en su
teléfono en vivo (`adb`, con la laptop de Chatterbox apagada y prendida a
propósito) descartó las dos hipótesis obvias — pantalla que se apaga durante
la descarga, servidor caído en el momento de escuchar — y encontró la real: la
descarga sobrevivía perfecta hasta el primer reinicio de la app.

### Un reinicio bastaba para perder cualquier descarga de Chatterbox

`migrateCacheKeys()` (`lib/storage/repositories.dart:331`) corre en cada
arranque (`main.dart:30`) y tiene una regla de cierre: toda clave de caché sin
prefijo de motor conocido "es de antes del split y viene de Edge". Se escribió
antes de que Chatterbox existiera y nadie la actualizó cuando se sumó — la
condición no la excluía.

Resultado: cada arranque le anteponía `edge-` a `chatterbox-voz_propia`,
convirtiéndola en `edge-chatterbox-voz_propia`. La reproducción sigue
calculando `chatterbox-voz_propia` para buscar el audio; esa clave mutada no
la vuelve a encontrar nunca. El archivo seguía intacto en
`getApplicationDocumentsDirectory()` — no era un caché que la app hubiera
limpiado, era un huérfano invisible — y en Ajustes → Almacenamiento el párrafo
pasaba a contarse como Edge, porque el motor de esa pantalla se lee del
prefijo de la clave.

La regla ahora excluye `chatterbox-%` (y `android-%`, ya cubierto antes por
`_dropRetiredEngineRows` pero mejor explícito). Se agrega además una
reparación de una sola vez que revierte cualquier fila que ya haya quedado
mal etiquetada por una versión anterior, para no forzar una resíntesis de
horas por un bug que ya no está.

### Dos huecos de visibilidad que salieron a la luz reproduciendo el bug

Una descarga cuyo servidor se cae a mitad de camino termina en Edge sin decir
nada en pantalla — solo se nota después, contando párrafos en Ajustes. Ahora
la barra de descarga (`lib/ui/screens/reader_screen.dart`) suma un aviso del
tipo "con Edge (Chatterbox no disponible)" en cuanto el motor real difiere del
elegido.

Y el rótulo de motor de la pantalla de lectura solo se actualizaba dentro de
`_provider()`, que solo corre cuando hay que sintetizar algo nuevo
(`reader_provider.dart:635`). Un párrafo servido desde caché nunca pasaba por
ahí, así que "Edge (Chatterbox no disponible)" podía quedar pegado en pantalla
mucho después de que el servidor volviera. Un acierto de caché bajo el motor
elegido ahora refresca el rótulo también.

---

## 0.7.0-preview.1 — 2026-09-03

La versión que prepara la app para dársela a otras personas. Casi todo lo de
aquí sale de esa frase: si alguien más va a usarla, el servidor no puede estar
abierto, los fallos tienen que llegar solos, y lo que se rompe tiene que decir
qué se rompió.

### Kokoro y Piper dejan de estar abiertos a quien pase por la WiFi

Ninguno de los dos sabe autenticar: la "API key" de Kokoro-FastAPI es la cadena
literal `not-needed`, que existe solo porque el cliente de OpenAI obliga a
mandar algo. Estaban publicados en `0.0.0.0`, alcanzables por cualquiera en la
red de casa.

Ahora escuchan **solo en loopback** y el único camino es un proxy nginx que
valida un token por persona. La parte que hace que eso no sea decorativo es
precisamente cerrar los puertos: un proxy con cerradura al lado de una ventana
abierta no sirve de nada. Cuesta el acceso directo por WiFi, que era el único
camino hasta ahora; a cambio queda uno solo que probar.

Seis rutas exactas y ninguna más. Kokoro-FastAPI publica además `/docs`,
`/redoc` y `/v1/models`, superficie que no tiene por qué existir de cara a
internet.

### La dirección del servidor sale de la interfaz

Un campo de texto libre era razonable cuando el único usuario escribía una IP de
su propia red. Deja de serlo en cuanto la app se le pasa a alguien más: se rompe
con un dedo, sale en cualquier captura, y se pega en un grupo de mensajes sin
querer. Ahora va compilada en el APK, un fichero por persona.

Conviene decir qué es esto y qué no. **No es un control de seguridad**: sobre
este mismo APK, `strings` encuentra el token dos veces y la dirección entera. Lo
que protege la máquina de casa está en el proxy —revocación individual, límite
de ritmo, lista blanca, backends en loopback— y no en esconder una cadena.

### Un sondeo que distingue un servidor caído de una clave rechazada

El sondeo estaba calibrado para una LAN: tres segundos, un intento, y cualquier
fallo colapsado en un booleano cuyo motivo solo llegaba al log. Por un túnel eso
se traduce en repliegues a Edge con el servidor perfectamente encendido.

Ahora hay cuatro estados. El nuevo es el que más falta hacía: **clave rechazada**
no es la computadora apagada, y la acción correcta no es esperar sino pedir una
compilación nueva.

El reintento es asimétrico a propósito. Un timeout es el caso ambiguo —puede ser
la red— y se reintenta con más margen; una conexión rechazada no, porque el
servidor no está y esperar ocho segundos más no lo va a traer. Y el TTL deja de
ser simétrico: cachear treinta segundos un éxito ahorra un sondeo por párrafo,
pero cachear los fallos significaba que un bache de red congelaba el repliegue
medio minuto y arrastraba los párrafos siguientes.

Medido después por la malla: un sondeo completo tarda ~0,84 s, así que el
presupuesto de 5 s va seis veces sobrado y el reintento no hizo falta ni una vez
en quince síntesis.

### Reportes que sobreviven a no tener servidor

Los fallos que más interesan ocurren justo cuando el servidor no está accesible,
que es exactamente cuando un reporte no se puede enviar. Así que no se envían: se
encolan en el teléfono y salen cuando el servidor vuelve.

Y como el envío es automático, el saneo es la pieza que sostiene todo: una
excepción de síntesis puede llegar con el párrafo que se estaba mandando dentro
del mensaje, y eso es la lectura personal de alguien. Viaja el tipo de la
excepción, la ruta y el estado; nunca el mensaje crudo.

Los probadores pueden contar un problema escrito o **grabando una nota de voz**,
que para alguien no técnico es mucho más cómodo que escribir un párrafo en el
teléfono. El permiso de micrófono se pide al pulsar grabar, nunca al arrancar.

### El diccionario en inglés no fallaba por la red

Reportado como "suele decir error de conexión", y reproducible fuera de la app:
seis consultas a `api.dictionaryapi.dev` dieron dos respuestas rápidas, tres de
más de diecinueve segundos y un 522. Con ocho segundos de plazo, expirar era el
caso normal.

Ahora va a Wikcionario, el mismo endpoint que ya usaba el español. Diez palabras
medidas de nuevo: entre 201 y 380 ms, ninguna falla, e incluso `waterbag`, que
dictionaryapi.dev no tenía. Era un intermediario lento delante de estos mismos
datos.

### Vuelve el motor del teléfono

Se retiró en 0.6.0 con argumentos que siguen siendo ciertos: no marca palabras y
escribe WAV. Dos cosas cambiaron. La valoración de la voz —la retirada juzgaba la
genérica de Google, y un Samsung trae las suyas, bastante mejores; hasta ahora no
había forma de elegirlas porque el proveedor solo fijaba el idioma—. Y sobre todo
que la app se va a repartir a gente sin servidor propio: para ellos es **el único
motor que sigue leyendo en el metro**.

### El motor del teléfono no generaba audio en Android 11 o superior

Dos testers lo reportaron el mismo día que se reintrodujo: "Teléfono" fallaba
siempre con *"El motor de voz del teléfono no generó audio"*, en un Samsung
Galaxy S21 Ultra (Android 12). El motor sí sintetizaba -el log de Android lo
confirmaba- pero `synthesizeToFile()` (`lib/tts/android_tts_provider.dart:77`)
no mandaba el parámetro `isFullPath`, que el plugin `flutter_tts` da por
`false`. Desde Android 11, con `isFullPath` en `false` el plugin ignora la
ruta que le pasamos y escribe el audio a través de `MediaStore`, en una URI
propia dentro de `Music/`. La app entonces comprobaba si el archivo existía en
la ruta que había pedido, no lo encontraba ahí -estaba en otro lado- y
reportaba que el motor no había generado nada, cuando sí lo había hecho.

Pasar `isFullPath: true` alcanza: el resto del código ya construye una ruta
absoluta. Verificado en el mismo teléfono que lo reportó.

### Descargar un capítulo con un motor podía romper el de otro

Reportado como "cambio de motor y no me deja, hay un proceso corriendo".
`ReaderNotifier` guardaba el motor de voz activo en un solo campo compartido
(`_ttsProvider`), y tanto la descarga (`downloadChapters`) como la
reproducción en vivo (`play`) pasaban por él. Cambiar de motor mientras una
descarga corría destruía la instancia que la descarga estaba usando a mitad
de una síntesis (`_provider`, línea 594: `unawaited(old.dispose())`) -y como
la descarga fijaba los ajustes una sola vez al arrancar, en la siguiente
vuelta del bucle volvía a pedir el motor viejo y destruía a su vez lo que la
reproducción acababa de crear. Las dos se turnaban la manguera.

Ahora la descarga tiene su propia instancia, nunca la de la reproducción en
vivo: cambiar de motor en Ajustes mientras algo se descarga ya no interrumpe
ni una cosa ni la otra. La descarga sigue terminando con el motor que tenía
al arrancar -salvo que el servidor se caiga a mitad, que ahí sí se repliega a
Edge como antes-, y solo un cambio de motor deliberado en Ajustes afecta a
partir de ese momento a la reproducción en vivo.

### Lectura

- El **tamaño de letra se ajusta sin salir del libro**. Los controles existían
  desde 0.3.0 pero vivían en la pantalla global de Ajustes, entre el motor de voz
  y la caché: había que abandonar la lectura, mover un deslizador a ciegas y
  volver a ver cómo quedó. Ahora es una hoja a media pantalla con el texto
  visible detrás.
- La **barra de progreso se arrastra**. Era un indicador; para moverse por el
  libro solo quedaba el índice o ir párrafo a párrafo.
- **La pantalla ya no se apaga leyendo en silencio.** El `WAKE_LOCK` que había
  mantiene viva la CPU para el audio, que es lo contrario de lo que hace falta
  al leer sin escuchar.
- **Abrir un marcador ya no arranca el TTS.**

### Debajo del capó

- **Kokoro pasa a AAC**: 94 kbps frente a los 130 del MP3, un 28 % menos por la
  red y sin perder calidad. Opus, el candidato obvio, salía *peor* (140 kbps) y
  además viaja en Ogg, que no se concatena por tramas. El tag de formato de la
  caché **no se toca**: bumpearlo habría huerfanizado todas las descargas ya
  hechas para retirar ficheros que se siguen reproduciendo bien.
- **Un libro en inglés y otro en español dejan de compartir audio.** Kokoro usa
  `af_bella` para los dos idiomas y el idioma nunca entraba en la clave. Migrado
  leyendo `books.language`, para no huerfanizar nada.
- **Los cuerpos de respuesta tienen plazo.** Una conexión que se degradaba tras
  las cabeceras colgaba indefinidamente, sin llegar siquiera a producir un error.
- **El prefetch deja de preguntar "¿es WiFi?" y pregunta "¿me cobran por esto?".**
  Android deja que una VPN se adueñe del transporte reportado, así que instalar
  Tailscale habría apagado la descarga adelantada estando en el WiFi de casa.
- Elegir una voz con Piper la guardaba en los ajustes de Edge, y `piperVoiceEs`
  no se escribía desde ninguna parte de la interfaz.
- `voicesProvider` pedía el catálogo entero con cada cambio de cualquier ajuste.
- De 86 tests a 131.

### Chatterbox se suma como motor, y compilarlo hizo desaparecer a Kokoro sin avisar

Cuarto motor TTS, pensado solo para español: clona una voz con GPU en una
laptop personal que entra a la tailnet como nodo aparte, sin proxy ni token
porque no se reparte a probadores (`lib/tts/chatterbox_tts_provider.dart`).
Reutiliza el mismo patrón de Kokoro y Piper — motor + voz + ritmo en la clave
de caché, repliegue silencioso a Edge si la laptop está apagada.

Compilar el primer APK con esto reveló un bug de proceso: `TtsServerConfig
.availableEngines` (`lib/config/server_config.dart:63-69`) decide qué motores
ofrecer solo por la variable que llegó no vacía **al compilar**, nunca contra
el estado real del servidor. Ese build se armó con `CHATTERBOX_URL` suelto en
vez de combinarlo con el `.json` que ya traía `KOKORO_URL`/`PIPER_URL`, y el
resultado fue un APK que solo ofrecía Edge, Chatterbox y Teléfono en Ajustes
→ Motor de voz — con Kokoro corriendo sano de fondo todo el tiempo, sin que
nada lo dijera.

`KOKORO_URL` pasa ahora a `tools/release/kokoro.json`, trackeado en git igual
que `chatterbox.json`: es la misma dirección para cualquier compilación
propia (laptop o desktop), así que no había motivo para que viviera solo en
el `.json` gitignorado de una máquina. Lo único que sigue sin compartirse es
el token, que se queda en el `.json` personal de cada quien
(`tools/release/README.md`).

---

## 0.6.0-preview.1 — 2026-09-02

### Fuera el TTS del teléfono

Estuvo desde 0.1.0, cuando era el único motor que no pedía nada a nadie. Con
Edge, Kokoro y Piper delante ya no ganaba en nada: no marca palabras, así que el
resaltado bajaba a oración estimada; suena a robot al lado de una voz neuronal;
y escribía WAV, que ocupa varias veces lo que el MP3 de los otros tres en la
misma caché de 150 MB. Lo que justificaba tenerlo —escuchar sin conexión— hoy lo
resuelve mejor la descarga por adelantado, que además suena bien.

Se va el proveedor, el chip de Ajustes y la dependencia `flutter_tts`.

**Un móvil que lo tuviera seleccionado no se queda a medias.** El nombre del
motor vive en SharedPreferences: al arrancar seguiría diciendo `android`. La
fábrica devolvía Edge en silencio, pero la clave de caché y la barra de estado
del lector habrían seguido nombrando un motor inexistente, y el sondeo del
servidor propio se habría lanzado a buscar una máquina que no toca. Ahora
`AppSettings.load()` devuelve a Edge cualquier motor que la app ya no tenga.

Su audio también se va: el mantenimiento del arranque borra las filas y los
archivos de los dos nombres que la clave tuvo (`android:` antes de 0.5.0,
`android-` después). Se hace **antes** de renombrar nada, porque la regla
catch-all del final etiqueta como `edge-` todo lo que no reconoce, y habría
convertido ese WAV en audio de Edge que ningún párrafo va a pedir jamás.

### Oír una palabra suelta no hacía nada con Kokoro o Piper

Misma causa que el repliegue roto de 0.5.2, en la función de al lado: la
pulsación larga sobre una palabra pedía la voz **seleccionada** en vez de la del
motor que iba a sintetizar. Con el servidor caído, eso mandaba `af_bella` a
Edge, que devolvía nada, y el `catch` de alrededor se tragaba el error. Sin
sonido, sin aviso, sin nada.

### Debajo del capó

- El mensaje de "sin conexión" ya no sugiere cambiar a un motor que no existe;
  ahora manda a descargar los capítulos por adelantado.
- `settings_engine_test.dart` fija que un motor retirado vuelve a Edge y que uno
  válido sobrevive con sus ajustes. 86 tests.
- Los comentarios que describían el motor local —el reparto estimado de
  oraciones, la extensión WAV, el catálogo de voces— nombran ahora a Piper, que
  es quien hereda esos casos.

---

## 0.5.2-preview.1 — 2026-08-30

Cuatro fallos en el camino de la caché y las descargas, encontrados revisando
el código y no usando la app: ninguno daba la cara hasta que ya había hecho
daño.

### Las descargas se borraban solas a los cinco días

La limpieza que corre en cada arranque retiraba todo lo que llevara cinco días
sin tocarse, **sin distinguir las descargas**. Descargar un libro con Kokoro
—dos horas de síntesis—, no abrirlo en una semana, y encontrarlo vacío sin que
nada lo avisara.

Es el mismo fallo que 0.5.0 arregló en el botón "Limpiar caché", en otra
función que se saltó la regla. Ahora la regla está escrita y probada: una
descarga solo la borra quien la pidió.

### El repliegue a Edge pedía una voz que Edge no tiene

Con Kokoro o Piper seleccionado y el servidor apagado, la app cambiaba de motor
pero seguía mandando la voz del motor caído: `af_bella` o
`es_AR-daniela-high`, nombres que no existen en el catálogo de Microsoft. La
petición volvía sin audio, así que el repliegue automático —lo que hace usable
un servidor doméstico— no funcionaba justo cuando hacía falta.

La función que resuelve la voz por motor ya existía, y su comentario explicaba
este caso exacto. La llamada de síntesis usaba el atajo equivocado.

De paso, una descarga que empieza con el servidor en pie y lo pierde a mitad ya
no archiva el audio de Edge bajo el nombre de Kokoro: cada párrafo re-deriva su
clave.

### Un párrafo descargado se volvía a sintetizar

Reproducir un párrafo y descargarlo después dejaba dos filas para el mismo
párrafo: la copia temporal y la descarga. La búsqueda tomaba la primera —la
temporal, más antigua— y cuando el sistema limpiaba el directorio temporal la
daba por perdida y se rendía, **sin mirar la descarga que estaba justo detrás**.
Sin servidor alcanzable, eso era volver a sintetizar con Edge.

Es exactamente el síntoma que se creía cerrado en 0.5.0. Aquel arreglo atacó
otra causa —la clave con `:` y `@`— y esta quedó viva.

Ahora la búsqueda prioriza las descargas y recorre todos los candidatos antes
de rendirse; guardar retira la copia que sustituye, así que no vuelven a
acumularse; y el mantenimiento del arranque limpia los duplicados que ya
existan, quedándose siempre con la descarga.

### El aviso del ritmo de Piper saltaba siempre

"Con este ritmo no se usarán los N párrafos ya descargados" aparecía a cada
roce del deslizador, incluso al volver al valor con el que se descargó. Buscaba
el ritmo al principio de la clave cuando va al final, y además los guiones
bajos de la clave se interpretaban como comodines.

### Debajo del capó

- `sqflite_common_ffi` en las dependencias de desarrollo: los repositorios se
  prueban ahora contra SQLite de verdad. De 53 tests a 80.
- Las consultas nuevas evitan funciones de ventana: Android 7, el mínimo que
  soporta la app, trae SQLite 3.9 y `ROW_NUMBER()` necesita la 3.25.
- `TECHNICAL.md` describía una app de dos motores que dejó de existir en 0.4.0.
  Reescrito. `TRACKING.md` decía "completado" sobre noventa casillas sin marcar.
- Anotado un fallo que este trabajo destapó y no se arregla aquí: la clave de
  Kokoro no lleva el idioma, y como la misma voz sirve para español e inglés,
  un libro con el idioma cambiado reutiliza el audio del anterior. Arreglarlo
  huerfanizaría las descargas existentes sin una migración.

---

## 0.5.1-preview.1 — 2026-08-30

### Un párrafo mudo se quedaba mudo para siempre

En inglés con Edge no sonaba nada. La barra de estado del lector decía
`Error: (0) Source error · Edge · 1.1 MB`: el contador de datos probaba que la
síntesis había corrido, así que el fallo estaba entre escribir el archivo y
reproducirlo.

**Causa.** Si la síntesis no devolvía audio —un timeout, una conexión cortada—
el archivo se escribía igual, con cero bytes, y se registraba en la caché. A
partir de ahí ese párrafo estaba condenado: cada intento posterior encontraba
la entrada en caché, se la pasaba al reproductor, y el reproductor solo sabía
decir "Source error". Ninguna de las dos capas comprobaba que hubiera audio.

Explica por qué era permanente y por qué solo pasaba en un libro: bastaba un
único fallo de red para envenenar ese párrafo.

**Arreglo, en tres capas:**

- Edge, Kokoro y Piper fallan con un mensaje claro cuando no hay audio, en vez
  de escribir un archivo que nadie puede abrir. En Piper el umbral son 64
  bytes: una cabecera WAV sola son 44 y se reproduce como silencio.
- El lector no registra en caché un archivo de menos de 512 bytes; lo borra y
  propaga el error.
- `AudioCacheRepo.get` trata como ausente lo que esté vacío, no solo lo que
  falte. Esto **repara solo** las entradas ya envenenadas: se regeneran al
  siguiente intento, sin tener que limpiar la caché a mano.
- Los mensajes de error explican qué pasó en vez de mostrar el texto crudo de
  la excepción.

**Verificado en el teléfono.** Con *The Gunslinger* en inglés y Edge:
`Reproduciendo… · Edge · 0.3 MB`, `PlaybackState state=3` avanzando, y el
resaltado por palabra siguiendo el texto.

---

## 0.5.0-preview.1 — 2026-08-30

Primera versión probada en un teléfono real. Casi todo lo que sigue son fallos
que ningún test ni emulador podía revelar, más el trabajo que salió de usarla
de verdad.

### Motores de voz auto-alojados

- **Piper** como cuarto motor, con voces entrenadas en cada idioma. Un servidor
  sirve español e inglés y la app manda el modelo según el libro.
- **Kokoro** con `lang_code` explícito en cada petición. Sin él deducía el
  idioma de la primera letra de la voz, y `af_bella` leía español con reglas
  inglesas: el mismo párrafo salía en 17 s en vez de 27,5 s, ininteligible.
- Ambos se repliegan a Edge cuando el servidor no responde, y el motor
  realmente en uso se ve en la barra de estado del lector.
- `tools/kokoro/` y `tools/piper/` con compose, Dockerfile y documentación.

### Reproductor y pantalla de bloqueo

- **Los controles de bloqueo aparecen por fin.** `MainActivity` heredaba de
  `FlutterActivity` en vez de `AudioServiceActivity`: la app levantaba un motor
  Flutter aislado del servicio, que se quedaba sin handler y nunca creaba la
  notificación, aunque el audio sonara con normalidad.
- Portada del libro, barra de progreso y avance en el subtítulo.

### El texto ya no se descoloca

- **Pausar dejó de perder el sitio.** El auto-scroll centra el párrafo activo
  al 15 % del borde, así que "el más alto visible" era siempre el de detrás; y
  sus propios eventos encolaban una actualización que se aplicaba al pausar.
- Se introduce una **sesión de escucha**: mientras está abierta manda el audio,
  no el scroll. Se cierra solo al pulsar Detener o salir del libro.
- Reanudar devuelve la vista al texto resaltado aunque no haya cambiado de
  párrafo.
- Salir del libro guarda el progreso en vez de confiar en el guardado periódico.

### Cambiar de motor cambia la voz

- La búsqueda en caché consultaba preventivamente la clave de Edge, así que
  cualquier párrafo ya escuchado seguía sonando con Edge eligiera lo que
  eligiera el usuario. Solo se notaba en libros sin descargas propias.

### Descargas

- **Se saneó la clave de caché.** Llevaba `:` y `@`, y se incrustaba en el
  nombre del archivo: cada escritura fallaba en silencio mientras la barra de
  progreso llegaba al 100 % sin guardar nada. Hay migración para no perder lo
  ya descargado.
- Los fallos de descarga se cuentan y se muestran, en vez de pasar
  desapercibidos.
- Estimación de tiempo y tamaño antes de empezar, y tiempo restante durante la
  descarga, refinado con los tiempos reales.

### Almacenamiento

- **"Limpiar caché" ya no borra las descargas.** Borraba la tabla entera:
  un botón rotulado "caché" se llevaba por delante horas de síntesis.
- Desglose por libro y por motor, con borrado selectivo. Y "Borrar todo" para
  cuando de verdad se quiere empezar de cero.

### Otros

- **Diccionario en español** vía Wiktionary, además del inglés.
- Los ajustes **se guardan solos**: cambiar de motor ya no obliga a recorrer la
  pantalla hasta un botón al final.
- El deslizador de Ritmo de Piper decía "1.00×", que se lee como velocidad,
  cuando es longitud de fonema y va al revés. Ahora dice "1.00× · normal".
- El campo de dirección se resincroniza al cambiar de motor; antes una URL de
  Kokoro podía acabar guardada en Piper.
- Las barras del lector dejan de rozar el texto.

### Versionado

`versionName` sale ahora de `pubspec.yaml`. Estaba fijado por código a
`0.2.<commits>`, así que el minor nunca avanzaba y el APK contradecía a este
mismo archivo. El contador de commits sigue alimentando `versionCode`.

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
