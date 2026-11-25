#!/bin/sh
# Wrapper: fija el intérprete del venv propio (sin depender del PATH ni de
# activar nada) y evita que dos corridas se pisen si una transcripción se alarga.
#
#   tools/reportes/procesar.sh                    # procesa lo pendiente
#   tools/reportes/procesar.sh --dry-run           # sin escribir nada
#
# El candado es un directorio y no `flock`: macOS no lo trae, y `mkdir` es
# atómico en cualquier sistema.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$DIR/estado"
CANDADO="$DIR/estado/.lock.d"
mkdir "$CANDADO" 2>/dev/null || exit 0   # otra corrida en curso
trap 'rmdir "$CANDADO"' EXIT

"$DIR/.venv/bin/python3" "$DIR/procesar.py" "$@"
