# VoiceX Móvil

Lector EPUB con TTS neuronal para Android. Lee en voz alta con voces naturales,
resalta el texto que va sonando, y funciona sin conexión con el audio que hayas
descargado. Construido con Flutter y distribuido como APK.

Versión Android de [VoiceX](https://github.com/Preston-IA/voicex).

## Qué hace

**Cuatro motores de voz**, elegibles en Ajustes:

| Motor | Dónde corre | Notas |
|---|---|---|
| **Edge** | Nube (Microsoft) | 300+ voces, tiempos por palabra. Funciona en cualquier red |
| **Qwen3** | Un Mac con Apple Silicon, propio | Voz clonada de una grabación. Solo español. No marca palabras |
| **Chatterbox** | El mismo Mac | Voz clonada, otro modelo. Solo español. No marca palabras |
| **Teléfono** | El propio móvil | El único sin red ni servidor. No marca palabras |

Qwen3 y Chatterbox salen del mismo servidor ([`tools/mlx`](tools/mlx/)); cuando
no responde, la app cae a Edge automáticamente y lo dice en pantalla. Se usan
para **descargar capítulos por tandas** con el teléfono en la WiFi de casa, y
escucharlos después sin conexión: no hace falta el Mac encendido para oírlos.

**Como lector**

- Modo inmersivo: el texto ocupa la pantalla y las barras se ocultan al tocar
- Una sola posición compartida entre leer y escuchar, al estilo Kindle+Audible
- Resaltado por palabra y por oración, sincronizado con el audio
- Tipografía, interlineado, márgenes y fondo sepia/claro/oscuro configurables
- Tres pieles para la biblioteca: la moderna, teñida con el color de cada
  portada; fichas de catálogo mecanografiadas; y una clásica de anticuario
  impresa a dos tintas. Siempre con la portada real del libro

**Como audiolibro**

- Controles en pantalla de bloqueo, notificaciones, auriculares y Bluetooth
- Descarga por adelantado en WiFi para escuchar sin conexión
- Velocidad de reproducción que no obliga a volver a sintetizar

**Para leer más**

- Rangos de lector, de *Lector novel* a *Maestro bibliotecario*, por páginas
  leídas o escuchadas; saltar desde el índice o la búsqueda no suma
- Pantalla de progreso con la pila de libros terminados y comparaciones con
  obras conocidas, no con otras personas
- Resumen semanal y recordatorio diario, opcionales y apagados de fábrica
- Buscar dentro del libro, notas en los marcadores, temporizador para dormir

**Para practicar idiomas**

- Repetir una oración, en bucle, para *shadowing*
- Pulsación larga sobre una palabra: oírla, consultar su definición, o copiar
  y compartir la oración
- Diccionario en inglés y español

---

## Versiones

| Versión | Lo que trajo |
|---|---|
| **0.14.1** | Un reporte hecho con el Mac apagado sale en cuanto el servidor vuelve a responder, sin esperar a que el teléfono cambie de red, y la nota de voz ya no se pierde si se corta a medio subir. |
| **0.14.0** | La barra del lector dice cuánto audio descargado queda por delante («sin conexión 1 h 45 min»). *Importar audios del Mac* los trae por Tailscale, sin cable, y en el Mac quedan como respaldo. `bajar` empieza en el párrafo donde vas leyendo. |
| **0.13.1** | Una pantalla para ver qué ocupa cada libro y borrar por capítulo, o todo lo anterior a donde vas (Ajustes → *Ver qué ocupa cada libro*). Borrar un libro ya borra su audio, que antes se quedaba en el teléfono sin dueño y sin verse en ningún detalle. Apagar la descarga adelantada cancela la que ya corre. |
| **0.13.0** | Edge vuelve a sonar (Microsoft cambió el token que exige y la app mandaba el viejo). Qwen3 y Chatterbox, voces clonadas generadas en un Mac, reemplazan a Kokoro, Piper y F5, que dependían de máquinas que ya no existen; sirven para descargar capítulos por tandas y oírlos sin conexión. Un EPUB con un byte suelto en el CSS ya se importa, lo descargado con el motor del teléfono deja de borrarse al abrir la app, y "Contar un problema" entrega al mismo Mac. **La primera vez que se abre borra el audio descargado con los motores retirados.** |
| **0.12.0** | La barra de escucha dice qué mueve cada botón: *Capítulo* y *Párrafo* escritos bajo los cuatro saltos, con doble chevrón para el capítulo en vez de la página con −/+ que un probador leyó como "eliminar o agregar una página". El índice abre en el capítulo actual en vez de desde arriba. Y dos arreglos: "Al final del capítulo" no funcionaba desde el menú del temporizador desde 0.10.0, y la barra oculta asomaba con descarga y oración resaltada |
| **0.11.0** | Las otras dos pieles, rehechas: la *Clásica* como un catálogo de anticuario a dos tintas —capitular roja, texto justificado, lotes en romanos, cinta de seda en el libro que estás leyendo— y la *Moderna* con cada tarjeta teñida del color de su portada, un solo botón y el estado en un chip. Las descripciones dejan de salir con los párrafos pegados |
| **0.10.1** | La piel *Fichas* pasa a parecer un fichero de verdad: mecanografiada sobre el rayado, con signatura en la esquina, la perforación de la varilla, sellos de goma para el estado —`SIN EMPEZAR` por fin se ve—, papel envejecido, la portada sujeta con un clip y el rango en el portaetiquetas de latón del cajón |
| **0.10.0** | Rangos de lector: cada página leída o escuchada suma, de *Lector novel* a *Maestro bibliotecario*, con una pantalla de progreso (la pila de libros terminados, comparaciones con obras conocidas, la semana en barras) y avisos semanales opcionales. Tres pieles para la biblioteca —moderna, fichas de catálogo y pergamino—, siempre con la portada real. Y los 23 hallazgos de una auditoría: buscar dentro del libro, temporizador para dormir, notas en marcadores, copiar y compartir citas, tocar la página oculta los controles en vez de cortar el audio, el servidor de F5 pide token, EPUB duplicados rechazados y una sección de Privacidad que dice qué sale del teléfono |
| **0.9.1** | Una descarga que se replegó a Edge ya no termina pareciendo una descarga limpia: ahora avisa antes de empezar si el motor elegido no está disponible —y deja cancelar—, y al terminar dice con cuál se descargó de verdad. Un capítulo de 104 párrafos bajado con la voz equivocada no se descubría hasta ponerse a escuchar |
| **0.9.0** | Descargar deja de repetir lo que ya leíste: se agrega "desde aquí hasta el final del capítulo", que arranca donde va la lectura en vez del párrafo 0. Y un servidor ocupado deja de romper la descarga — F5 ya avisaba que estaba trabajando en su propio sondeo de salud y la app no lo leía, así que le mandaba el párrafo siguiente a hacer cola por la GPU hasta agotarle la espera |
| **0.8.0** | Se va Chatterbox, entra F5-TTS. Sonaban parejos, pero Chatterbox iba a 0.089x tiempo real —casi tres horas de GPU por capítulo— y bloqueaba hasta su propio sondeo de salud mientras generaba, así que la app lo daba por caído a mitad de descarga. F5 hace lo mismo por encima de tiempo real y contesta el sondeo en milisegundos aunque esté trabajando |
| **0.7.2** | Chatterbox tiene un solo worker: mientras genera audio no contesta ni su propio sondeo de salud, y eso hacía que una descarga entera se replegara a Edge creyéndolo caído. Ahora se le da aire en vez de sondearlo cada 13 s, y el techo de espera de una descarga se calibra con lo que tarda esa máquina en vez de un número medido en otro hardware — antes se tiraba a la basura audio que el servidor sí había terminado |
| **0.7.1** | Cualquier capítulo descargado con Chatterbox se volvía huérfano en el primer reinicio de la app: la clave de caché se corrompía silenciosamente hacia Edge. Se repara también lo que ya había quedado mal etiquetado, y la descarga avisa en pantalla cuando termina con un motor distinto al elegido |
| **0.7.0** | La versión que prepara la app para dársela a otras personas. Kokoro y Piper dejan de estar abiertos a quien pase por la WiFi: escuchan solo en loopback, detrás de un proxy con un token por probador. La dirección sale de Ajustes y va compilada. Los fallos se reportan solos, encolados si el servidor no está, y se puede contar un problema por escrito o con una nota de voz. El diccionario en inglés deja de expirar. Vuelve el motor del teléfono, el único que lee sin red ni servidor. La letra se ajusta sin salir del libro |
| **0.6.0** | Fuera el TTS del teléfono: no marcaba palabras, sonaba a robot al lado de las voces neuronales y su WAV llenaba la caché. Un móvil que lo tuviera puesto vuelve a Edge solo, y su audio se borra en el arranque. Oír una palabra suelta con Kokoro o Piper vuelve a funcionar |
| **0.5.2** | Las descargas se borraban solas a los cinco días, el repliegue a Edge pedía una voz que Edge no tiene, y un párrafo ya descargado se volvía a sintetizar. Los repositorios pasan a tener tests contra SQLite real |
| **0.5.1** | Un párrafo cuyo audio salía vacío se guardaba en caché igual y quedaba mudo para siempre: en inglés con Edge no sonaba nada. Ahora ningún motor entrega audio vacío, la caché descarta lo que no se puede reproducir y el error se explica en pantalla |
| **0.5.0** | Primera versión probada en teléfono real. Controles de bloqueo que nunca habían aparecido, el texto que se descolocaba al pausar, el cambio de motor que no cambiaba nada, y descargas que se guardaban en el vacío. Diccionario español, ajustes que se guardan solos, almacenamiento por libro y motor |
| **0.4.0** | Motores auto-alojados: Kokoro y Piper en la red local, con repliegue automático a Edge. Descarga previa en WiFi. Repetir oración, oír una palabra, diccionario |
| **0.3.0** | Modo lectura estilo Kindle: inmersivo, posición compartida, tipografía y temas. Audio en segundo plano. Resaltado por palabra. ~20 bugs, entre ellos un filtro que descartaba los diálogos cortos de las novelas |
| **0.2.0** | Portadas y metadatos EPUB en la biblioteca |
| **0.1.0** | Primera versión funcional |

El detalle de cada cambio, con su causa, está en
[`docs/RELEASES.md`](docs/RELEASES.md).

---

## Requisitos

- [Flutter 3.50 o posterior](https://docs.flutter.dev/get-started/install) (canal stable): el proyecto usa Gradle 9.5, que exige un Flutter reciente
- Android 7.0 o superior (API 24+)
- Android Studio o un dispositivo conectado

```bash
flutter doctor
```

---

## Quickstart

```bash
git clone https://github.com/PedroSolorzano/voicex-movil.git
cd voicex-movil
flutter pub get
flutter run
```

### Servidor de voz (opcional)

Solo si quieres usar Qwen3 o Chatterbox. La app funciona sin él con Edge. Corre
en un Mac con Apple Silicon:

```bash
cd tools/mlx && ./arrancar.sh   # puerto 8765; el token queda en tools/mlx/.token
```

La instalación, las voces y el porqué de cada decisión están en
[`tools/mlx/README.md`](tools/mlx/README.md).

Para moverse por las herramientas del Mac (ruta, PATH, `adb`, audios por cable,
reportes) ver [`docs/context/USO_HERRAMIENTAS.md`](docs/context/USO_HERRAMIENTAS.md):
`source tools/entorno.sh` deja la terminal lista. Al principio de esa guía está el
*inicio rápido* para generar audio y pasarlo al celular, paso a paso.

La dirección **no se escribe en Ajustes**: va compilada en el APK. Compila con
`compilar.sh` (o `compilar.ps1` en Windows), que pasa `voz.json` (la dirección) y tu `.json` personal (el
token `VOICE_TOKEN`); ver [`tools/release/README.md`](tools/release/README.md).
Sin eso, esos chips ni aparecen en Ajustes → Motor de voz.

---

## Build

```powershell
tools/release/compilar.sh -l -i                   # macOS/Linux; -l si cambió la versión
.\tools\release\compilar.ps1 -Limpio -Instalar   # Windows, lo mismo
```

**No `flutter build apk` a mano**: sin `--dart-define-from-file` el APK sale
sin servidores —solo Edge y Teléfono en Ajustes—, se instala igual y no avisa.
El script pasa los `.json` y comprueba después que las URLs quedaron
dentro del binario. `compilar.sh` es bash y no pide nada más que `flutter` y
`python3`; `compilar.ps1` funciona con PowerShell 7 (`pwsh`) y con el 5.1 que trae
Windows. Detalles en
[`tools/release/README.md`](tools/release/README.md).

El APK queda en `build/app/outputs/flutter-apk/` con el nombre de la versión.
`versionName` sale de `pubspec.yaml`; el `versionCode` se deriva del número de
commits.

---

## Estructura

```
VoiceXMovil/
├── lib/
│   ├── config/          # AppSettings (SharedPreferences)
│   ├── tts/             # Edge, Qwen3, Chatterbox y el del sistema (Strategy + Factory)
│   ├── epub/            # Parser EPUB, modelos y alineado texto-audio
│   ├── audio/           # Handler de audio_service con MediaSession
│   ├── services/        # Diccionario, reportes y avisos de lectura
│   ├── stats/           # Rangos de lector: crédito, escala, equivalencias, citas
│   ├── storage/         # SQLite: libros, progreso, marcadores, caché
│   └── ui/              # providers · screens · widgets
├── tools/
│   ├── mlx/             # Servidor de voz Qwen3 + Chatterbox y buzón de reportes (Mac, MLX)
│   ├── release/         # compilar.sh / .ps1 y los .json de cada compilación
│   ├── reportes/        # Vuelca los reportes recibidos a docs/bugs
│   ├── skins/           # Genera las texturas de las pieles de biblioteca
├── test/
└── docs/
    ├── RELEASES.md            # Historial de versiones
    ├── context/TECHNICAL.md   # Especificación técnica
    ├── context/ACCESO_REMOTO.md # Kokoro/Piper fuera de casa
    ├── tasks/IMPROVEMENTS.md  # Mejoras pendientes
    ├── tasks/TRACKING.md      # Estado de implementación
    └── bugs/EDGE_TTS_DEBUG.md # Investigaciones de bugs
```

---

## Comandos útiles

```bash
flutter devices                  # dispositivos disponibles
flutter test                     # tests
flutter analyze                  # análisis estático
flutter clean && flutter pub get # limpiar build cache
```

---

## Proyecto relacionado

[VoiceX Desktop](https://github.com/PedroSolorzano/voicex) — versión
Python/tkinter para escritorio (Linux/macOS/Windows).
