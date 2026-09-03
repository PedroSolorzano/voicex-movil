#!/usr/bin/env python3
"""Vuelca los reportes de testers a los documentos del repo.

Lee `tools/proxy/logs/reportes.jsonl`, transcribe localmente la nota de voz
de cada reporte que traiga una (nunca se manda audio a un servicio en la
nube: ver `tools/reportes/README.md`), y agrega cada entrada al documento que
corresponde: `docs/bugs/REPORTES_TESTERS.md` para bugs y crashes,
la sección "Sin triar" de `docs/tasks/IMPROVEMENTS.md` para mejoras.

Pensado para correr solo desde el cron del host (`procesar.sh`), sin
intervención humana en cada corrida. Nunca hace `git commit` -- a lo sumo
`git add` de los dos documentos, para que la revisión y el commit los siga
haciendo la persona, como en el resto del repo.

Uso:
    procesar.py [--dry-run] [--correlacionar-por-cercania]

--dry-run                     No escribe nada (ni docs, ni ledger, ni
                               archivo, ni borra audio); solo imprime qué
                               haría. Sí transcribe, para poder juzgar la
                               calidad antes de dejarlo corriendo solo.
--correlacionar-por-cercania  Para reportes viejos, mandados antes de que
                               el cuerpo llevara el campo `nota`: busca el
                               .m4a de fecha más cercana en vez de exigir la
                               referencia explícita. Pensado para una sola
                               corrida manual sobre el backlog existente,
                               nunca para la línea de cron -- una correlación
                               por cercanía puede equivocarse de reporte.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PROXY_LOGS = REPO / "tools" / "proxy" / "logs"
RAW = PROXY_LOGS / "reportes.jsonl"
PROCESSING = PROXY_LOGS / "reportes.processing.jsonl"
NOTAS = PROXY_LOGS / "notas"
PROCESADOS_DIR = PROXY_LOGS / "procesados"
RETENCION_PROCESADOS = timedelta(days=3)

AQUI = Path(__file__).resolve().parent
ESTADO_DIR = AQUI / "estado"
LEDGER = ESTADO_DIR / "procesados.jsonl"
LOGS_DIR = AQUI / "logs"
LOG_PROCESO = LOGS_DIR / "procesar.log"
FALLIDOS = LOGS_DIR / "fallidos.jsonl"

BUGS_DOC = REPO / "docs" / "bugs" / "REPORTES_TESTERS.md"
IMPROVEMENTS_DOC = REPO / "docs" / "tasks" / "IMPROVEMENTS.md"

# Modelo balanceado a propósito hacia calidad: las notas duran <=90s y las
# corridas son periódicas, no en vivo, así que unos segundos más de CPU
# importan menos que entender bien una voz real, con ruido de fondo.
MODELO_WHISPER = "small"

CORRELACION_TOLERANCIA = timedelta(minutes=5)


def log(mensaje: str) -> None:
    linea = f"{datetime.now(timezone.utc).isoformat()}  {mensaje}"
    print(linea)
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    with LOG_PROCESO.open("a", encoding="utf-8") as f:
        f.write(linea + "\n")


def registrar_fallido(linea_cruda: str, error: Exception) -> None:
    LOGS_DIR.mkdir(parents=True, exist_ok=True)
    with FALLIDOS.open("a", encoding="utf-8") as f:
        f.write(json.dumps({
            "ts": datetime.now(timezone.utc).isoformat(),
            "error": f"{type(error).__name__}: {error}",
            "linea": linea_cruda,
        }, ensure_ascii=False) + "\n")


def id_de(linea_cruda: str) -> str:
    return hashlib.sha256(linea_cruda.encode("utf-8")).hexdigest()[:16]


def cargar_ledger() -> set[str]:
    if not LEDGER.exists():
        return set()
    ids: set[str] = set()
    for linea in LEDGER.read_text(encoding="utf-8").splitlines():
        try:
            ids.add(json.loads(linea)["id"])
        except (json.JSONDecodeError, KeyError):
            continue
    return ids


def agregar_al_ledger(ids: list[str]) -> None:
    if not ids:
        return
    ESTADO_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).isoformat()
    with LEDGER.open("a", encoding="utf-8") as f:
        for id_ in ids:
            f.write(json.dumps({"id": id_, "ts": ts}) + "\n")


def rotar() -> bool:
    """Deja el lote a procesar en PROCESSING. Devuelve False si no hay nada
    que hacer, o si el proxy no está disponible para el `reopen`."""
    if not PROCESSING.exists():
        if not RAW.exists() or RAW.stat().st_size == 0:
            return False
        RAW.rename(PROCESSING)
        log(f"rotado {RAW.name} -> {PROCESSING.name}")
    else:
        log(f"{PROCESSING.name} ya existía (corrida anterior interrumpida), reintentando")

    try:
        subprocess.run(
            ["docker", "exec", "voicex-proxy", "nginx", "-s", "reopen"],
            check=True, capture_output=True, timeout=15, text=True,
        )
    except Exception as e:
        log(f"nginx -s reopen falló, no se toca {PROCESSING.name} esta corrida: {e}")
        return False
    return True


@dataclass
class Nota:
    ruta: Path
    aproximada: bool


def resolver_nota(reporte: dict, correlacionar_por_cercania: bool,
                   ts_entrada: str | None) -> Nota | None:
    nombre = reporte.get("nota")
    if isinstance(nombre, str) and nombre:
        ruta = NOTAS / nombre
        return Nota(ruta, aproximada=False) if ruta.exists() else None

    if not correlacionar_por_cercania or not NOTAS.is_dir() or not ts_entrada:
        return None
    try:
        cuando = datetime.fromisoformat(ts_entrada)
    except ValueError:
        return None

    mejor: Path | None = None
    mejor_delta: timedelta | None = None
    for candidata in NOTAS.glob("*.m4a"):
        mtime = datetime.fromtimestamp(candidata.stat().st_mtime, tz=timezone.utc)
        delta = abs(mtime - cuando)
        if delta <= CORRELACION_TOLERANCIA and (mejor_delta is None or delta < mejor_delta):
            mejor, mejor_delta = candidata, delta
    return Nota(mejor, aproximada=True) if mejor else None


_modelo = None


def cargar_modelo():
    global _modelo
    if _modelo is None:
        from faster_whisper import WhisperModel
        log(f"cargando modelo whisper '{MODELO_WHISPER}' (cpu, int8)")
        _modelo = WhisperModel(MODELO_WHISPER, device="cpu", compute_type="int8")
    return _modelo


def transcribir(ruta: Path) -> str:
    modelo = cargar_modelo()
    segmentos, _info = modelo.transcribe(str(ruta), language="es", vad_filter=True)
    return " ".join(s.text.strip() for s in segmentos).strip()


def _fecha_hora(ts: str) -> str:
    try:
        return datetime.fromisoformat(ts).strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return ts


def _contexto(reporte: dict) -> str | None:
    partes = []
    if reporte.get("libro"):
        partes.append(str(reporte["libro"]))
    if reporte.get("capitulo") is not None:
        partes.append(f"capítulo {reporte['capitulo']}")
    if reporte.get("motor"):
        partes.append(str(reporte["motor"]))
    return ", ".join(partes) if partes else None


def bloque_bug(entrada: dict, reporte: dict, transcripcion: str | None,
               aproximada: bool) -> str:
    tester = entrada.get("tester", "?")
    tipo = reporte.get("tipo", "?")
    fecha = _fecha_hora(entrada.get("ts", ""))
    lineas = [f"## {fecha} — {tipo} — {tester}"]

    contexto = _contexto(reporte)
    if contexto:
        lineas.append(f"\n**Contexto:** {contexto}")

    if tipo == "crash":
        lineas.append(f"\n**Error:** {reporte.get('error', '?')}")
        if reporte.get("traza"):
            lineas.append(f"\n**Traza:** {reporte['traza']}")
    elif reporte.get("texto"):
        lineas.append(f"\n> {reporte['texto']}")

    if transcripcion:
        marca = " _(nota de voz correlacionada por cercanía de horario, no por referencia explícita)_" if aproximada else ""
        lineas.append(f"\n**Nota de voz transcrita:**{marca}\n\n> {transcripcion}")

    diagnostico = reporte.get("diagnostico")
    if diagnostico:
        lineas.append("\n**Diagnóstico:**")
        lineas.extend(f"- {d}" for d in diagnostico)

    lineas.append("\n---\n")
    return "\n".join(lineas)


def bloque_mejora(entrada: dict, reporte: dict, transcripcion: str | None,
                   aproximada: bool) -> str:
    tester = entrada.get("tester", "?")
    fecha = _fecha_hora(entrada.get("ts", ""))
    texto = (reporte.get("texto") or "").strip()

    if texto and transcripcion:
        contenido = f"{texto} — audio: “{transcripcion}”"
    elif transcripcion:
        marca = " _(correlación aproximada)_" if aproximada else ""
        contenido = f"(por nota de voz{marca}) {transcripcion}"
    else:
        contenido = texto or "(sin texto ni nota de voz -- revisar el reporte crudo)"

    linea = f"- **{fecha}** `{tester}` — {contenido}"
    contexto = _contexto(reporte)
    if contexto:
        linea += f" _({contexto})_"
    return linea


BUGS_HEADER = """# Reportes crudos de probadores

Volcado automático de `tools/proxy/logs/reportes.jsonl` por
`tools/reportes/procesar.py`, que corre solo desde el cron del host (ver
`tools/reportes/README.md`). Se añade al final, nunca se edita ni se
reordena a mano. Si algo de aquí se convierte en una investigación de
verdad, esa investigación vive en su propio archivo de `docs/bugs/` y
referencia esta entrada, no al revés.

---

"""


def escribir_bugs(bloques: list[str]) -> None:
    if not BUGS_DOC.exists():
        BUGS_DOC.write_text(BUGS_HEADER, encoding="utf-8")
    with BUGS_DOC.open("a", encoding="utf-8") as f:
        for b in bloques:
            f.write(b + "\n")


SIN_TRIAR_HEADER = "## Sin triar (reportado por testers)"
SIN_TRIAR_INTRO = """
Entradas que añade solo `tools/reportes/procesar.py`, automáticamente. No
usan el formato de arriba a propósito: nadie -ni el tester, ni el script-
puso una prioridad, y forzar una acá sería inventarla. Revisar, decidir
prioridad y sección, reescribir con el formato estándar de arriba, y borrar
de acá.
"""


def escribir_mejoras(bullets: list[str]) -> None:
    texto = IMPROVEMENTS_DOC.read_text(encoding="utf-8")
    nuevas = "\n".join(bullets)

    if SIN_TRIAR_HEADER in texto:
        # Insertar al final de la sección existente, antes del próximo "## " o "---".
        inicio = texto.index(SIN_TRIAR_HEADER)
        resto = texto[inicio:]
        fin_relativo = len(resto)
        for marca in ("\n## ", "\n---"):
            pos = resto.find(marca, len(SIN_TRIAR_HEADER))
            if pos != -1:
                fin_relativo = min(fin_relativo, pos)
        seccion = resto[:fin_relativo].rstrip("\n")
        seccion_nueva = seccion + "\n" + nuevas + "\n"
        texto = texto[:inicio] + seccion_nueva + resto[fin_relativo:]
    else:
        bloque = f"{SIN_TRIAR_HEADER}\n{SIN_TRIAR_INTRO}\n{nuevas}\n\n---\n\n"
        ancla = "## Pendiente de decisión"
        if ancla in texto:
            texto = texto.replace(ancla, bloque + ancla, 1)
        else:
            texto = texto.rstrip("\n") + "\n\n---\n\n" + bloque

    IMPROVEMENTS_DOC.write_text(texto, encoding="utf-8")


def git_add() -> None:
    subprocess.run(
        ["git", "-C", str(REPO), "add", str(BUGS_DOC), str(IMPROVEMENTS_DOC)],
        check=False,
    )


def purgar_procesados() -> None:
    if not PROCESADOS_DIR.is_dir():
        return
    limite = datetime.now(timezone.utc) - RETENCION_PROCESADOS
    for archivo in PROCESADOS_DIR.glob("reportes-*.jsonl"):
        mtime = datetime.fromtimestamp(archivo.stat().st_mtime, tz=timezone.utc)
        if mtime < limite:
            archivo.unlink(missing_ok=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--correlacionar-por-cercania", action="store_true")
    args = ap.parse_args()

    if args.dry_run:
        crudo = ""
        if PROCESSING.exists():
            crudo += PROCESSING.read_text(encoding="utf-8")
        if RAW.exists():
            crudo += RAW.read_text(encoding="utf-8")
        lineas = [l for l in crudo.splitlines() if l.strip()]
    else:
        if not rotar():
            return 0
        lineas = [l for l in PROCESSING.read_text(encoding="utf-8").splitlines() if l.strip()]

    if not lineas:
        log("nada que procesar")
        if not args.dry_run and PROCESSING.exists():
            PROCESSING.unlink()
        return 0

    ledger = cargar_ledger()
    bloques_bugs: list[str] = []
    bullets_mejoras: list[str] = []
    ids_nuevos: list[str] = []
    pendientes: list[str] = []  # se reintentan la próxima corrida
    ya_procesadas: list[str] = []  # ya estaban en el ledger de antes

    for cruda in lineas:
        id_ = id_de(cruda)
        if id_ in ledger:
            ya_procesadas.append(cruda)
            continue
        try:
            entrada = json.loads(cruda)
            reporte = json.loads(entrada["reporte"])
            nota = resolver_nota(reporte, args.correlacionar_por_cercania, entrada.get("ts"))
            transcripcion = None
            aproximada = False
            if nota is not None:
                aproximada = nota.aproximada
                transcripcion = transcribir(nota.ruta)
                log(f"transcrita {nota.ruta.name} ({len(transcripcion)} chars)"
                    + (" [correlación aproximada]" if aproximada else ""))

            if reporte.get("tipo") == "mejora":
                bullets_mejoras.append(bloque_mejora(entrada, reporte, transcripcion, aproximada))
            else:
                bloques_bugs.append(bloque_bug(entrada, reporte, transcripcion, aproximada))

            if args.dry_run:
                continue

            if nota is not None:
                nota.ruta.unlink(missing_ok=True)
            ids_nuevos.append(id_)
            ya_procesadas.append(cruda)
        except Exception as e:  # noqa: BLE001 -- un reporte roto no debe tumbar el lote
            log(f"reporte inválido, se reintenta la próxima corrida: {e}")
            registrar_fallido(cruda, e)
            pendientes.append(cruda)

    if args.dry_run:
        print(f"\n--- {len(bloques_bugs)} bug(s)/crash(es) irían a {BUGS_DOC.relative_to(REPO)} ---")
        for b in bloques_bugs:
            print(b)
        print(f"\n--- {len(bullets_mejoras)} mejora(s) irían a la sección 'Sin triar' de {IMPROVEMENTS_DOC.relative_to(REPO)} ---")
        for b in bullets_mejoras:
            print(b)
        return 0

    if bloques_bugs:
        escribir_bugs(bloques_bugs)
        log(f"{len(bloques_bugs)} entrada(s) agregadas a {BUGS_DOC.name}")
    if bullets_mejoras:
        escribir_mejoras(bullets_mejoras)
        log(f"{len(bullets_mejoras)} entrada(s) agregadas a la sección 'Sin triar' de {IMPROVEMENTS_DOC.name}")
    if bloques_bugs or bullets_mejoras:
        git_add()

    agregar_al_ledger(ids_nuevos)

    if pendientes:
        PROCESSING.write_text("\n".join(pendientes) + "\n", encoding="utf-8")
        log(f"{len(pendientes)} reporte(s) quedan pendientes para la próxima corrida")
    else:
        if ya_procesadas:
            PROCESADOS_DIR.mkdir(parents=True, exist_ok=True)
            archivo = PROCESADOS_DIR / f"reportes-{datetime.now(timezone.utc):%Y-%m-%dT%H%M%S}.jsonl"
            archivo.write_text("\n".join(ya_procesadas) + "\n", encoding="utf-8")
        PROCESSING.unlink(missing_ok=True)

    purgar_procesados()
    return 0


if __name__ == "__main__":
    sys.exit(main())
