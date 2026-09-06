# Las descargas con Chatterbox fallan: no es el tamaño del texto, es el propio servidor bloqueándose al generar un párrafo largo

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

Descartada la hipótesis del nodo intermitente: el log del contenedor Docker
de Chatterbox en `g14` (`docker logs chatterbox-tts-server-cu130`) muestra que
nunca se reinició (`RestartCount: 0`, arriba desde antes del incidente) y
reconstruye el minuto a minuto exacto:

- **20:29:55 UTC** (14:29:55 local) llega una petición `/tts` real
  (`mode='clone'`), que el servidor trocea en 11 chunks internos —coincide
  con el `ok` de 327ms de las 14:29:53.
- El **chunk 2 de 11** tarda **70 segundos** en generarse (20:30:21→20:31:31
  UTC, `EOS token detected... step 637` — una secuencia larga).
- Los cuatro `unreachable` del diagnóstico (14:31:05, 14:31:14, 14:31:26,
  14:31:35 local = 20:31:05…20:31:35 UTC) caen **exactamente dentro de esa
  ventana de 70s**.
- El trabajo completo (11 chunks) tardó más de **4m37s**, superando
  `TtsTimeouts.synthesisChatterbox` (240s, `tts_endpoint.dart:39`): el
  cliente ya había abandonado ese párrafo, pero el servidor lo siguió
  cocinando de fondo —no hay evidencia de que cancele el trabajo al cortarse
  la conexión—, y eso bloqueó los health-checks de los párrafos siguientes de
  la misma descarga.

Chatterbox es un servidor de **un solo worker**: mientras la GPU está
generando audio no puede atender ninguna otra petición, ni siquiera su propio
endpoint de salud (`/api/model-info`). No hace falta una laptop dormida ni
una segunda acción concurrente para producir esta secuencia — `downloadChapters`
es un loop secuencial (`reader_provider.dart:1242`), así que un solo párrafo
lento dentro de la misma descarga basta para envenenar los health-checks de
los que siguen.

## Veredicto

La hipótesis de "bloques de texto muy grandes" **no explica este incidente**:
el fallo fue del health check, un endpoint que ningún párrafo toca, y lo que
alargó el trabajo no fue el tamaño del texto de entrada sino cuánto audio
decidió generar el modelo para el chunk 2 (step 637, una secuencia larga
frente a los ~100-200 steps típicos de los otros chunks del mismo párrafo) —
un comportamiento autoregresivo, no una función del largo del texto que
manda el cliente. Sigue sin haber límite de caracteres del lado del cliente
para Chatterbox, y sigue siendo una preocupación válida en general, pero el
mecanismo de este incidente es contención de un servidor de un solo worker,
no un bloque de texto desmedido.

## Confirmado

- El servidor **nunca estuvo caído ni reiniciado**: `RestartCount: 0`, uptime
  continuo verificado en el log del contenedor.
- La causa fue **contención de un solo worker**, no un nodo intermitente:
  mitigado en `lib/tts/server_health.dart` (`markServerBusy`/`_busyUntil`) y
  `lib/tts/chatterbox_tts_provider.dart` — al agotar `synthesisTimeout`, el
  cliente asume que el servidor seguirá ocupado un rato
  (`TtsTimeouts.busyCooldown`) y salta los health-checks de red durante ese
  margen en vez de reintentar cada ~13-18s y fallar igual, cascada abajo, en
  cada párrafo siguiente.
- **El párrafo abandonado no debería haberse abandonado.** Los 240s por
  defecto salen de medir ~55-75s por párrafo en otro hardware; en una GPU
  justa un párrafo tarda varias veces eso, y rendirse antes de tiempo tira a
  la basura una generación que el servidor sí completó. Durante una descarga
  el techo ahora se deriva de lo que esa máquina viene tardando de verdad
  (`TtsTimeouts.adaptiveSynthesis`: cinco veces el promedio medido, con suelo
  en los 240s de siempre y tope en 20 min), medido solo sobre párrafos de
  Chatterbox exitosos para que un tramo por Edge no baje el promedio. La
  lectura en vivo conserva el presupuesto fijo: ahí esperar minutos no sirve
  de nada, el repliegue rápido es lo correcto.
- El segundo reporte ("no me parece Chatterbox" en la pantalla de descargas)
  ya se arregló aparte: la barra de descarga ahora muestra un aviso explícito
  cuando el motor real difiere del elegido (`downloadEngineNotice`, commit
  `9e759d2`).

## Recurrencia tras el fix (2026-09-06)

El fix de arriba no evitó una recaída: dos reportes nuevos del mismo tester,
mismo libro (`docs/bugs/REPORTES_TESTERS.md`, 2026-09-06 01:33 y 01:44) —
*"volvió a fallar la descarga"* y *"me sale descarga incompleta, un párrafo
fallido... el fix que mandamos necesitamos afinarlo un poco más"*.

**El primer `unreachable` de esta recaída no lo pudo haber disparado el fix.**
El reporte de 01:33 tiene un `ok` a las 19:28:44 y el siguiente `unreachable`
a las 19:31:50 — solo 3m6s después, menos que el piso de 240s de
`TtsTimeouts.adaptiveSynthesis`. El `synthesize` de ese párrafo todavía no
podía haber agotado su propio timeout, así que `markServerBusy`
(`chatterbox_tts_provider.dart:93-97`) no se había disparado por ese camino
todavía. El `unreachable` viene de otro llamador:

- **`resetServerHealthCache()` (`server_health.dart:44-47`) borra
  `_busyUntil` junto con el caché de veredictos de red.** La función no
  distingue "lo que sé del servidor" (que sigue ocupado) de "lo que sé de mi
  propia conexión" (que cambió de red). Dos llamadores ajenos a la descarga
  la invocan sin condición:
  - `settings_screen.dart:83` — el botón "Probar conexión" en Ajustes. Un
    tester frustrado con una descarga fallando entra ahí a probar, y reabre
    la ventana que el fix acababa de cerrar contra un servidor que sigue
    ocupado.
  - `reader_provider.dart:298` — cada evento de
    `Connectivity().onConnectivityChanged` (Android puede emitir varios en
    una sola transición de red) limpia el caché y dispara
    `unawaited(maybePrefetchAhead())` (línea 299).
- **`maybePrefetchAhead` (`reader_provider.dart:1416-1458`) hace su propio
  `isReachable` (línea ~1441) sin guardia de reentrada propia** — solo mira
  `state.isDownloading`, que `downloadChapters` no puso todavía. El patrón
  del reporte 01:44 (19:36:37, 44, 45, 52 — unos 4-7s entre cada uno, cada
  uno con su reintento a 5s/8s) encaja mejor con **dos `probeServer`
  solapados** disparados por eventos de conectividad casi simultáneos que
  con un único loop reintentando.

`downloadChapters` no reintenta un párrafo fallido: incrementa
`downloadFailed` y sigue con el siguiente, dejando el mensaje "Descarga
incompleta: N párrafos fallaron" (`reader_provider.dart:1386-1391`) — coincide
con lo reportado.

**Veredicto de la recaída:** el fix funciona bien dentro de su propio loop de
descarga; lo que falta es que `_busyUntil` (conocimiento sobre el *servidor*)
deje de limpiarse junto con el caché de red (conocimiento sobre la *conexión
del cliente*).

**Ajuste concreto, sin implementar todavía:**
- Separar el reset en `server_health.dart:44-47`: que `resetServerHealthCache`
  siga limpiando el caché de veredictos, pero no `_busyUntil` — o exponer un
  reset aparte que los call sites de "Probar conexión"
  (`settings_screen.dart:83`) y de conectividad (`reader_provider.dart:298`)
  usen en su lugar.
- Darle a `maybePrefetchAhead` (`reader_provider.dart:1416`) una guardia de
  reentrada propia antes de su `isReachable`, no solo depender de
  `state.isDownloading`.
