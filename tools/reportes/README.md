# Pipeline de reportes de testers

`tools/mlx/reportes/reportes.jsonl` es donde caen los reportes que manda la
app ("Contar un problema"): `tools/mlx/server.py` los recibe por `POST /report`
y las notas de voz por `PUT /report/audio/<id>.m4a`. Este pipeline los lee,
transcribe la nota de voz si trae una, y los vuelca a los documentos del repo.

```
procesar.sh ──► procesar.py
                   │
                   ├─ renombra reportes.jsonl (el servidor crea otro al siguiente reporte)
                   ├─ transcribe con mlx-whisper, local, en la GPU del Mac
                   ├─ docs/bugs/REPORTES_TESTERS.md      (bug, crash)
                   └─ docs/tasks/IMPROVEMENTS.md         (mejora, sección "Sin triar")
```

**La transcripción es local, siempre.** Nunca se manda una nota de voz a un
servicio en la nube -- sería mandar la voz de una persona a un tercero, y
todo el resto del proyecto (`Reporter`, el servidor) está diseñado para que eso
no pase. `mlx-whisper` corre en este mismo Mac, con el mismo modelo que ya usa
el banco de pruebas de voces: transcribe una nota de ~8 s en ~2 s.

## Arranque

```bash
cd tools/reportes
uv venv --python 3.12 .venv            # no el python3 del sistema: mlx no publica ruedas para versiones tan nuevas
uv pip install --python .venv/bin/python -r requirements.txt
```

El modelo (`mlx-community/whisper-large-v3-turbo`, 1,6 GB) se descarga la primera
vez que se transcribe una nota, o ya está si corriste antes las pruebas de voces.

Probar contra el backlog real sin escribir nada:

```bash
.venv/bin/python3 procesar.py --dry-run
```

Los reportes mandados antes de que el cuerpo llevara el campo `nota` (ver
`lib/services/reporter.dart`) no tienen forma de decir qué audio les
corresponde. Para esos, una sola vez, a mano:

```bash
.venv/bin/python3 procesar.py --dry-run --correlacionar-por-cercania   # revisar primero
.venv/bin/python3 procesar.py --correlacionar-por-cercania             # y recién, sin --dry-run
```

Esto nunca va en la línea de cron: correlacionar por cercanía de horario
puede equivocarse de reporte si dos llegan casi juntos.

## Cuándo correrlo

A mano, cuando quieras revisar lo que llegó:

```bash
tools/reportes/procesar.sh --dry-run    # ver qué haría, sin escribir nada
tools/reportes/procesar.sh              # volcarlo a los documentos
```

Un reporte es un acto humano y llegan pocos, así que no hace falta un cron. Si
algún día lo quieres automático, `launchd` en el Mac hace lo mismo que cron.
El script usa un directorio como candado (`estado/.lock.d`) y no `flock`, que
macOS no trae: así dos corridas no se superponen si una transcripción se alarga.

## Qué hace con cada reporte

- Si el `tipo` es `mejora`: una línea nueva en la sección **"Sin triar
  (reportado por testers)"** de `docs/tasks/IMPROVEMENTS.md`. Sin prioridad
  asignada a propósito -- ni el tester ni el script pueden decidir eso.
  Triar significa reescribirla con el formato estándar del archivo y
  borrarla de ahí.
- Cualquier otro `tipo` (`bug`, `crash`): una entrada nueva en
  `docs/bugs/REPORTES_TESTERS.md`, que es un volcado crudo, no una
  investigación -- distinto de algo como `EDGE_TTS_DEBUG.md`.
- Si hay nota de voz, se transcribe y se agrega a la entrada, y **la nota se
  borra del servidor** una vez transcrita: una nota de voz es la voz de una
  persona, y no tiene por qué quedarse en disco una vez que se actuó sobre ella.
- El script solo hace `git add` de los dos documentos que tocó. Nunca
  `git commit` -- eso lo sigue haciendo la persona, como el resto del repo.

## Qué build ya incluye qué arreglo

`versiones.jsonl` es un ledger chico, versionado en git (a diferencia de
`estado/`, que es datos de esta máquina): una línea por arreglo o feature que
le importa a un tester, con el número de build en que salió.

```json
{"build": 65, "commit": "ddc3517", "fecha": "2026-09-03", "tag": "capitulo-siguiente", "resumen": "Botones de saltar capítulo en el lector, en vez de pasar por el índice"}
```

`build` sale de `git rev-list --count <commit>` -- el mismo número que usa
`versionCode` (`android/app/build.gradle.kts`), así que compara directo
contra el `app` que manda cada reporte (`reporter.dart`, `X-Voicex-Client`).
Se completa a mano, junto con `RELEASES.md`, cuando algo se arregla.

Cada reporte nuevo se compara contra el ledger por solape de palabras
(`buscar_coincidencias` en `procesar.py`) y, si hay coincidencia, la entrada
sale con una nota:

- **Build igual o posterior al del arreglo:** "⚠️ Posible duplicado" -- puede
  ser el mismo bug reportado de nuevo por alguien con una versión ya
  parchada.
- **Build anterior:** "ℹ️ build anterior a..." -- a esa persona ese arreglo
  todavía no le había llegado.

Es una nota, nunca una decisión: comparar números de build es mecánico y
confiable, decidir si es el mismo bug no, así que sigue haciendo falta
mirarlo. El solape de palabras es deliberadamente simple (sin acentos, sin
conectores, mínimo dos palabras en común) -- prefiere un falso positivo
ocasional (una nota de más, fácil de ignorar) a uno negativo (un duplicado
real sin avisar).

## Si algo falla

Un reporte que no se puede parsear (o cuya transcripción falla) no tumba el
lote entero: queda en `logs/fallidos.jsonl` con el error y la línea cruda, y
se reintenta automáticamente en la próxima corrida sin bloquear a los demás.

`logs/procesar.log` tiene una línea por cada acción real (rotación,
transcripción, escritura en los docs). Si lo corres desde cron o `launchd`, su salida
cruda sirve para lo que pase antes de que el script llegue a loguear algo (por
ejemplo, si el venv no existe).

## Retención

- `tools/mlx/reportes/procesados/`: el lote crudo que ya se volcó a los docs,
  archivado por si hace falta reprocesar tras un bug del script. **3 días**
  -- ni 0 (para poder corregir un error del pipeline sin perder el reporte
  original) ni mucho más (es texto de una persona, no telemetría).
- `tools/reportes/estado/procesados.jsonl`: el ledger de qué reportes ya se
  volcaron (por hash de la línea cruda). No caduca -- es lo que evita
  duplicar una entrada si el pipeline corre dos veces sobre el mismo lote.
