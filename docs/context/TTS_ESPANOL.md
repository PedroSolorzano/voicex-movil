# VoiceX Móvil — Un motor de voz en español mejor que Piper

Piper entró como el motor rápido y sin internet, y cumple esa parte: sintetiza
a una fracción del tiempo real. Lo que no cumple es sonar bien en español, y
eso es lo que se pide reemplazar. Este documento compara lo que hay hoy
—septiembre de 2026— para hacer ese reemplazo.

**El resumen, por si no lees más:** hay dos escenarios distintos según en qué
máquina corra el motor. En el **servidor** (sin GPU utilizable) los candidatos
son tres modelos pequeños en CPU. En la **laptop con la RTX 4050** se abre
Chatterbox Multilingual, que es el que mejor puntúa en español. Nada de esto se
decide leyendo: se decide escuchando el mismo párrafo en cada uno, que es como
ya se eligió el motor la primera vez (`muestras_voz/`).

---

## Lo que condiciona la elección

**1. El servidor no tiene GPU; la laptop sí.** `voicex-server` —el i7-10700K
que corre Kokoro, Piper, el proxy y los cron— tiene una Radeon RX Vega 56/64
(`gfx900`), que AMD sacó de su matriz oficial de soporte de PyTorch/ROCm.
Compilar ROCm a mano para esa tarjeta es la clase de tarde perdida que este
proyecto ya decidió evitar con Oracle Cloud en
[`ACCESO_REMOTO.md`](ACCESO_REMOTO.md). La laptop, en cambio, tiene una **RTX
4050 de 6 GB**, y eso cambia qué modelos entran.

**2. La vara es Piper, no Kokoro.** Kokoro se queda: es Apache 2.0, va a ~5x
tiempo real en la CPU del servidor, y es **el único self-hosted que da marcas
por palabra** (`/dev/captioned_speech`), que es lo que permite subrayar la
palabra que suena. Lo que se busca es un reemplazo para el segundo puesto.

**3. WAV descalifica.** Piper devuelve WAV sin comprimir: 159 MB por hora, la
razón medida por la que nunca se le repartió a un probador
([`ACCESO_REMOTO.md`](ACCESO_REMOTO.md), consumo de datos). Un motor que solo
emita WAV repite el problema.

**4. Tiene que hablar HTTP.** La app habla con sus motores por HTTP a través
del proxy, con una lista blanca de rutas exactas
([`tools/proxy/nginx.conf`](../../tools/proxy/nginx.conf)). Un modelo que solo
traiga API de Python obliga a escribir el servidor: no descarta, pero suma
trabajo.

---

## Con GPU: Chatterbox Multilingual

Es el que mejor puntúa en español de todo lo que revisé (9-10/10 en las
comparativas), MIT, de Resemble AI. Tres cosas que hay que saber antes de
instalarlo:

**Hay que elegir el modelo correcto.** Son dos y confundirlos arruina la
prueba:

| Variante | Tamaño | Idiomas | VRAM |
|---|---|---|---|
| Chatterbox **Turbo** | 350M | **principalmente inglés** | 6 GB mínimo |
| Chatterbox **Multilingual** | 0.5B | 25, incluido español | más holgada con textos largos |

El liviano no habla español. **Para esto hace falta el Multilingual (0.5B).**

**6 GB está en el filo, pero el uso de esta app lo salva.** De la versión
multilingüe dicen que con textos largos agradece más VRAM. El caso que revienta
6 GB es meter un audiolibro entero en una sola petición — y esta app **no hace
eso**: `downloadChapters`
([`reader_provider.dart`](../../lib/ui/providers/reader_provider.dart))
sintetiza **párrafo por párrafo**, que es justo el patrón que mantiene la VRAM
acotada. Aun así, esto hay que confirmarlo midiendo, no asumiendo.

**La integración sería sorprendentemente barata.** El servidor de referencia
([devnen/Chatterbox-TTS-Server](https://github.com/devnen/Chatterbox-TTS-Server))
expone `/v1/audio/speech` y `/v1/audio/voices`: la **misma forma
OpenAI-compatible** que ya habla
[`kokoro_tts_provider.dart`](../../lib/tts/kokoro_tts_provider.dart) y que la
lista blanca del proxy ya contempla para Kokoro. Y saca **mp3/opus**, no solo
WAV — según la tabla medida de `ACCESO_REMOTO.md`, ~56-60 MB/h contra los 159
de Piper.

Lo que **no** da son marcas por palabra. Reemplazaría a Piper, no a Kokoro.

### Dónde correrlo, si gana

La laptop es mal servidor 24/7: se cierra, se duerme, anda con batería. Tres
salidas, en orden de menos a más invasivo:

1. **Solo para generar por adelantado.** La app ya tiene *Descargar → este
   capítulo / los próximos / libro completo*, y lo descargado queda anclado
   (`pinned`: ni la evicción LRU ni la purga de 5 días lo tocan). La laptop
   solo necesita estar encendida **cuando generás**, no cuando escuchás. Cero
   cambios de red.
2. **Segundo nodo de la tailnet.** El proxy le rutea `/chatterbox`. Funciona en
   vivo, pero solo mientras la laptop esté despierta; si duerme, la app se
   repliega a Edge en silencio.
3. **Mudar todo el stack a la laptop.** Un solo servidor, con GPU, pero la
   laptop queda de servidor permanente.

La (1) es la que aprovecha lo que ya está construido. Se decide después de
escuchar, no antes.

---

## Sin GPU: los tres que corren en CPU

Por si el veredicto es que Chatterbox no compensa el enredo de la laptop.

| Candidato | Licencia | Español | En CPU | Servidor HTTP |
|---|---|---|---|---|
| **Pocket TTS** (Kyutai) | MIT | sí, desde v2.0.0 (abril 2026) | ~6x tiempo real **con 2 núcleos** en un M4 | sí, `serve` en `:8000` |
| **Audio8 TTS 0.1B** | Apache 2.0 | sí, entre 11 idiomas | ONNX INT8, ~100M | sí, **compatible con OpenAI** |
| **Supertonic 3** | código MIT, **pesos OpenRAIL-M** | sí, entre 31 idiomas | ~99M en ONNX; dicen 2-3x Kokoro | por ONNX Runtime |
| MeloTTS-Spanish | MIT | dedicado, **acento de España** | tiempo real | no: API de Python |

Pocket TTS y Audio8 **clonan voz** desde una muestra corta: el acento lo eliges
tú en vez de conformarte con el que traiga el modelo. Ninguno de los cuatro da
marcas por palabra.

---

## Lo que quedó fuera

- ~~**F5-Spanish** y **VoicePoweredAI Spanish v1**: Apache 2.0 y entrenados en
  español de verdad —lo que se pedía—, pero son F5-TTS, que es difusión.
  Demasiado pesado para CPU, y en la 4050 competirían de igual a igual con
  Chatterbox, que puntúa mejor.~~

  **Descartado por una premisa equivocada, y corregido en 0.8.0.** Lo de
  "demasiado pesado para CPU" era cierto; lo de competir de igual a igual en
  la 4050, no, y por más de un orden de magnitud. F5 **no es autoregresivo**:
  genera todo el audio en un número fijo de pasos en paralelo, en vez de token
  por token como Chatterbox. Medido en la misma tarjeta: Chatterbox 0.089x
  tiempo real, F5-Spanish 1.26x. Veintisiete veces más rápido, calidad pareja
  al oído y licencia CC0. Es el motor que quedó
  ([`tools/f5/README.md`](../../tools/f5/README.md)).

  La lección para la próxima comparativa: **el throughput es criterio de
  primera clase, no un detalle a mirar después**. Esta tabla ordenó los
  candidatos por calidad de voz y dejó la velocidad como nota al pie, y por
  eso el ganador tardó tres semanas en revelarse inservible para leer un
  libro.
- **XTTS-v2** (Coqui): licencia CPML, **prohíbe el uso comercial**, o sea que
  no es de uso libre. Y Coqui cerró: nadie lo mantiene.
- **CosyVoice2**, **Orpheus** (3B sobre Llama), **IndexTTS-2**: no entran en
  6 GB con holgura, y no puntúan mejor que Chatterbox en español.

---

## Antes de todo esto: la voz de Piper

El servidor de Piper **trae las voces compiladas dentro de la imagen**, como
argumentos de construcción
([`tools/piper/docker-compose.yml`](../../tools/piper/docker-compose.yml)):

```yaml
args:
  VOICE_ES: es_AR-daniela-high
  VOICE_ES_PATH: es/es_AR/daniela/high
```

O sea que la voz que se está juzgando es **una sola, argentina**, mientras el
resto de la app usa mexicano (`es-MX-DaliaNeural`). El catálogo tiene
**`es_MX-claude-high`** (`es/es_MX/claude/high`, verificado en
[rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices/tree/main/es/es_MX)),
descrita como latinoamericano neutro.

Cuesta editar esos dos argumentos, reconstruir la imagen y ajustar
`piperVoiceEs` ([`lib/config/settings.dart`](../../lib/config/settings.dart)).
Vale la pena antes de montar nada: en agosto, daniela era **la preferida para
el día a día** (`muestras_voz/LEEME.md`); si la opinión cambió después de
convivir con ella, conviene saber si el problema es el modelo o el acento.

---

## Cómo probar — el procedimiento

Mismo método que en agosto: **el mismo párrafo, en todos los motores**, y se
escucha. El texto es `muestras_voz/parrafo.txt`, un pasaje de *El Instituto*
con diálogo y narración larga, que es lo que más estresa la expresividad. Las
muestras nuevas van a esa misma carpeta (que **no está en git**, son audios
locales) con el mismo criterio de nombre: `ES-<Motor>-<voz>.<ext>`.

**Referencia rápida:** un párrafo español bien leído dura **~26 s**. Si sale en
~17 s, se está pronunciando con reglas inglesas.

**El párrafo**, incrustado acá porque `muestras_voz/` está en `.gitignore` y
clonar el repo en otra máquina no lo trae:

> —No lo sé —contestó Tim, aunque sí lo sabía; un antiguo compañero suyo de la
> policía le había contado que en la Gran Manzana abundaba el trabajo en el
> sector de la seguridad privada, incluidas algunas empresas que concederían más
> valor a su experiencia que a la absurda cagada que había puesto fin a su
> carrera policial en Florida—. Solo espero llegar a Georgia esta noche. Quizá
> me guste más aquello.

### En la laptop, para Chatterbox

Ya probado en la laptop con la RTX 4050 (septiembre 2026). La vía que
funciona en Windows con GPU es Docker, no el `pip install` manual: este
último pide **Python 3.10** (3.11+ no tiene wheels precompiladas), mientras
que la imagen Docker se lleva ese problema puesto. El repo trae un
`docker-compose-cuNNN.yml` por versión de CUDA; el que corresponde al driver
de cada máquina se ve con `nvidia-smi` (esta laptop: driver 581.80, CUDA
13.0 → `docker-compose-cu130.yml`).

```bash
git clone https://github.com/devnen/Chatterbox-TTS-Server
cd Chatterbox-TTS-Server
```

Dos archivos hay que tocar antes de levantarlo:

- **`config.yaml`**: `model.repo_id` viene en `chatterbox-turbo` (inglés) por
  defecto — cambiarlo a `chatterbox-multilingual`. De paso,
  `generation_defaults.language` viene en `en`; ponerlo en `es` como default
  (se puede igual pisar por request).
- **`.env`** (no lo trae el repo, hay que crearlo — el compose lo referencia
  con `env_file: .env`): `HF_TOKEN=` (vacío alcanza, los modelos de
  Chatterbox son públicos) y `TTS_BF16=on` (~40 % más rápido en GPUs
  bf16-capaces, que incluye la serie RTX 30/40).

```bash
docker compose -f docker-compose-cu130.yml up -d --build
```

**El endpoint que hay que pedirle no es `/v1/audio/speech`.** Ese, el
OpenAI-compatible, solo devuelve `wav` u `opus` y no tiene forma de fijar el
idioma — con el modelo multilingüe eso es una moneda al aire entre español e
inglés. El que sirve es el endpoint propio, `/tts`, que sí acepta
`output_format: mp3` y `language: es`:

```bash
curl -s -X POST http://localhost:8004/tts \
  -H "Content-Type: application/json" \
  -d "{\"text\":\"$(cat ../muestras_voz/parrafo.txt)\",
       \"language\":\"es\",\"output_format\":\"mp3\",
       \"voice_mode\":\"predefined\",\"predefined_voice_id\":\"Emily.wav\"}" \
  -o ../muestras_voz/ES-Chatterbox-multilingual.mp3
```

(`Emily.wav` es una de las voces predefinidas que trae el repo en `voices/`;
son solo el timbre de referencia para el clonado zero-shot, cualquiera sirve
de punto de partida — el idioma lo decide el campo `language`, no la voz.)

Mientras corre, anotar con `nvidia-smi`: **VRAM máxima usada** (¿entra en los
6 GB con un párrafo?) y **cuántos segundos tardó**.

**Resultados medidos en esta laptop** (RTX 4050, `chatterbox-multilingual`,
`TTS_BF16=on`, voz `Emily.wav`, sin clonado):

| Métrica | Valor |
|---|---|
| VRAM pico | ~3,6–3,8 GB (holgado dentro de los 6 GB — confirma lo que el doc asumía sobre sintetizar párrafo por párrafo) |
| Tiempo de síntesis | ~55 s para un párrafo cuyo audio dura ~25 s — **más lento que tiempo real** (factor ~2,2x), a diferencia de Kokoro y Piper, que van varias veces más rápido que tiempo real |
| Duración del audio | 24,8–25,1 s (español correcto; la referencia de mala pronunciación inglesa serían ~17 s) |
| Peso | ~14,3 MB/hora en mp3 — menos que Kokoro (~42 MB/h) y muy por debajo de Piper (~159 MB/h) |

El costo de este motor no es la VRAM ni el peso —los dos le sobran— sino el
**tiempo**: 55 s de espera por párrafo descarta generar sobre la marcha
mientras se escucha, y confirma que si este motor gana, la única opción
razonable de las tres que propone este documento es la (1): generar por
adelantado con la laptop prendida, nunca en vivo.

### Para comparar contra lo que ya hay

No hace falta tocar `voicex-server`: Kokoro y Piper corren en CPU, así que
para la comparación alcanza con levantarlos también en la máquina de la
prueba con lo que ya trae el repo:

```bash
docker compose -f tools/kokoro/docker-compose.yml up -d
docker compose -f tools/piper/docker-compose.yml up -d --build
```

Kokoro necesita el `lang_code` explícito (ver comentario en
[`kokoro_tts_provider.dart`](../../lib/tts/kokoro_tts_provider.dart)) o
también le sale la pronunciación inglesa:

```bash
curl -s -X POST http://localhost:8880/dev/captioned_speech \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"kokoro\",\"input\":\"$(cat ../muestras_voz/parrafo.txt)\",
       \"voice\":\"ef_dora\",\"response_format\":\"aac\",\"speed\":1.0,
       \"lang_code\":\"e\",\"stream\":false,\"return_timestamps\":false}" \
  | python -c "import json,sys,base64; open('../muestras_voz/ES-Kokoro-ef_dora.aac','wb').write(base64.b64decode(json.load(sys.stdin)['audio']))"

curl -s -X POST http://localhost:5000/synthesize \
  -H "Content-Type: application/json" \
  -d "{\"text\":\"$(cat ../muestras_voz/parrafo.txt)\",\"voice\":\"\"}" \
  -o ../muestras_voz/ES-Piper-es_AR-daniela.wav
```

Si se prueba la voz mexicana de Piper, no hace falta pisar el
`docker-compose.yml` versionado (eso cambiaría la voz por defecto de toda la
app): alcanza con un build puntual con otro `--build-arg` y otro puerto,
tirar el contenedor al terminar.

**Resultados medidos en esta laptop:**

| Motor / voz | Síntesis | Audio | Peso |
|---|---|---|---|
| Kokoro `ef_dora` | ~11 s | ~23,6 s | ~42 MB/h |
| Piper `es_AR-daniela-high` (la actual) | ~7 s | 18,5 s | ~159 MB/h |
| Piper `es_MX-claude-high` | ~3 s | 26,6 s | ~159 MB/h |

`es_AR-daniela` lee rápido —18,5 s no es un fallo de idioma, es su ritmo
natural, ya conocido (`tools/piper/README.md`)—. La duración de `es_MX-claude`
sí queda dentro de la referencia de ~26 s, pero esa voz **ya se había
descartado antes** por errores de lectura
([`tools/piper/README.md`](../../tools/piper/README.md)): esta muestra nueva
es para volver a confirmarlo escuchando, no para partir de cero.

### Qué anotar de cada candidato

Tres cosas, medidas en la máquina que lo va a correr, no estimadas:

1. **Cómo suena**, escuchado **en el teléfono** y no en los parlantes de la
   computadora: es donde se va a usar, y el altavoz del teléfono perdona menos.
2. **Segundos de síntesis por párrafo**, contra los ~4,9 s de Kokoro que ya
   están medidos.
3. **MB por hora de audio**, con la misma vara que la tabla de formatos de
   [`ACCESO_REMOTO.md`](ACCESO_REMOTO.md).

Y un resultado que también es válido, y hay que estar dispuesto a aceptarlo:
que ninguno le gane a Kokoro y no valga la pena el enredo. En ese caso se
retira Piper y quedan Kokoro y Edge — una app con una pieza menos que explicar
y mantener.
