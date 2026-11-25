#!/bin/zsh
# Arranca el servidor de voz. Uso: ./arrancar.sh   (desde cualquier carpeta)
cd "${0:A:h}" || exit 1
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"   # ffmpeg

[[ -x .venv/bin/uvicorn ]] || { echo "Falta el entorno. Ver README.md > Instalación."; exit 1; }

# El token vive en .token (ignorado por git). Se crea una vez y se reutiliza.
[[ -s .token ]] || { openssl rand -hex 16 > .token; chmod 600 .token; echo "Token nuevo creado en tools/mlx/.token"; }
export VOZ_TOKEN="$(cat .token)"

PUERTO="${VOZ_PUERTO:-8765}"
IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)"
echo "Servidor de voz en http://${IP:-<ip-del-mac>}:${PUERTO}  (token en tools/mlx/.token)"

# caffeinate -i: que el Mac no se duerma mientras sirve.
exec caffeinate -i .venv/bin/uvicorn server:app --host 0.0.0.0 --port "$PUERTO"
