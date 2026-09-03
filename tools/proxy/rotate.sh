#!/bin/sh
# Rota el log de acceso del proxy y borra lo que pase de la retención.
#
# Diario, desde el cron del host:
#   5 4 * * * /ruta/a/VoiceXMovil/tools/proxy/rotate.sh
#
# `nginx -s reopen` es lo que hace que nginx suelte el fichero viejo y abra
# uno nuevo; sin eso seguiría escribiendo en el renombrado por el descriptor.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)/logs"
RETENCION_DIAS=14

[ -f "$DIR/access.jsonl" ] || exit 0

mv "$DIR/access.jsonl" "$DIR/access-$(date +%Y-%m-%d).jsonl"
docker exec voicex-proxy nginx -s reopen

# Los registros crudos son de personas concretas: caducan. El informe agregado
# que produce report.sh es lo que sobrevive a la ronda de pruebas.
find "$DIR" -name 'access-*.jsonl' -mtime "+$RETENCION_DIAS" -delete
