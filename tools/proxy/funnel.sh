#!/bin/sh
# Prender/apagar Tailscale Funnel a mano, con la fecha de encendido guardada
# para que el aviso (en report.sh) y el apagado automático (funnel_watchdog.sh)
# sepan cuánto lleva expuesto el proxy a internet.
#
#   tools/proxy/funnel.sh on       # prende, guarda la hora
#   tools/proxy/funnel.sh off      # apaga, borra la marca
#   tools/proxy/funnel.sh status   # cuánto lleva encendido, o que está apagado
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"
MARCA="$DIR/estado/funnel_desde"

encender() {
    mkdir -p "$DIR/estado"
    docker exec voicex-tailscale tailscale funnel --bg 8080
    date -u +%Y-%m-%dT%H:%M:%SZ >"$MARCA"
    echo "Funnel encendido. Recordá apagarlo al cerrar la ronda de pruebas:"
    echo "  tools/proxy/funnel.sh off"
}

apagar() {
    docker exec voicex-tailscale tailscale funnel --https=443 off || true
    rm -f "$MARCA"
    echo "Funnel apagado."
}

estado() {
    if [ ! -f "$MARCA" ]; then
        echo "Funnel: apagado."
        return 0
    fi
    desde=$(cat "$MARCA")
    desde_epoch=$(date -u -d "$desde" +%s 2>/dev/null || echo 0)
    ahora_epoch=$(date -u +%s)
    dias=$(((ahora_epoch - desde_epoch) / 86400))

    if [ "$dias" -ge 14 ]; then
        echo "Funnel: ENCENDIDO desde $desde ($dias días) -- se apaga solo a los 21. Si ya terminó la ronda: tools/proxy/funnel.sh off"
    else
        echo "Funnel: encendido desde $desde ($dias días)."
    fi
}

case "${1:-}" in
    on) encender ;;
    off) apagar ;;
    status) estado ;;
    *)
        echo "uso: $0 on|off|status" >&2
        exit 1
        ;;
esac
