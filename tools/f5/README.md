# Servidor de voz F5-TTS en español

Reemplaza a Chatterbox. La razón no es la calidad —quedaron parejos al oído—
sino la velocidad: Chatterbox va a **0.089x tiempo real** en la RTX 4050, o sea
~2.9 horas de GPU por capítulo, mientras F5 va por encima de tiempo real.

La diferencia es arquitectónica, no de ajuste: Chatterbox es autoregresivo y
genera token por token; F5 usa flow matching sobre un Diffusion Transformer y
genera en un número fijo de pasos en paralelo.

```bash
docker compose -f tools/f5/docker-compose.yml up -d --build
```

Arranca en ~3 minutos la primera vez, porque baja el checkpoint (~1,3 GB).

## Las voces

Cada voz son **dos archivos** en `voices/`:

```
voices/esposa.wav   la grabación de referencia
voices/esposa.txt   la transcripción exacta de esa grabación
```

El `.txt` no es opcional: F5 alinea la voz contra su texto. Dejarlo vacío
obliga al modelo a transcribir con un ASR, que gasta VRAM y sale peor que
escribir a mano lo que dice el audio.

**La referencia se recorta a 12 segundos** (`utils_infer.py`, F5 corta ahí
siempre), así que grabar más no aporta. Y hay dos cosas que se heredan de esa
grabación y conviene saber antes de grabar:

- **La calidad del audio se reproduce.** Una grabación con ruido da una voz
  con ruido. La original tenía 18 dB de SNR y zumbido de 60 Hz; regrabada con
  el teléfono a batería y a 15 cm del micrófono llegó a 34 dB.
- **El ritmo de la referencia fija el ritmo de todo lo generado.** La misma
  persona leyendo más lento dio 42 s contra 32 s para el mismo párrafo.

## Sustituciones de pronunciación

`voices/sustituciones.json` corrige palabras que **este modelo** pronuncia mal
en cualquier texto:

```json
{ "quizá": "kizá", "quizás": "kizás" }
```

Sin eso, "quizá" suena "guizás". No es sistemático de la "qu" —probado con
pares mínimos *quiso/guiso* y *quita/guita*, el resto sale bien—, son palabras
sueltas y la lista es corta: pasado un corpus de 378 palabras de prosa real no
apareció ningún otro error en español.

**Los nombres propios de cada libro no van acá.** `Jack Sawyer` sale "jakq
sayer" y mejora escrito `Yac Sóyer`, pero eso depende del libro y no del
motor; este archivo es solo para defectos del checkpoint.

## La API

| Ruta | Qué hace |
|---|---|
| `GET /health` | Sondeo barato. No toca la GPU. |
| `POST /tts` | `{"text", "voice", "speed", "nfe_step"}` → MP3 |

`/health` **sigue contestando en milisegundos con una síntesis en curso**
(medido: 4-9 ms mientras la GPU trabajaba 25 s). No es un detalle: Chatterbox
compartía el hilo entre síntesis y sondeo, así que un párrafo largo bloqueaba
su propio endpoint de salud y la app lo leía como servidor caído —el bug de
[`docs/bugs/CHATTERBOX_DESCARGAS.md`](../../docs/bugs/CHATTERBOX_DESCARGAS.md).
Acá `/tts` es una función sincrónica, así que FastAPI la corre en otro hilo y
el bucle de eventos queda libre.

La GPU se serializa con un lock: dos síntesis a la vez no van más rápido, solo
compiten por VRAM en una tarjeta de 6 GB.

## `nfe_step` 64, no 32

F5 trae 32 pasos por defecto. Con ese valor aparecen tartamudeos y
repeticiones —"trabajo" sale "trabajo abajo"—, verificado transcribiendo la
salida y comparándola con el texto pedido. A 64 la lectura sale al 100 % y
sigue por encima de tiempo real. Cuesta la mitad de velocidad y vale la pena.

## Rendimiento medido (RTX 4050 Laptop, 6 GB)

| Texto | Audio | Proceso | Velocidad |
|---|---|---|---|
| Un párrafo | 29,1 s | 23 s | 1,26x |
| 378 palabras | 175 s | 291 s | 0,60x |

La caída con texto largo es por el troceo: F5 tiene una ventana de 22
segundos y **la referencia se la come**. Con una referencia de 11 s quedan
~124 caracteres por lote; con una de 5 s, ~186. Menos lotes es menos
sobrecarga, así que una referencia más corta acelera los textos largos.
