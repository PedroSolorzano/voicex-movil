#!/usr/bin/env bash
# Trae del teléfono los EPUB que tiene la app, con el nombre del libro.
#
#   tools/audios/traer-libros.sh
#
# Antes, en la app: Ajustes → Almacenamiento → Ver qué ocupa cada libro →
# "Dejar mis libros listos para el Mac". Son el mismo archivo que la app usa,
# byte por byte: el audio que generes con ellos se encuentra al importarlo, y no
# importa cómo se llamara tu copia ni de qué edición fuera.
set -euo pipefail

APP="com.pedrosolorzano.voicex_movil"
cd "$(dirname "$0")/../.."
DESTINO="${1:-epubs/del-telefono}"

ADB="$(command -v adb || true)"
[ -z "$ADB" ] && [ -x /opt/homebrew/share/android-commandlinetools/platform-tools/adb ] \
  && ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb
[ -z "$ADB" ] && { echo "No encuentro adb." >&2; exit 1; }

"$ADB" get-state >/dev/null 2>&1 || {
  echo "No veo el teléfono: conéctalo por cable y acepta la depuración USB." >&2
  exit 1
}

ORIGEN="/sdcard/Android/data/$APP/files/libros"
"$ADB" shell "ls '$ORIGEN'/*.epub" >/dev/null 2>&1 || {
  echo "El teléfono no tiene libros preparados. En la app: Ajustes → Almacenamiento →" >&2
  echo "Ver qué ocupa cada libro → \"Dejar mis libros listos para el Mac\"." >&2
  exit 1
}

mkdir -p "$DESTINO"
"$ADB" pull "$ORIGEN/." "$DESTINO/" | tail -1
echo
echo "Libros en $DESTINO:"
ls -1 "$DESTINO"
