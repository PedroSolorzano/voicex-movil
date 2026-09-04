# El botón de escuchar voz se queda mudo para siempre con el motor Teléfono

**Reportado:** `docs/bugs/REPORTES_TESTERS.md`, entrada del 2026-09-03 21:40
(spiny, Don Quijote, motor Teléfono) — nota de voz transcrita: *"no me
funcionan los previos de las voces, solo me funcionó como 10 veces y después
dejaron de funcionar"*. No hay crash ni mensaje de error: el botón deja de
hacer nada.

---

## Hipótesis, con el código que la sostiene

El botón de previsualizar voz tiene un guardián de reentrada:

```dart
// settings_screen.dart:774
Future<void> _preview(String voiceId, String lang) async {
  if (_previewing != null) return;
  setState(() => _previewing = voiceId);
  ...
  try {
    ...
    await tts.synthesize(...);   // android_tts_provider.dart:82 → _tts.synthesizeToFile(...)
    ...
  } finally {
    ...
    setState(() => _previewing = null);   // settings_screen.dart:804
  }
}
```

Si el `await` nunca vuelve, `_previewing` se queda con un valor para siempre y
**todo** botón de previsualizar, de cualquier voz, se convierte en un no-op —
exactamente lo que describe el reporte.

`AndroidTtsProvider` pide completar la síntesis antes de seguir
(`android_tts_provider.dart:42`, `awaitSynthCompletion(true)`). El plugin
`flutter_tts` (4.2.5, `FlutterTtsPlugin.kt` en
`~/.pub-cache/hosted/pub.dev/flutter_tts-4.2.5/android/.../FlutterTtsPlugin.kt`)
implementa ese `await` guardando el `Result` del canal de método y
resolviéndolo más tarde, cuando el motor nativo de Android avisa que terminó:

```kotlin
// FlutterTtsPlugin.kt:343-357 — maneja la llamada "synthesizeToFile"
if (synth) { result.success(0); return }   // ya hay una síntesis en curso
synthesizeToFile(text, fileName, isFullPath)
if (awaitSynthCompletion) {
    synth = true
    synthResult = result        // se guarda, no se resuelve todavía
}

// FlutterTtsPlugin.kt:209-215 — se llama SOLO desde onDone()
fun synthCompletion(success: Int) {
    synth = false
    synthResult?.success(success)   // acá se libera el await de Dart
    synthResult = null
}
```

El problema está en el otro camino, `onError`:

```kotlin
// FlutterTtsPlugin.kt:185-191
override fun onError(utteranceId: String, errorCode: Int) {
    if (utteranceId.startsWith(SYNTHESIZE_TO_FILE_PREFIX)) {
        closeParcelFileDescriptor(true)
        if (awaitSynthCompletion) {
            synth = false          // desbloquea la SIGUIENTE llamada nativa...
        }
        invokeMethod("synth.onError", "...")   // ...pero esto es un evento, no una respuesta
    }
    ...
}
```

`onError` limpia el flag `synth` (así que el motor nativo vuelve a aceptar
peticiones) pero **nunca llama a `synthResult.success(...)`**. El `Result`
guardado por el canal de método queda huérfano. Del lado de Dart, eso es un
`Future` que jamás se completa: el `await tts.synthesize(...)` en
`_preview()` cuelga para siempre, sin excepción, sin timeout.

Encaja con "funcionó unas 10 veces y después dejó de funcionar": basta con que
el motor TTS del sistema falle *una sola vez* — voz no descargada, motor
ocupado, cualquier `ERROR_*` de Android `TextToSpeech` — para que esa
preview se cuelgue y deje `_previewing` fijo. A partir de ahí cada toque
subsiguiente entra por el guardián de la línea 774 y no hace nada, sin
importar cuántas veces se reintente ni qué voz se elija.

Ningún otro motor (Edge, Kokoro, Piper) pasa por `flutter_tts`, así que esto es
exclusivo de "Teléfono".

---

## Qué falta para confirmarlo

No se reprodujo en banco, solo se rastreó por código. Para cerrar la
investigación:

- Reproducir el cuelgue forzando un error del motor nativo (por ejemplo,
  eligiendo una voz `network`/no descargada mientras el teléfono está en modo
  avión) y confirmar que el botón deja de responder sin reiniciar la app.
- Verificar si versiones más nuevas de `flutter_tts` (vamos en 4.2.5,
  `pubspec.yaml:32` fija `^4.0.2`) corrigen `onError` para resolver
  `synthResult`.

## Arreglo probable

No depende del plugin: alcanza con no confiar en que el `await` siempre
vuelva. Un `Future.any([...,  Future.delayed(...)])` o `.timeout(...)`
alrededor de `tts.synthesize(...)` en `_preview()` (`settings_screen.dart:786`)
convierte el cuelgue silencioso en el mismo `catch` que ya maneja los demás
fallos, y el `finally` vuelve a correr y libera `_previewing`. Mismo riesgo
existe fuera de la preview, en cualquier síntesis con el motor Teléfono
(`android_tts_provider.dart:82`), aunque ahí un cuelgue se nota menos porque no
hay un guardián global bloqueando el resto de la app.

---

## Reporte relacionado, sin diagnóstico propio

La entrada anterior del mismo tester (2026-09-03 21:31, Alice cap. 1, motor
Teléfono) se queja de la velocidad: *"no sé qué onda con la velocidad cuando
usó la voz Teléfono"*. No hay síntoma reproducible en el texto ni un
diagnóstico adjunto que aplique (el log que acompaña son health-checks de
Kokoro, ajenos a este motor). Queda anotado en
`docs/bugs/REPORTES_TESTERS.md` pero no se investigó más: falta que el tester
precise si el audio suena más rápido, más lento o entrecortado.
