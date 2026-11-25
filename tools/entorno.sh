# Prepara la terminal para trabajar con VoiceX: te pone en la carpeta del
# proyecto y deja `adb`, Java y `ffmpeg` en el PATH.
#
# Se carga con `source`, NO se ejecuta (si se ejecuta, el cambio de carpeta y
# de PATH se pierde al terminar):
#
#   source ~/Projects/Personal/voicex-movil/tools/entorno.sh
#
# Para no escribir esa ruta, una línea en ~/.zshrc:
#
#   alias voicex='source ~/Projects/Personal/voicex-movil/tools/entorno.sh'
#
# y desde cualquier terminal nueva basta `voicex`. También acepta un comando:
#
#   voicex bajar "epubs/del-telefono/Visión ciega.epub" Teseo --horas 1.2

VOICEX_RAIZ="${${(%):-%x}:A:h:h}" 2>/dev/null
[ -n "$VOICEX_RAIZ" ] && [ -d "$VOICEX_RAIZ/tools" ] || VOICEX_RAIZ="$HOME/Projects/Personal/voicex-movil"
export VOICEX_RAIZ

_sdk=/opt/homebrew/share/android-commandlinetools
for _dir in "$_sdk/platform-tools" "$HOME/.local/bin" /opt/homebrew/bin; do
  case ":$PATH:" in *":$_dir:"*) ;; *) [ -d "$_dir" ] && PATH="$_dir:$PATH" ;; esac
done
export PATH
export ANDROID_HOME="$_sdk"
[ -d /opt/homebrew/opt/openjdk@17 ] && export JAVA_HOME=/opt/homebrew/opt/openjdk@17
unset _sdk _dir

cd "$VOICEX_RAIZ" || return 1

# Atajos (solo existen en esta terminal). Son funciones y no alias para que
# `voicex bajar "libro.epub" 4` también funcione: el comando que sigue a
# `voicex` se ejecuta al terminar de preparar la terminal.
# Las versiones anteriores de este script los definían como alias: quitarlos,
# o zsh se niega a definir una función con el mismo nombre.
unalias servidor reportes bajar pasar traer-libros compilar 2>/dev/null

servidor()     { tools/mlx/arrancar.sh "$@"; }
reportes()     { tools/reportes/procesar.sh "$@"; }
bajar()        { dart run tools/audios/bajar.dart "$@"; }
pasar()        { tools/audios/pasar.sh "$@"; }
traer-libros() { tools/audios/traer-libros.sh "$@"; }
compilar()     { tools/release/compilar.sh "$@"; }

echo "VoiceX listo en $VOICEX_RAIZ"
printf '  adb:     %s\n' "$(command -v adb || echo 'NO encontrado')"
printf '  dart:    %s\n' "$(command -v dart || echo 'NO encontrado')"
printf '  ffmpeg:  %s\n' "$(command -v ffmpeg || echo 'NO encontrado')"
printf '  celular: %s\n' "$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{n++} END{print n ? n" conectado(s)" : "ninguno conectado"}')"

# `voicex bajar "libro.epub" 4`: lo que sigue se ejecuta aquí mismo.
if [ "$#" -gt 0 ]; then
  echo
  "$@"
fi
