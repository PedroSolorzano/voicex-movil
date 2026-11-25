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
# y desde cualquier terminal nueva basta `voicex`.

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

# Atajos (solo existen en esta terminal).
alias servidor='tools/mlx/arrancar.sh'
alias reportes='tools/reportes/procesar.sh'
alias bajar='dart run tools/audios/bajar.dart'
alias pasar='tools/audios/pasar.sh'
alias traer-libros='tools/audios/traer-libros.sh'
alias compilar='tools/release/compilar.sh'

echo "VoiceX listo en $VOICEX_RAIZ"
printf '  adb:     %s\n' "$(command -v adb || echo 'NO encontrado')"
printf '  dart:    %s\n' "$(command -v dart || echo 'NO encontrado')"
printf '  ffmpeg:  %s\n' "$(command -v ffmpeg || echo 'NO encontrado')"
printf '  celular: %s\n' "$(adb devices 2>/dev/null | awk 'NR>1 && $2=="device"{n++} END{print n ? n" conectado(s)" : "ninguno conectado"}')"
