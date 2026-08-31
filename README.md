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
| **Android** | El propio teléfono | Sin internet, sin servidor |

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
docker compose -f tools/kokoro/docker-compose.yml up -d   # puerto 8880
docker compose -f tools/piper/docker-compose.yml up -d    # puerto 5000
```

Luego, en **Ajustes → Motor de voz**, apunta a `http://<IP-de-tu-PC>:8880`.
Cada carpeta tiene su propio README con los detalles.

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
│   ├── tts/             # Edge, Kokoro, Piper y Android (Strategy + Factory)
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
