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
chips de Qwen3 y Chatterbox no aparecen. Es el modo correcto para probar la app sin
depender de nada.

**Un motor que no aparece en Ajustes casi siempre es esto**: `TtsServerConfig`
solo ofrece el motor cuya URL llegó vacía al build. Antes de compilar, revisá
qué variables lleva el `.json` que vas a usar contra las que llevaba el build
anterior — un archivo incompleto no avisa, simplemente el motor desaparece en
silencio.

## Sumar el servidor de voz a una compilación

`VOICE_URL` vive en [`voz.json`](voz.json), **trackeado en git** a diferencia
de los `.json` por probador: es la dirección del Mac que corre Qwen3-TTS y
Chatterbox (`tools/mlx`), igual para cualquier compilación tuya. Lo único que
cambia por persona es el token, `VOICE_TOKEN`, que va en el `.json` personal.
`--dart-define-from-file` acepta repetirse, y **el último archivo gana cada
clave que repita**, así que el personal va al final:

```bash
flutter build apk --release \
  --dart-define-from-file=tools/release/voz.json \
  --dart-define-from-file=tools/release/pedro.json
```

`compilar.sh` (macOS y Linux) o `compilar.ps1` (Windows) hacen exactamente eso y
además comprueban que las direcciones y el token quedaron dentro del APK. El
`.sh` no necesita PowerShell: es bash con `flutter`, `python3` y `unzip`.

Una dirección equivocada es igual de callada que una que falta: el motor sí
aparece en Ajustes, no contesta nunca y la app se repliega a Edge sin decirlo.
Si el Mac cambia de dirección, actualizar `voz.json` y recompilar. Una
dirección de la red local (`192.168.x.x`) cambia cuando el router reparte otra:
conviene reservarla en el router, o usar una de Tailscale, que no cambia.

**Los reportes ("Contar un problema") van al mismo servidor**, con el mismo
token: `POST /report` y `PUT /report/audio/…` en `tools/mlx/server.py`. No hay
nada más que configurar: la función existe exactamente cuando la compilación
trae `VOICE_URL`. Sin esa dirección (un APK con solo Edge), `Reporter.canDeliver`
es falso y Ajustes ni muestra la sección, porque un reporte encolado sin destino
promete un envío que nunca ocurre. Lo que llega se procesa con
`tools/reportes/procesar.sh`.

## Configurar una segunda PC propia

Esto es para vos mismo en una segunda máquina, no para un probador nuevo: el
mismo `TTS_TOKEN`, la misma firma, otro disco. El objetivo es compilar ahí un
APK igual de completo al de la primera PC sin tener que mandarse nada en cada
build.

**Lo que ya llega solo con `git pull`:** `voz.json`
(la URL, sin token) — no hay que tocarlos.

**Lo que hay que llevar aparte, una sola vez, por USB** (nunca por git: ver
"Lo que un APK no puede esconder" y "El keystore" más abajo para el porqué de
cada uno):

| Archivo | Va en | Por qué no está en git |
|---|---|---|
| `voicex.keystore` | `android/app/` | Firma del APK; perderlo es no poder actualizar nunca más ningún APK ya instalado. |
| `key.properties` | `android/` | Contraseñas de esa firma. |
| `pedro.json` (o el `.json` personal que uses) | `tools/release/` | Lleva `VOICE_TOKEN` (servidor de voz, el de `tools/mlx/.token`). Es lo que falta si Qwen3 y Chatterbox no aparecen en la segunda PC. |

**Lo que NO se copia:** `android/local.properties`. Lo regenera Flutter solo
en el primer build, y trae el `sdk.dir` de *esa* máquina — copiar el de la
otra PC apunta a una ruta que no existe ahí y rompe el build.

Con los tres archivos en su sitio, compilar es el mismo comando de siempre:

```bash
flutter build apk --release \
  --dart-define-from-file=tools/release/voz.json \
  --dart-define-from-file=tools/release/pedro.json
```

Y confirmar como en cualquier build (ver "Al subir la versión, compila
limpio"): instalar el APK y probar conexión en Ajustes → Motor de voz para
Qwen3 y Chatterbox. Hecho este traspaso una vez, compilar en cualquiera de las dos
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
`tools/mlx/README.md`.

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
