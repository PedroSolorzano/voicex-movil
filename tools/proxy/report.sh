#!/bin/sh
# Informe de uso por probador, sobre el log del proxy.
#
#   tools/proxy/report.sh              # todo lo que haya
#   tools/proxy/report.sh 2026-09-03   # solo ese día
#
# Responde las tres preguntas que motivaron el log: quién se conecta, qué
# consume, y si los errores y los tiempos justifican los plazos que la app
# concede al sondeo.
#
# Cómo leerlo:
#   p95 alto y reintentos altos en una persona -> su red, no el servidor.
#   4xx sostenidos -> token mal copiado, o un APK reenviado a alguien más.
#   sondeos cerca del número de síntesis -> la caché de salud no funciona.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)/logs"
FILTRO="${1:-}"

command -v jq >/dev/null || { echo "Hace falta jq: sudo apt install jq"; exit 1; }

cat "$DIR"/access.jsonl "$DIR"/access-*.jsonl 2>/dev/null \
| { [ -n "$FILTRO" ] && grep "\"ts\":\"$FILTRO" || cat; } \
| jq -s -r '
  def num: if . == "" or . == "-" or . == null then 0 else (tonumber? // 0) end;
  def pct($p): if length == 0 then 0 else sort | .[((length - 1) * $p) | floor] end;

  map(select(.tester != ""))
  | group_by(.tester)
  | map({
      tester:    .[0].tester,
      peticiones: length,
      sintesis:  map(select(.endpoint | test("synthesize|captioned"))) | length,
      sondeos:   map(select(.endpoint | test("/health$|/info$")))      | length,
      voces:     map(select(.endpoint | test("voices$")))              | length,
      mb:        (map(.bytes | num) | add / 1048576),
      chars:     (map(.chars | num) | add),
      p50:       (map(.req_ms | num * 1000) | pct(0.50)),
      p95:       (map(.req_ms | num * 1000) | pct(0.95)),
      err4:      map(select(.status | startswith("4"))) | length,
      err5:      map(select(.status | startswith("5"))) | length,
      reintentos: map(select(.attempt == "2")) | length,
    })
  | (["PROBADOR","PETIC","SINT","SOND","VOCES","MB","CARACT","p50ms","p95ms","4xx","5xx","REINT"] | @tsv),
    (.[] | [.tester, .peticiones, .sintesis, .sondeos, .voces,
            (.mb * 10 | round / 10), .chars,
            (.p50 | round), (.p95 | round), .err4, .err5, .reintentos] | @tsv)
' | column -t

echo
echo "Peticiones rechazadas sin identificar (401, escaneo o token inválido):"
cat "$DIR"/access.jsonl "$DIR"/access-*.jsonl 2>/dev/null \
| jq -r 'select(.tester == "") | .net' | sort | uniq -c | sort -rn | head -5
