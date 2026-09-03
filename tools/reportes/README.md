# Pipeline de reportes de testers

`tools/proxy/logs/reportes.jsonl` es donde caen los reportes de los testers
(ver `tools/proxy/README.md`). Este pipeline los lee, transcribe la nota de
voz si trae una, y los vuelca a los documentos del repo -- sin que nadie lo
dispare a mano.

```
cron (cada 15 min) ──► procesar.sh ──► procesar.py
                                          │
                                          ├─ nginx -s reopen (rota reportes.jsonl)
                                          ├─ transcribe con faster-whisper, local
                                          ├─ docs/bugs/REPORTES_TESTERS.md      (bug, crash)
                                          └─ docs/tasks/IMPROVEMENTS.md         (mejora, sección "Sin triar")
```

**La transcripción es local, siempre.** Nunca se manda una nota de voz a un
servicio en la nube -- sería mandar la voz de una persona a un tercero, y
todo el resto del proyecto (proxy, `Reporter`) está diseñado para que eso no
pase. `faster-whisper` corre en este mismo host, el que ya tiene Kokoro y
Piper.

## Arranque

```bash
cd tools/reportes
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Precalentar el modelo antes de activar el cron, para que la primera corrida
automática no sea la que descarga el modelo (~500 MB, modelo `small`)
mientras se supone que atiende reportes:

```bash
.venv/bin/python3 -c "from faster_whisper import WhisperModel; WhisperModel('small', device='cpu', compute_type='int8')"
```

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

## Cron

```cron
*/15 * * * * PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin /home/pedro/Repos/Personales/VoiceXMovil/tools/reportes/procesar.sh >> /home/pedro/Repos/Personales/VoiceXMovil/tools/reportes/logs/cron.log 2>&1
```

`PATH` explícito porque cron no carga el del shell interactivo, y el script
necesita `docker` y `git` en el camino. El venv se invoca por ruta absoluta,
así que no hace falta activarlo. `flock` en `procesar.sh` evita que dos
corridas se superpongan si una transcripción tarda más que el intervalo.

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
  borra del servidor** una vez transcrita: es la misma regla que ya
  describe `tools/proxy/README.md` ("las notas de voz se borran en cuanto
  se ha actuado sobre ellas").
- El script solo hace `git add` de los dos documentos que tocó. Nunca
  `git commit` -- eso lo sigue haciendo la persona, como el resto del repo.

## Si algo falla

Un reporte que no se puede parsear (o cuya transcripción falla) no tumba el
lote entero: queda en `logs/fallidos.jsonl` con el error y la línea cruda, y
se reintenta automáticamente en la próxima corrida sin bloquear a los demás.

`logs/procesar.log` tiene una línea por cada acción real (rotación,
transcripción, escritura en los docs). `logs/cron.log` es la salida cruda de
cron, para lo que pase antes de que el script llegue a loguear algo (por
ejemplo, si el venv no existe).

## Retención

- `tools/proxy/logs/procesados/`: el lote crudo que ya se volcó a los docs,
  archivado por si hace falta reprocesar tras un bug del script. **3 días**
  -- ni 0 (para poder corregir un error del pipeline sin perder el reporte
  original) ni los 14 de `access.jsonl` (es texto de una persona, no
  telemetría).
- `tools/reportes/estado/procesados.jsonl`: el ledger de qué reportes ya se
  volcaron (por hash de la línea cruda). No caduca -- es lo que evita
  duplicar una entrada si el pipeline corre dos veces sobre el mismo lote.
