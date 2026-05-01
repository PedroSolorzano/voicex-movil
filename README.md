# VoiceX Móvil

Versión Android de [VoiceX](https://github.com/Preston-IA/voicex) — lector EPUB con TTS neuronal. Construido con Flutter. Distribuido como APK.

- TTS online: Edge TTS (voces Microsoft, vía WebSocket)
- TTS offline: Android TTS nativo
- Caché de audio para re-reproducción sin internet
- Subrayado de oración activa en tiempo real
- Sincronización de progreso y marcadores (SQLite local)

---

## Requisitos

- [Flutter 3.x](https://docs.flutter.dev/get-started/install) (canal stable)
- Android SDK API 21+ (Android 5.0)
- Android Studio o un dispositivo/emulador conectado

Verifica tu entorno:

```bash
flutter doctor
```

---

## Quickstart

```bash
# 1. Clonar
git clone https://github.com/Preston-IA/voicex-movil.git
cd voicex-movil

# 2. Instalar dependencias
flutter pub get

# 3a. Correr en dispositivo/emulador conectado
flutter run

# 3b. Correr en emulador específico
flutter run -d emulator-5554
```

---

## Build APK

```bash
# APK de debug (para pruebas)
flutter build apk --debug

# APK de release (para distribución)
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/`.

---

## Estructura

```
VoiceXMovil/
├── lib/
│   ├── main.dart
│   ├── config/          # AppSettings (SharedPreferences)
│   ├── tts/             # Edge TTS + Android TTS (Strategy + Factory)
│   ├── epub/            # Parser EPUB y modelos
│   ├── audio/           # AudioPlayer con ticks de 50ms
│   ├── storage/         # SQLite (libros, progreso, bookmarks, caché)
│   └── ui/
│       ├── providers/   # Riverpod state
│       ├── screens/     # library, reader, settings
│       └── widgets/     # BookCard, HighlightedText
├── android/
├── test/
├── pubspec.yaml
└── docs/
    ├── context/TECHNICAL.md   # Especificación técnica completa
    ├── tasks/IMPROVEMENTS.md  # Mejoras y nuevos requisitos
    ├── tasks/TRACKING.md      # Estado de implementación
    ├── bugs/EDGE_TTS_DEBUG.md # Investigaciones de bugs
    └── RELEASES.md            # Historial de versiones
```

---

## Comandos útiles

```bash
# Ver dispositivos disponibles
flutter devices

# Limpiar build cache
flutter clean && flutter pub get

# Correr tests
flutter test

# Analizar código
flutter analyze
```

---

## Tareas pendientes

| # | Tarea | Estado |
|---|-------|--------|
| — | — | — |

> Las tareas se agregan aquí a medida que surgen durante el desarrollo.

---

## Proyecto relacionado

[VoiceX Desktop](https://github.com/PedroSolorzano/voicex) — versión Python/tkinter para escritorio (Linux/macOS/Windows).
