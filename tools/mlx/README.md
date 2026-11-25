# Servidor de voz en el Mac (Qwen3-TTS y Chatterbox)

También hace de buzón de los reportes de la app: ver "Reportes de la app" más abajo.

Un solo proceso sirve dos motores con las voces clonadas de `voices/`. La app
los ve como `qwen3` y `chatterbox2`: comparten dirección, token y `/health`.

Reemplaza a F5, que corría en la laptop con GPU que se averió (su carpeta se
borró; sigue en el historial de git). Se eligieron Qwen3-TTS y Chatterbox por una prueba de
oído y de medidas sobre el mismo diálogo en este Mac (M3 Max, 64 GB):

| | Qwen3-TTS 1.7B | Chatterbox multilingüe |
|---|---|---|
| Errores de lectura (Whisper) | 0,0 % | 0,0 % – 0,7 % |
| Tiempo por hora de audio | ~21 min (RTF 0,35) | ~27 min (RTF 0,44–0,48) |
| Memoria | ~10 GB | ~5,5 GB |

La velocidad deja de decidir: el uso es **descargar 2 o 3 capítulos por tanda**
y oírlos sin conexión, no sintetizar en directo. Chatterbox había quedado fuera
de la app en 0.8.0 por ir a 0,089x tiempo real en una RTX 4050; en este Mac va
a ~0,45x, cinco veces más rápido que escuchar.

```bash
./arrancar.sh
```

Arranca en ~15 s porque los dos modelos ya están en la caché de Hugging Face.
Muestra la dirección y deja el token en `.token` (ignorado por git).
`caffeinate -i` evita que el Mac se duerma mientras sirve.

## Instalación (una vez)

```bash
cd tools/mlx
uv venv --python 3.12 .venv
uv pip install --python .venv/bin/python -r requirements.txt
brew install ffmpeg        # o que ffmpeg esté en el PATH
```

La primera vez descarga ~9 GB de modelos (Qwen3 4,5 GB, Chatterbox 2,7 GB y sus
tokenizadores). **Python 3.12, no el 3.15 del sistema**: `mlx` no publica ruedas
para versiones tan nuevas.

## Las voces

Cada voz son **dos archivos** en `voices/`:

```
voices/esposa.wav   la grabación de referencia
voices/esposa.txt   la transcripción exacta de esa grabación
```

El `.txt` no es opcional: Qwen3 alinea la voz contra su texto, y una voz sin él
se omite (y lo dice en el log). Se lee al arrancar: **para añadir una voz hay
que reiniciar el servidor.** Hay dos: `esposa` y `colombiana` (OpenSLR 72,
CC-BY-SA).

Qué se hereda de la grabación, igual que con F5:

- **La calidad del audio se reproduce.** Una grabación con ruido da una voz con
  ruido.
- **El ritmo de la referencia fija el ritmo de todo lo generado.**
- **El acento también.** Por eso las voces clonadas son las que dan un español
  latino: el modelo lo copia de la grabación.

Con 5 a 10 segundos de una sola persona, sin música, basta. Mono, 24 kHz.

## Por qué está hecho así

- **Un solo hilo para toda la GPU** (`ThreadPoolExecutor(max_workers=1)`). MLX
  ata sus streams al hilo que los crea: cargar el modelo en uno y sintetizar
  desde otro falla con "no Stream in current thread". Ese hilo hace además de
  cola: una síntesis a la vez.
- **`/health` fuera de ese hilo.** Contesta en milisegundos aunque haya una
  síntesis en curso y dice `"busy": true`. Es el mismo diseño que tuvo F5 y por
  la misma razón: Chatterbox compartía un hilo entre síntesis y sondeo, y un
  párrafo largo lo hacía parecer muerto (`docs/bugs/CHATTERBOX_DESCARGAS.md`).
  La app trata `busy` como "no usable ahora" y vuelve a Edge sin hacer cola.
- **El párrafo entero va en una petición**, y el servidor solo lo parte si pasa
  de 380 caracteres, por oraciones. Así se midió (0 % de errores); partir de más
  introduce pausas que el modelo no pondría. Los modelos autorregresivos
  pueden saltarse o repetir palabras en tramos largos, y por eso el tope.
- **El motor se llama `chatterbox2`, no `chatterbox`.** Ese id lo retiró la app
  en 0.8.0, y `_dropRetiredEngineRows` borra en cada arranque todo lo que lleve
  `chatterbox-`. Un motor nuevo con ese nombre perdería sus descargas la
  siguiente vez que se abriera la app.
- **MP3 a 96 kbps por ffmpeg**, en memoria, sin archivos temporales. La app
  guarda el MP3 tal cual.
- **`mx.clear_cache()` tras cada síntesis.** Sin él el proceso conserva los
  buffers de cada párrafo y la huella crece muy por encima de lo que el modelo
  necesita (medido: 35 GB de huella con 9 GB reales).

## API

| | |
|---|---|
| `GET /health` | `{"status": "ok", "engines": [...], "voices": [...], "busy": false}`. `status` es `loading` mientras cargan los modelos. |
| `POST /tts` | `{"text": "...", "voice": "esposa", "engine": "qwen3"}` → `audio/mpeg` |
| `POST /report` | El reporte de la app (JSON, máx. 32 KB) → `204` |
| `PUT /report/audio/<uuid>.m4a` | La nota de voz de un reporte (máx. 4 MB) → `204` |

`401` con token malo, `404` con voz o motor desconocidos, `503` mientras carga.

La app **no** manda la velocidad: la aplica al reproducir, y así un mismo
archivo sirve a todas.

## Variables

| Variable | Por defecto | Para qué |
|---|---|---|
| `VOZ_TOKEN` | `.token` (lo lee `arrancar.sh`) | Credencial. Sin ella el servidor no pide nada, lo cual en una WiFi ajena enumera tus voces a cualquiera. |
| `VOZ_PUERTO` | `8765` | Puerto. **No 5000 ni 7000**: macOS los usa para AirPlay. |
| `VOZ_MOTORES` | `qwen3,chatterbox2` | Cuáles cargar. Con uno solo ahorra memoria; con `VOZ_MOTORES=""` no carga ninguno (~80 MB en vez de ~7,6 GB) y el servidor solo recibe reportes. |
| `VOZ_MAX_CHARS` | `380` | A partir de cuándo se parte un párrafo. |
| `VOZ_VOCES` | `./voices` | Carpeta de voces. |
| `VOZ_REPORTES` | `./reportes` | Dónde se guardan los reportes y sus notas. |
| `VOZ_TESTER` | `pedro` | Nombre que se anota en cada reporte. |

## Reportes de la app

"Contar un problema" y los fallos que la app captura solos llegan aquí, con el
mismo token que la síntesis. No es pesado: son dos rutas pequeñas dentro del
mismo proceso, sin memoria extra, y cada reporte ocupa como mucho 32 KB de texto
más una nota de voz de hasta 4 MB.

```
reportes/reportes.jsonl      una línea por reporte: {"ts", "tester", "app", "reporte"}
reportes/notas/<uuid>.m4a    la nota de voz que lo acompaña, si trae una
```

Es el mismo formato que dejaba el proxy de nginx que los recibía antes, y
`tools/reportes/procesar.sh` los vuelca a `docs/bugs/REPORTES_TESTERS.md` y a
`docs/tasks/IMPROVEMENTS.md`, transcribiendo la nota de voz en el propio Mac.

- **El nombre de la nota lo impone el servidor**: solo acepta un UUID con
  `.m4a`, así que un cliente no puede elegir dónde se escribe un archivo.
- **Límites de tamaño y de ritmo** (20 por minuto): con el token dentro del APK
  son lo que impide que un cliente que se repite solo llene el disco.
- **El archivo se abre, escribe y cierra en cada reporte.** Así el procesador
  puede renombrarlo en cualquier momento sin avisarle al servidor; con nginx
  hacía falta `nginx -s reopen`.
- **Lo guardado es de personas**, no del proyecto: `reportes/` está en
  `.gitignore`. Un reporte nunca lleva texto de un libro (`Reporter.sanitize`).
- La app encola el reporte en el teléfono y lo envía cuando el Mac responde, así
  que un fallo con el Mac apagado no se pierde.

## Que el teléfono llegue al Mac

El servidor escucha en todas las interfaces. La dirección va compilada en el APK
(`tools/release/voz.json`), y hoy es la de **Tailscale**
(`http://100.127.104.30:8765`), que es fija y sirve también fuera de casa. Las
dos opciones:

- **Misma WiFi:** `http://192.168.x.x:8765`. Funciona sin instalar nada, pero esa
  IP la reparte el router y puede cambiar: reservarla en el router, o recompilar.
- **Tailscale:** una IP `100.x` fija que además funciona fuera de casa. Hay que
  instalarlo en el Mac y en el teléfono con la misma cuenta.

Con token, cualquiera en la red que no lo conozca recibe `401`. Aun así, no es
un secreto: va dentro del APK en claro (ver
`tools/release/README.md`, "Lo que un APK no puede esconder").

## Prueba rápida

```bash
T=$(cat tools/mlx/.token)
curl -s -H "Authorization: Bearer $T" http://127.0.0.1:8765/health
curl -s -H "Authorization: Bearer $T" -H 'Content-Type: application/json' \
  -d '{"text":"Hola, esto es una prueba.","voice":"esposa","engine":"qwen3"}' \
  -o prueba.mp3 http://127.0.0.1:8765/tts
```

## Medido en el M3 Max

Párrafo de diálogo de ~330 caracteres: Qwen3 ~9 s (16,8 s de audio), Chatterbox
~7 s (14,2 s). El presupuesto de espera de la app es de 250 ms por carácter,
unas nueve veces eso (`TtsTimeouts` en `lib/tts/tts_endpoint.dart`).
