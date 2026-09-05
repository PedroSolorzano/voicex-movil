# Las descargas con Chatterbox fallan: no es el tamaño del texto, es el nodo intermitente

**Reportado:** `docs/bugs/REPORTES_TESTERS.md`, dos entradas del 2026-09-05
(pedro, La Odisea cap. 0, motor Chatterbox):

> Cuando descargo audios en la sección de descargas no me parece Chatterbox,
> hay que revisar esa parte. (20:32)

> Está fallando las descargas a Chatterbox. (20:34)

El diagnóstico adjunto a ambas es el mismo: cinco sondeos de `/api/model-info`
entre 14:29 y 14:31, uno `ok` (327ms) seguido de cuatro `unreachable` (5007ms,
8007ms, 5008ms, 8004ms).

Hipótesis inicial del usuario: los bloques de texto que se le mandan a
Chatterbox son demasiado grandes y eso lo hace fallar.

---

## Por qué el tamaño de bloque no encaja con el síntoma

Los tiempos de `unreachable` (5007/8007/5008/8004 ms) coinciden con exactitud
con los timeouts de **health check**, no de síntesis:
`TtsTimeouts.probe` = 5s y `probeRetry` = 8s (`tts_endpoint.dart:20,25`),
iguales para los tres motores remotos y cacheados 60s en éxito / 5s en fallo
(`server_health.dart:26-27`). El endpoint que falló es `GET /api/model-info`
— el sondeo de salud — no `/tts`, así que ningún párrafo estuvo involucrado en
esa ventana.

El tamaño del texto tampoco tiene por dónde afectar como se sospechaba:

- `ChatterboxTtsProvider` manda el párrafo completo en una sola petición
  (`chatterbox_tts_provider.dart:25`) y **no lo trocea del lado del
  cliente** — a diferencia de Kokoro y Piper, que sí re-trocean por oración a
  1800 caracteres (`kokoro_tts_provider.dart:18`, `piper_tts_provider.dart:17`).
  El troceado de Chatterbox lo hace el servidor externo (`split_text`, ~120
  caracteres con crossfade), así que no hay nada que hacer del lado de la app.
- `reader_provider.dart:downloadChapters` (líneas 1242-1364) trocea **por
  párrafo** (`para.rawText`, línea 1313) igual para los cuatro motores — no
  hay ninguna rama condicionada por `engine`.
- El timeout de síntesis de Chatterbox es de **240s**
  (`tts_endpoint.dart:39`), el más generoso de los tres (Kokoro 180s, Piper
  120s), justificado en el propio comentario por medir ~55-75s por párrafo.
  `docs/context/TTS_ESPANOL.md:63-67,235-236` confirma que la app sintetiza
  párrafo por párrafo (nunca el capítulo entero) y que ese patrón mantiene la
  VRAM acotada — nada ahí sugiere que el tamaño del bloque produzca error, el
  costo medido es tiempo, no fallo.

## Lo que sí explica el patrón

`docs/context/ACCESO_REMOTO.md:139-176` documenta que Chatterbox corre en una
laptop con GPU que entra a la tailnet como **nodo intermitente**, sin proxy y
sin token, y lo anticipa en el propio texto: *"cuando está apagada o dormida,
el sondeo de salud de la app... falla y el repliegue a Edge es automático y
silencioso"*. La secuencia observada — un `ok`, luego varios `unreachable`
seguidos y silencio — es indistinguible de la laptop reconectándose o
despertando en la tailnet en ese momento.

## Veredicto

La hipótesis de "bloques de texto muy grandes" **no explica este incidente
concreto**: el fallo fue del health check, un endpoint que ningún párrafo
toca. Es una preocupación válida en general —no hay límite de caracteres del
lado del cliente para Chatterbox— pero haría falta un párrafo
extraordinariamente largo (varias veces el promedio medido) para agotar los
240s de margen, y no hay evidencia de que eso ocurriera acá.

## Qué falta para confirmarlo

- Confirmar si la laptop (`voicex-laptop` / `g14` en la tailnet) estaba
  encendida y con Tailscale corriendo entre las 14:29 y 14:31 de ese día.
- El segundo reporte ("no me parece Chatterbox" en la pantalla de descargas)
  es un asunto de UI aparte, no diagnosticado acá: falta ver qué motor
  muestra esa pantalla cuando la descarga cae a Edge por health check
  fallido, y si el rótulo debería reflejar el repliegue.
