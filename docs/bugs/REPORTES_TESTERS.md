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

