#!/bin/sh
# Red de seguridad, no el mecanismo principal: el aviso de funnel.sh/report.sh
# es lo que se supone que apaga el Funnel al cerrar una ronda. Esto es para
# el día que ese aviso se ignora -- apaga solo a los 21 días, sin depender de
# que alguien lo vea a tiempo.
#
# Diario, desde el cron del host:
#   0 5 * * * /ruta/a/VoiceXMovil/tools/proxy/funnel_watchdog.sh
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
MARCA="$DIR/estado/funnel_desde"
LOG="$DIR/logs/funnel.log"
LIMITE_DIAS=21

[ -f "$MARCA" ] || exit 0

desde_epoch=$(date -u -d "$(cat "$MARCA")" +%s 2>/dev/null || echo 0)
ahora_epoch=$(date -u +%s)
dias=$(((ahora_epoch - desde_epoch) / 86400))

if [ "$dias" -ge "$LIMITE_DIAS" ]; then
    "$DIR/funnel.sh" off
    mkdir -p "$DIR/logs"
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) apagado automático tras $dias días encendido" >>"$LOG"
fi
