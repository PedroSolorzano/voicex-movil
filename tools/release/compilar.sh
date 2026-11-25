#!/usr/bin/env bash
# Compila el APK con TODOS los motores y comprueba que de verdad quedaron dentro.
#
# Es el equivalente de compilar.ps1 para macOS y Linux, sin PowerShell. Existe
# por la misma razón: `flutter build apk --release` a secas compila sin
# servidor y el resultado no se distingue de uno bueno. El APK se instala,
# arranca y funciona, solo que en Ajustes aparecen dos motores en vez de cuatro.
# Es un fallo silencioso, y por eso hace falta comprobarlo en vez de confiar.
#
#   tools/release/compilar.sh                 # perfil pedro, todos los motores
#   tools/release/compilar.sh -p amigo        # compilación de un probador
#   tools/release/compilar.sh -l              # limpio: obligatorio si cambió la versión
#   tools/release/compilar.sh -i              # y lo deja en el teléfono (adb)
#
# Ver README.md de esta carpeta para qué lleva cada .json y por qué.
set -euo pipefail

perfil="pedro"
limpio=0
instalar=0
while getopts "p:li" opt; do
  case "$opt" in
    p) perfil="$OPTARG" ;;
    l) limpio=1 ;;
    i) instalar=1 ;;
    *) echo "Uso: $0 [-p perfil] [-l] [-i]" >&2; exit 2 ;;
  esac
done

raiz="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$raiz"

# El .json personal lleva VOICE_TOKEN: no está en git. voz.json (la dirección del
# servidor de voz) sí, así que vale para cualquier compilación.
personal="tools/release/$perfil.json"
if [[ ! -f "$personal" ]]; then
  echo "No existe $personal. Copia tools/release/tester.example.json y edítalo (ver README.md)." >&2
  exit 1
fi
# Los compartidos van PRIMERO y el perfil personal AL FINAL, porque
# `--dart-define-from-file` repetido se queda con el último valor de cada clave.
# Al revés, voz.json le pisaría el VOICE_URL a un perfil que traiga uno propio y
# el APK saldría con una dirección que no es la suya, sin un solo aviso.
configs=()
for extra in tools/release/voz.json; do
  if [[ -f "$extra" ]]; then
    configs+=("$extra")
  else
    echo "AVISO: falta $extra: lo que lleva no va a estar en el APK." >&2
  fi
done
configs+=("$personal")

# Lo que esperamos encontrar después dentro del binario: toda clave *_URL o
# *_TOKEN con valor. Se lee de los mismos .json que se le pasan al build, así que
# un archivo incompleto -- el fallo que el README avisa que no da la cara -- se
# detecta abajo. El token también, porque sin él el servidor responde 401 y la
# app se repliega a Edge sin decirlo.
esperados="$(python3 - "${configs[@]}" <<'PY'
import json, sys
vistos = {}
for ruta in sys.argv[1:]:
    for clave, valor in json.load(open(ruta)).items():
        if (clave.endswith("_URL") or clave.endswith("_TOKEN")) and valor:
            vistos[clave] = valor          # el último archivo gana, como en flutter
for clave in sorted(vistos):
    print(f"{clave}\t{vistos[clave]}")
PY
)"

echo "Perfil:  $perfil"
echo "Config:  ${configs[*]}"
echo "Motores: Edge y Teléfono (siempre) + lo que traigan: $(cut -f1 <<<"$esperados" | tr '\n' ' ')"
echo

# `flutter build apk` no regenera el manifiesto cuando lo único que cambió es la
# versión: Gradle no vigila android/local.properties como entrada de tarea, y el
# APK sale con el versionName viejo dentro. Ver README.md, "Al subir la versión".
if [[ $limpio -eq 1 ]]; then flutter clean; fi

argumentos=(build apk --release)
for c in "${configs[@]}"; do argumentos+=("--dart-define-from-file=$c"); done
flutter "${argumentos[@]}"

# --- Comprobación: los valores compilados están en el snapshot de Dart ---
#
# String.fromEnvironment deja el valor como cadena literal dentro de libapp.so
# (ver README.md, "Lo que un APK no puede esconder"). Eso, que es lo que impide
# tratar el token como secreto, sirve aquí para verificar el build.
apk="build/app/outputs/flutter-apk/app-release.apk"
[[ -f "$apk" ]] || { echo "No apareció $apk." >&2; exit 1; }

so="$(unzip -Z1 "$apk" | grep -m1 'lib/.*/libapp\.so' || true)"
[[ -n "$so" ]] || { echo "El APK no trae libapp.so: no se puede comprobar nada." >&2; exit 1; }
contenido="$(mktemp)"
trap 'rm -f "$contenido"' EXIT
unzip -p "$apk" "$so" > "$contenido"

echo
faltan=()
while IFS=$'\t' read -r nombre valor; do
  [[ -n "$nombre" ]] || continue
  # -a: es binario. -F: el valor es literal, no una expresión regular.
  if grep -qaF -- "$valor" "$contenido"; then
    echo "  OK       $nombre"
  else
    echo "  FALTA    $nombre"
    faltan+=("$nombre")
  fi
done <<<"$esperados"
if [[ ${#faltan[@]} -gt 0 ]]; then
  echo "El APK se compiló sin ${faltan[*]}: esos motores no aparecerán en Ajustes. No lo repartas." >&2
  exit 1
fi

version="$(sed -n 's/^version:[[:space:]]*\([^+]*\).*/\1/p' pubspec.yaml | head -1 | tr -d ' ')"
echo
echo "APK correcto: $apk ($version, perfil $perfil)"

if [[ $instalar -eq 1 ]]; then
  adb install -r "$apk"
  # Lo que dice el APK por dentro, no lo que dice el nombre del archivo.
  adb shell dumpsys package com.pedrosolorzano.voicex_movil | grep versionName
fi
