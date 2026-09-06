# VoiceX Móvil

Lector EPUB con TTS neuronal para Android. Lee en voz alta con voces naturales,
resalta el texto que va sonando, y funciona sin conexión con el audio que hayas
descargado. Construido con Flutter y distribuido como APK.

Versión Android de [VoiceX](https://github.com/Preston-IA/voicex).

## Qué hace

**Cuatro motores de voz**, elegibles por libro:

| Motor | Dónde corre | Notas |
|---|---|---|
| **Edge** | Nube (Microsoft) | 300+ voces, tiempos por palabra. Funciona en cualquier red |
| **Kokoro** | Servidor propio | Mejor calidad de voz, con tiempos por palabra |
| **Piper** | Servidor propio | Voces entrenadas por idioma. El más rápido |
| **Teléfono** | El propio móvil | El único sin red ni servidor. No marca palabras |

Kokoro y Piper corren en tu computadora ([`tools/`](tools/)); cuando no
responden, la app cae a Edge automáticamente y lo dice en pantalla.

**Como lector**

- Modo inmersivo: el texto ocupa la pantalla y las barras se ocultan al tocar
- Una sola posición compartida entre leer y escuchar, al estilo Kindle+Audible
- Resaltado por palabra y por oración, sincronizado con el audio
- Tipografía, interlineado, márgenes y fondo sepia/claro/oscuro configurables

**Como audiolibro**

- Controles en pantalla de bloqueo, notificaciones, auriculares y Bluetooth
- Descarga por adelantado en WiFi para escuchar sin conexión
- Velocidad de reproducción que no obliga a volver a sintetizar

**Para practicar idiomas**

- Repetir una oración, en bucle, para *shadowing*
- Pulsación larga sobre una palabra: oírla o consultar su definición
- Diccionario en inglés y español

---

## Versiones

| Versión | Lo que trajo |
|---|---|
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

- [Flutter 3.x](https://docs.flutter.dev/get-started/install) (canal stable)
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

### Servidores de voz (opcional)

Solo si quieres usar Kokoro o Piper. La app funciona sin ellos con Edge.

```bash
docker compose -f tools/kokoro/docker-compose.yml up -d   # puerto 8880, solo loopback
docker compose -f tools/piper/docker-compose.yml up -d    # puerto 5000, solo loopback
```

La dirección **no se escribe en Ajustes**: va compilada en el APK. Compila con
`--dart-define-from-file` apuntando a un `.json` con `KOKORO_URL`/`PIPER_URL`
(ver [`tools/release/README.md`](tools/release/README.md)); sin eso, esos
chips ni aparecen en Ajustes → Motor de voz. Cada carpeta tiene su propio
README con los detalles.

---

## Build

```bash
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/` con el nombre de la versión.
`versionName` sale de `pubspec.yaml`; el `versionCode` se deriva del número de
commits.

---

## Estructura

```
VoiceXMovil/
├── lib/
│   ├── config/          # AppSettings (SharedPreferences)
│   ├── tts/             # Edge, Kokoro, Piper y el del sistema (Strategy + Factory)
│   ├── epub/            # Parser EPUB, modelos y alineado texto-audio
│   ├── audio/           # Handler de audio_service con MediaSession
│   ├── services/        # Diccionario
│   ├── storage/         # SQLite: libros, progreso, marcadores, caché
│   └── ui/              # providers · screens · widgets
├── tools/
│   ├── kokoro/          # Servidor de voz Kokoro (Docker)
│   └── piper/           # Servidor de voz Piper (Docker)
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
