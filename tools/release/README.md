# Compilar un APK por probador

La dirección del servidor y el token van **dentro del binario**, no en un campo
de Ajustes. Una compilación por persona, cada una con su token.

```bash
cp tools/release/tester.example.json tools/release/amigo.json   # y edítalo
flutter build apk --release --dart-define-from-file=tools/release/amigo.json
```

El APK sale en `build/app/outputs/flutter-apk/`. Renómbralo con el nombre de la
persona antes de mandarlo: todas las compilaciones del mismo commit comparten
`versionName` y `versionCode`, así que el nombre del fichero es lo único que las
distingue.

Sin `--dart-define-from-file`, la compilación no trae servidor: solo Edge, y los
chips de Kokoro y Piper no aparecen. Es el modo correcto para probar la app sin
depender de nada.

## Al subir la versión, compila limpio

`flutter build apk` **no regenera el manifiesto** cuando lo único que cambió es
la versión: Gradle no vigila `android/local.properties` como entrada de tarea.
El resultado es traicionero, porque el fichero sale con el nombre nuevo mientras
el APK lleva dentro el `versionName` viejo — comprobado: un APK llamado
`voicex-0.7.0-...apk` que se instalaba y decía ser 0.6.0.

Así que después de tocar `version:` en `pubspec.yaml`:

```bash
flutter clean
flutter build apk --release --dart-define-from-file=tools/release/amigo.json
```

Y confirma siempre lo que hay dentro, no lo que dice el nombre:

```bash
aapt dump badging build/app/outputs/flutter-apk/app-release.apk | head -1
adb shell dumpsys package com.pedrosolorzano.voicex_movil | grep versionName
```

Importa más de lo que parece con varios probadores: el `versionName` es lo que
la app estampa en cada petición (`X-Voicex-Client`) y lo que aparece en el log
del proxy. Con él mal, los informes atribuyen el fallo a la compilación
equivocada.

## Lo que un APK no puede esconder

Un valor compilado con `String.fromEnvironment` es una cadena literal dentro del
snapshot: `unzip -p app.apk lib/arm64-v8a/libapp.so | strings` lo encuentra en
segundos. `isMinifyEnabled` no ayuda — R8 ofusca Java y Kotlin, no el código
Dart. Y el nombre del host es público de todas formas: los certificados `*.ts.net`
aparecen en los registros de Certificate Transparency a los minutos de emitirse.

Por eso el token **no se trata como un secreto** sino como un identificador
revocable. Lo que protege la máquina de casa está en el proxy: un token distinto
por persona, límite de ritmo, lista blanca de rutas, backends en loopback y el
túnel apagado fuera de la ventana de pruebas. Ver
[`tools/proxy/README.md`](../proxy/README.md).

## Entrega

- **Nunca un enlace público ni un release de GitHub**: el APK lleva el token.
  Envío directo a cada persona.
- Avisa de que Android dirá que el archivo es peligroso y de que Play Protect
  pedirá confirmación. Sin ese aviso, la mitad cancela la instalación.
- Manda un EPUB de dominio público con el APK: una biblioteca vacía es la peor
  primera pantalla y desperdicia la mitad del feedback.

## El keystore

`android/app/voicex.keystore` y `android/key.properties` están gitignorados y no
se pueden regenerar: **perderlos significa no poder actualizar nunca más el APK
de nadie sin desinstalar primero**. Cópialos fuera de esta máquina.
