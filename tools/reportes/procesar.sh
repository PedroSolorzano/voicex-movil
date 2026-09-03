#!/bin/sh
# Wrapper para el cron: fija el intérprete del venv propio (sin depender del
# PATH de cron ni de activar nada) y evita que dos corridas se pisen si una
# transcripción se alarga más que el intervalo del cron.
#
#   tools/reportes/procesar.sh                    # cron
#   tools/reportes/procesar.sh --dry-run           # a mano, sin escribir nada
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/estado"
exec 9>"$DIR/estado/.lock"
flock -n 9 || exit 0

exec "$DIR/.venv/bin/python3" "$DIR/procesar.py" "$@"
