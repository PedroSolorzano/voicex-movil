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

- **F5-Spanish** y **VoicePoweredAI Spanish v1**: Apache 2.0 y entrenados en
  español de verdad —lo que se pedía—, pero son F5-TTS, que es difusión.
  Demasiado pesado para CPU, y en la 4050 competirían de igual a igual con
  Chatterbox, que puntúa mejor.
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

```bash
git clone https://github.com/PedroSolorzano/voicex-movil.git && cd voicex-movil

# Servidor con endpoints OpenAI-compatibles. Ojo con el modelo:
# el Multilingual (0.5B) es el que habla español, no el Turbo.
git clone https://github.com/devnen/Chatterbox-TTS-Server
cd Chatterbox-TTS-Server && pip install -r requirements.txt
# configurar el modelo multilingüe y arrancar según su README

curl -s -X POST http://localhost:8004/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d "{\"input\":\"$(cat ../muestras_voz/parrafo.txt)\",
       \"voice\":\"<voz o muestra clonada>\",\"response_format\":\"mp3\"}" \
  -o ../muestras_voz/ES-Chatterbox-multilingual.mp3
```

Mientras corre, anotar con `nvidia-smi`: **VRAM máxima usada** (¿entra en los
6 GB con un párrafo?) y **cuántos segundos tardó**.

### En el servidor, para comparar contra lo que ya hay

Los comandos de Kokoro y Piper están en `muestras_voz/LEEME.md`. Y si se prueba
la voz mexicana de Piper, hay que reconstruir la imagen con los args nuevos
antes de generar.

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
