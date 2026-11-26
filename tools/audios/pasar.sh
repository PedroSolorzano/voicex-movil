#!/usr/bin/env bash
# Pasa por cable USB al teléfono el audio que generó bajar.dart.
#
#   tools/audios/pasar.sh [carpeta-de-salida]
#
# Lo deja en la carpeta propia de la app (Android/data/<app>/files/importar),
# que adb puede escribir y la app leer sin pedir permisos. Después, en la app:
# Ajustes → Almacenamiento → Ver qué ocupa cada libro → Importar audios del Mac.
set -euo pipefail

APP="com.pedrosolorzano.voicex_movil"
cd "$(dirname "$0")/../.."
SALIDA="${1:-tools/audios/salida}"

ADB="$(command -v adb || true)"
[ -z "$ADB" ] && [ -x /opt/homebrew/share/android-commandlinetools/platform-tools/adb ] \
  && ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb
[ -z "$ADB" ] && { echo "No encuentro adb." >&2; exit 1; }

[ -d "$SALIDA" ] && [ -n "$(ls -A "$SALIDA" 2>/dev/null)" ] || {
  echo "No hay nada en $SALIDA. Primero: dart run tools/audios/bajar.dart <libro.epub> <capítulos>" >&2
  exit 1
}

"$ADB" get-state >/dev/null 2>&1 || {
  echo "No veo el teléfono: conéctalo por cable y acepta la depuración USB." >&2
  exit 1
}
"$ADB" shell pm path "$APP" >/dev/null 2>&1 || {
  echo "VoiceX no está instalada en el teléfono." >&2
  exit 1
}

DEST="/sdcard/Android/data/$APP/files/importar"
"$ADB" shell mkdir -p "$DEST"

for libro in "$SALIDA"/*/; do
  nombre="$(basename "$libro")"
  [ -f "$libro/manifest.json" ] || continue
  echo "→ $nombre"
  # Se borra y se crea a mano antes: `adb push` no puede crear carpetas dentro
  # de Android/data ("secure_mkdirs failed"), solo escribir en una que ya
  # existe. Y así no queda nada de una pasada anterior.
  "$ADB" shell rm -rf "$DEST/$nombre"
  "$ADB" shell mkdir -p "$DEST/$nombre"
  "$ADB" push "$libro/." "$DEST/$nombre/" | tail -1
done

echo
echo "Listo. En la app: Ajustes → Almacenamiento → Ver qué ocupa cada libro → Importar audios del Mac."
echo "La salida del Mac se queda como respaldo: el servidor de voz la sirve, y la app"
echo "también puede traerla por Tailscale con el mismo botón, sin cable."
