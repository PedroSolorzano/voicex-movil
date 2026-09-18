# Reportes crudos de probadores

Volcado automático de `tools/proxy/logs/reportes.jsonl` por
`tools/reportes/procesar.py`, que corre solo desde el cron del host (ver
`tools/reportes/README.md`). Se añade al final, nunca se edita ni se
reordena a mano. Si algo de aquí se convierte en una investigación de
verdad, esa investigación vive en su propio archivo de `docs/bugs/` y
referencia esta entrada, no al revés.

---

## 2026-09-03 04:11 — bug — pedro

**Contexto:** kokoro

> la voz se corta al bloquear la pantalla

**Diagnóstico:**
- 21:35 /kokoro/health ok 210ms

---

## 2026-09-03 14:29 — bug — pedro

**Contexto:** El talismán, capítulo 11, Edge

> No funciona el tts nativo de Android o Samsung

---

## 2026-09-03 21:31 — bug — spiny

**Contexto:** Alice's Adventures in Wonderland, capítulo 1, Teléfono

> Nomse que onda con la velocidad cuando iso la voz "Teléfono"

**Diagnóstico:**
- 15:25:43  /kokoro/health  ok  692ms
- 15:24:41  /kokoro/health  ok  533ms
- 15:23:36  /kokoro/health  ok  508ms
- 15:22:26  /kokoro/health  ok  507ms
- 15:21:24  /kokoro/health  ok  1549ms

---

## 2026-09-03 21:40 — bug — spiny

**Contexto:** Don Quijote, capítulo 0, Teléfono

**Nota de voz transcrita:**

> mire usted que no me funcionan los previos de las voces solo me funcionó como 10 veces y después los de mañana

**Diagnóstico:**
- 15:35:00  /kokoro/health  ok  2304ms
- 15:25:43  /kokoro/health  ok  692ms
- 15:24:41  /kokoro/health  ok  533ms
- 15:23:36  /kokoro/health  ok  508ms
- 15:22:26  /kokoro/health  ok  507ms
- 15:21:24  /kokoro/health  ok  1549ms

---

## 2026-09-05 20:32 — bug — pedro

**Contexto:** La Odisea, capítulo 0, Chatterbox

> Cuando descargo audios en la seccion de descargas no me Parece chatterbox hay que revisar esa parte.

**Diagnóstico:**
- 14:31:35  /api/model-info  unreachable  8007ms (intento 2)
- 14:31:26  /api/model-info  unreachable  5007ms
- 14:31:14  /api/model-info  unreachable  8004ms (intento 2)
- 14:31:05  /api/model-info  unreachable  5008ms
- 14:29:53  /api/model-info  ok  327ms

---

## 2026-09-05 20:34 — bug — pedro

**Contexto:** La Odisea, capítulo 0, Chatterbox

> Esta fallando las descargas a chatterbox

**Diagnóstico:**
- 14:31:35  /api/model-info  unreachable  8007ms (intento 2)
- 14:31:26  /api/model-info  unreachable  5007ms
- 14:31:14  /api/model-info  unreachable  8004ms (intento 2)
- 14:31:05  /api/model-info  unreachable  5008ms
- 14:29:53  /api/model-info  ok  327ms

---

## 2026-09-06 01:33 — bug — pedro

**Contexto:** La Odisea, capítulo 0

> Volvio a fallar la descarga de la odisea, documentos la información para validarla con el celular y poder diagnosticar que pudo pasar

**Diagnóstico:**
- 19:32:21  /api/model-info  unreachable  8006ms (intento 2)
- 19:31:50  /api/model-info  unreachable  5001ms
- 19:28:44  /api/model-info  ok  309ms

---

## 2026-09-06 01:44 — bug — pedro

**Contexto:** La Odisea, capítulo 0

> Me sale descarga incompleta un parrafo fallido. He hecho varios intentos creo que el fix que mamdamos necesitamos afinarlo un poco mas.

**Diagnóstico:**
- 19:38:15  /api/model-info  ok  182ms
- 19:36:52  /api/model-info  unreachable  8001ms (intento 2)
- 19:36:45  /api/model-info  unreachable  8001ms (intento 2)
- 19:36:44  /api/model-info  unreachable  5002ms
- 19:36:37  /api/model-info  unreachable  5001ms

---

## 2026-09-06 17:46 — bug — pedro

**Contexto:** El talismán, capítulo 10, Edge (F5 no disponible)

> Identifique posible bug, descargué todo el capitulo era alrededor de 100 parrafos, se tardo un tiempo aceptable no mostro ningún error sin embargo cuando me dispongo a escuchar me grnera la voz de edge, me sale 104 párrafos descargados peroe sale solo 9 megas aproximadamente, no me hace sentido esos… (recortado)

**Diagnóstico:**
- 11:42:06  /health  unreachable  8001ms (intento 2)
- 11:41:58  /health  unreachable  5002ms
- 11:41:31  /health  unreachable  8003ms (intento 2)
- 11:41:23  /health  unreachable  5003ms
- 11:41:12  /health  unreachable  8002ms (intento 2)
- 11:41:04  /health  unreachable  5002ms
- 11:40:53  /health  unreachable  8001ms (intento 2)
- 11:40:44  /health  unreachable  5001ms

---

## 2026-09-18 17:24 — crash — pedro

**Error:** \_TypeError

**Traza:** \#0 StatefulElement.state (package:flutter/src/widgets/framework.dart:5951) \| \#1 Navigator.of (package:flutter/src/widgets/navigator.dart:2949) \| \#2 showDialog (package:flutter/src/material/dialog.dart:1642) \| \#3 \_ReaderScreenState.\_editBookmarkNote (package:voicex\_movil/ui/screens/reader\_screen.dart… (recortado)

---

## 2026-09-18 17:24 — bug — pedro

⚠️ **Posible duplicado:** este build (135) ya incluye «El motor de voz del teléfono no generaba audio en Android 11 o superior» (build 63, commit `18410b9`). Revisar si es el mismo caso antes de investigar de cero.

**Contexto:** El talismán, capítulo 14, Edge

**Nota de voz transcrita:**

> ahorita le furí que cuando estoy escuchando audiencia real, o sea que no le ha bajado y termina un párrafo, no me carga si el teléfono está apagado, no me carga y tengo que encender la pantalla, se mira que el botoncita está con moda con el símbolo de carga y ya después se pone pero si no desbloquea el teléfono, si el audio no empieza queda como en ese limpo, como detenido por alguna razón

---

## 2026-09-18 17:31 — bug — pedro

⚠️ **Posible duplicado:** este build (150) ya incluye «Botones de saltar capítulo en el lector, en vez de pasar por el índice» (build 65, commit `ddc3517`). Revisar si es el mismo caso antes de investigar de cero.

**Contexto:** Project Hail Mary, capítulo 2, Kokoro

**Nota de voz transcrita:**

> Estoy descargando con Cocoro un capítulo del libro Project Hail Mary y me está descargando todos los capítulos. Pero miren que hice 51 errores fallidos. Yo apague la pantalla, no sé si tal vez eso hizo que dejará de descargar cuando apago la pantalla. Mientras tengo encendido se miren que sí, descargando todo bien.

**Diagnóstico:**
- 11:30:57 /kokoro/health ok 215ms
- 11:29:52 /kokoro/health ok 1425ms (intento 2)
- 11:29:50 /kokoro/health unreachable 5001ms
- 11:29:23 /kokoro/health unreachable 8002ms (intento 2)
- 11:29:15 /kokoro/health unreachable 5002ms
- 11:27:38 /kokoro/health ok 259ms
- 11:26:36 /kokoro/health ok 166ms
- 11:25:35 /kokoro/health ok 235ms

---

## 2026-09-18 18:02 — crash — pedro

**Error:** \_TypeError

**Traza:** \#0 StatefulElement.state (package:flutter/src/widgets/framework.dart:5951) \| \#1 Navigator.of (package:flutter/src/widgets/navigator.dart:2949) \| \#2 showDialog (package:flutter/src/material/dialog.dart:1642) \| \#3 \_ReaderScreenState.\_editBookmarkNote (package:voicex\_movil/ui/screens/reader\_screen.dart… (recortado)

**Diagnóstico:**
- 11:36:52 /kokoro/health unreachable 8002ms (intento 2)
- 11:36:00 /kokoro/health unreachable 5001ms
- 11:35:40 /kokoro/health unreachable 8003ms (intento 2)
- 11:34:20 /kokoro/health unreachable 5004ms
- 11:33:02 /kokoro/health ok 154ms
- 11:32:00 /kokoro/health ok 235ms
- 11:30:57 /kokoro/health ok 215ms
- 11:29:52 /kokoro/health ok 1425ms (intento 2)

---

## 2026-09-18 18:55 — bug — spiny

**Contexto:** capítulo 0

> Hay muchos settings en una sola View. Señores developers por favor denme un menu para mejor organización

**Diagnóstico:**
- 12:53:11 /kokoro/health ok 1264ms

---

