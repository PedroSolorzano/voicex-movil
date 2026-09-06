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

**Un motor que no aparece en Ajustes casi siempre es esto**: `TtsServerConfig`
solo ofrece el motor cuya URL llegó vacía al build. Antes de compilar, revisá
qué variables lleva el `.json` que vas a usar contra las que llevaba el build
anterior — un archivo incompleto no avisa, simplemente el motor desaparece en
silencio.

## Sumar Kokoro a una compilación

`KOKORO_URL` vive en [`kokoro.json`](kokoro.json), **trackeado en git** a
diferencia de los `.json` por probador: la dirección del proxy es la misma
para cualquier compilación tuya, lo único que cambia por persona es
`TTS_TOKEN`. `--dart-define-from-file` acepta repetirse:

```bash
flutter build apk --release \
  --dart-define-from-file=tools/release/amigo.json \
  --dart-define-from-file=tools/release/kokoro.json
```

Si el proxy cambia de dirección de tailnet, actualizar `kokoro.json` y
recompilar. `PIPER_URL` queda fuera de este archivo a propósito: Piper
devuelve WAV sin comprimir (~159 MB/hora) y no siempre conviene mandárselo a
un probador, así que sigue viviendo en el `.json` personal de quien sí lo
quiera.

## Sumar F5 a una compilación

`F5_URL` vive en [`f5.json`](f5.json), **trackeado en
git** a diferencia de los `.json` por probador: no lleva proxy ni token, así
que no hay nada que revocar (ver
[`docs/context/ACCESO_REMOTO.md`](../../docs/context/ACCESO_REMOTO.md),
segundo nodo de la tailnet). `--dart-define-from-file` acepta repetirse, así
que se combina con tu archivo personal en el mismo build:

```bash
flutter build apk --release \
  --dart-define-from-file=tools/release/amigo.json \
  --dart-define-from-file=tools/release/f5.json
```

Si la laptop cambia de IP de tailnet, actualizar `f5.json` y
recompilar.

## Configurar una segunda PC propia

Esto es para vos mismo en una segunda máquina, no para un probador nuevo: el
mismo `TTS_TOKEN`, la misma firma, otro disco. El objetivo es compilar ahí un
APK igual de completo al de la primera PC sin tener que mandarse nada en cada
build.

**Lo que ya llega solo con `git pull`:** `kokoro.json` y `f5.json`
(las URLs, sin token) — no hay que tocarlos.

**Lo que hay que llevar aparte, una sola vez, por USB** (nunca por git: ver
"Lo que un APK no puede esconder" y "El keystore" más abajo para el porqué de
cada uno):

| Archivo | Va en | Por qué no está en git |
|---|---|---|
| `voicex.keystore` | `android/app/` | Firma del APK; perderlo es no poder actualizar nunca más ningún APK ya instalado. |
| `key.properties` | `android/` | Contraseñas de esa firma. |
| `pedro.json` (o el `.json` personal que uses) | `tools/release/` | Lleva `TTS_TOKEN` y, si querés Piper, `PIPER_URL`. Es lo que falta hoy si Kokoro no aparece configurable en la segunda PC. |

**Lo que NO se copia:** `android/local.properties`. Lo regenera Flutter solo
en el primer build, y trae el `sdk.dir` de *esa* máquina — copiar el de la
otra PC apunta a una ruta que no existe ahí y rompe el build.

Con los tres archivos en su sitio, compilar es el mismo comando de siempre:

```bash
flutter build apk --release \
  --dart-define-from-file=tools/release/pedro.json \
  --dart-define-from-file=tools/release/kokoro.json
```

Y confirmar como en cualquier build (ver "Al subir la versión, compila
limpio"): instalar el APK y probar conexión en Ajustes → Motor de voz para
Kokoro y Piper. Hecho este traspaso una vez, compilar en cualquiera de las dos
PCs no vuelve a pedir mandarse nada: cada `git pull` trae lo público, y lo
privado ya quedó instalado en ambas.

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
