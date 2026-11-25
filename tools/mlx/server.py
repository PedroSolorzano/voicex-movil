"""Servidor de voz para VoiceX: Qwen3-TTS y Chatterbox en un Mac con Apple Silicon.

Un solo proceso sirve los dos motores con las voces clonadas de `voices/`.
La app lo ve como dos motores (`qwen3`, `chatterbox2`) que comparten dirección
y token. Ver README.md para el porqué de cada decisión.

    POST /tts     {"text": ..., "voice": ..., "engine": ...}  ->  audio/mpeg
    GET  /health  estado, voces y si hay una síntesis en curso (sin tocar la GPU)

    POST /report                reporte de error o mejora de la app (JSON)
    PUT  /report/audio/<id>.m4a nota de voz que acompaña a un reporte
"""
import hmac
import json
import logging
import os
import re
import shutil
import subprocess
import threading
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.responses import Response
from pydantic import BaseModel, Field

log = logging.getLogger("voz")
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s", datefmt="%H:%M:%S")

VOCES = Path(os.environ.get("VOZ_VOCES", Path(__file__).parent / "voices"))
TOKEN = os.environ.get("VOZ_TOKEN", "")
FFMPEG = os.environ.get("VOZ_FFMPEG") or shutil.which("ffmpeg") or "ffmpeg"

# Reportes de la app ("Contar un problema"). Mismo formato en disco que dejaba el
# proxy de nginx que los recibía antes, para que `tools/reportes/procesar.py`
# siga leyéndolos sin cambios de fondo.
REPORTES = Path(os.environ.get("VOZ_REPORTES", Path(__file__).parent / "reportes"))
TESTER = os.environ.get("VOZ_TESTER", "pedro")
MAX_REPORTE = 32 * 1024        # un reporte es texto y contexto, no un libro
MAX_NOTA = 4 * 1024 * 1024     # una nota de voz de unos minutos
MAX_POR_MINUTO = 20            # un reporte es un acto humano, no un bucle
# El nombre lo impone esta expresión, así que un cliente no puede elegir dónde
# escribe: es un UUID y la extensión de la nota, nada más.
NOTA_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f-]{27}\.m4a$")

# Un párrafo de diálogo cabe entero (así se midió: 0 % de errores). Solo lo que
# lo supera se parte, por oraciones, porque los modelos autorregresivos pueden
# saltarse o repetir palabras en tramos largos.
MAX_CHARS = int(os.environ.get("VOZ_MAX_CHARS", "380"))
PAUSA_S = 0.2  # silencio entre los trozos de un párrafo largo

# id que ve la app -> repo y parámetros de `generate`. `chatterbox2` y no
# `chatterbox`: ese id lo retiró la app en 0.8.0 y borra sus filas de caché en
# cada arranque (ver `_dropRetiredEngineRows` en la app).
MOTORES = {
    "qwen3": "mlx-community/Qwen3-TTS-12Hz-1.7B-Base-bf16",
    "chatterbox2": "mlx-community/chatterbox-multilingual-v3",
}
ACTIVOS = [m for m in os.environ.get("VOZ_MOTORES", ",".join(MOTORES)).split(",") if m in MOTORES]


def _args_de_voz(motor: str, wav: str, texto_ref: str) -> dict:
    if motor == "qwen3":
        return dict(ref_audio=wav, ref_text=texto_ref, lang_code="spanish")
    return dict(ref_audio=wav, lang_code="es")


# MLX liga sus streams al hilo que los crea: cargar el modelo en un hilo y
# sintetizar desde otro falla con "no Stream in current thread". Todo el trabajo
# de GPU pasa por este único hilo, que además hace de cola: una síntesis a la vez.
_gpu = ThreadPoolExecutor(max_workers=1, thread_name_prefix="mlx")
_modelos: dict = {}
_errores: dict[str, str] = {}
_pendientes = 0  # síntesis en cola o en curso
_lock = threading.Lock()
_voces: dict[str, tuple[str, str]] = {}


def _cargar_voces() -> None:
    _voces.clear()
    for wav in sorted(VOCES.glob("*.wav")):
        txt = wav.with_suffix(".txt")
        if not txt.exists() or not txt.read_text(encoding="utf-8").strip():
            log.warning("%s sin .txt con su transcripción, se omite", wav.name)
            continue
        _voces[wav.stem] = (str(wav), txt.read_text(encoding="utf-8").strip())
    log.info("voces: %s", ", ".join(_voces) or "(ninguna)")


def _cargar_modelos() -> None:
    from mlx_audio.tts.utils import load_model

    for motor in ACTIVOS:
        t0 = time.perf_counter()
        try:
            _modelos[motor] = load_model(MOTORES[motor])
            log.info("%s listo en %.1f s", motor, time.perf_counter() - t0)
        except Exception as e:  # un motor caído no tumba al otro
            _errores[motor] = f"{type(e).__name__}: {e}"
            log.exception("no se pudo cargar %s", motor)


@asynccontextmanager
async def _vida(_: FastAPI):
    _cargar_voces()
    _gpu.submit(_cargar_modelos)
    yield
    _gpu.shutdown(wait=False, cancel_futures=True)


app = FastAPI(title="VoiceX voz", lifespan=_vida)


def exigir_token(authorization: str | None = Header(default=None)) -> None:
    """Opcional a propósito, pero recomendado: el puerto queda abierto en toda
    la red local y `/health` enumera voces que son grabaciones de personas."""
    if not TOKEN:
        return
    esperado = f"Bearer {TOKEN}"
    if not authorization or not hmac.compare_digest(authorization, esperado):
        raise HTTPException(401, "token inválido")


class Peticion(BaseModel):
    text: str = Field(max_length=20000)
    voice: str | None = None
    engine: str | None = None


def _trozos(texto: str) -> list[str]:
    """El párrafo entero si cabe; si no, oraciones agrupadas hasta MAX_CHARS."""
    texto = " ".join(texto.split())
    if len(texto) <= MAX_CHARS:
        return [texto]
    oraciones = re.split(r"(?<=[.!?…])\s+", texto)
    trozos, actual = [], ""
    for o in oraciones:
        if actual and len(actual) + 1 + len(o) > MAX_CHARS:
            trozos.append(actual)
            actual = o
        else:
            actual = f"{actual} {o}".strip()
    if actual:
        trozos.append(actual)
    return trozos


def _sintetizar(motor: str, voz: str, texto: str) -> tuple[np.ndarray, int]:
    import mlx.core as mx

    wav, texto_ref = _voces[voz]
    modelo = _modelos[motor]
    partes, sr = [], None
    for trozo in _trozos(texto):
        for r in modelo.generate(text=trozo, **_args_de_voz(motor, wav, texto_ref)):
            partes.append(np.array(r.audio, dtype=np.float32).reshape(-1))
            sr = r.sample_rate
        if sr is None:
            raise RuntimeError("el modelo no devolvió audio")
        partes.append(np.zeros(int(sr * PAUSA_S), dtype=np.float32))
    mx.clear_cache()  # sin esto el proceso conserva los buffers de cada párrafo
    return np.concatenate(partes[:-1]) if partes else np.zeros(0, np.float32), sr


def _a_mp3(onda: np.ndarray, sr: int) -> bytes:
    pcm = (np.clip(onda, -1, 1) * 32767).astype("<i2").tobytes()
    hecho = subprocess.run(
        [FFMPEG, "-hide_banner", "-loglevel", "error", "-f", "s16le", "-ar", str(sr),
         "-ac", "1", "-i", "pipe:0", "-b:a", "96k", "-f", "mp3", "pipe:1"],
        input=pcm, capture_output=True,
    )
    if hecho.returncode != 0:
        raise HTTPException(500, f"ffmpeg falló: {hecho.stderr.decode()[:200]}")
    return hecho.stdout


@app.get("/health", dependencies=[Depends(exigir_token)])
def salud() -> dict:
    """Barato: no toca la GPU ni espera a que termine una síntesis."""
    cargando = [m for m in ACTIVOS if m not in _modelos and m not in _errores]
    return {
        "status": "loading" if cargando else ("ok" if _modelos else "error"),
        "engines": sorted(_modelos),
        "errors": _errores,
        "voices": sorted(_voces),
        "busy": _pendientes > 0,
    }


@app.post("/tts", dependencies=[Depends(exigir_token)])
def sintetizar(p: Peticion) -> Response:
    global _pendientes
    if not _modelos:
        raise HTTPException(503, "los modelos todavía están cargando")
    texto = p.text.strip()
    if not texto:
        raise HTTPException(400, "texto vacío")
    motor = p.engine or next(iter(_modelos))
    if motor not in _modelos:
        raise HTTPException(404, f"motor no disponible: {motor!r}")
    voz = p.voice or next(iter(_voces), None)
    if voz not in _voces:
        raise HTTPException(404, f"voz desconocida: {voz!r}")

    with _lock:
        _pendientes += 1
    t0 = time.perf_counter()
    try:
        onda, sr = _gpu.submit(_sintetizar, motor, voz, texto).result()
    finally:
        with _lock:
            _pendientes -= 1
    audio_s = len(onda) / sr if sr else 0
    log.info("%s/%s %d car -> %.1f s de audio en %.1f s", motor, voz, len(texto), audio_s,
             time.perf_counter() - t0)
    if audio_s == 0:
        raise HTTPException(500, "el modelo no devolvió audio")
    return Response(content=_a_mp3(onda, sr), media_type="audio/mpeg")


_recientes: deque[float] = deque()


def _limitar() -> None:
    """Ritmo máximo de reportes. Con el token dentro del APK es lo que impide
    que un cliente que se repite solo llene el disco."""
    with _lock:
        ahora = time.monotonic()
        while _recientes and ahora - _recientes[0] > 60:
            _recientes.popleft()
        if len(_recientes) >= MAX_POR_MINUTO:
            raise HTTPException(429, "demasiados reportes seguidos")
        _recientes.append(ahora)


async def _leer_cuerpo(request: Request, tope: int) -> bytes:
    """Lee el cuerpo sin pasarse de [tope], aunque el cliente mienta en
    Content-Length o no lo mande."""
    declarado = request.headers.get("content-length")
    if declarado and declarado.isdigit() and int(declarado) > tope:
        raise HTTPException(413, "cuerpo demasiado grande")
    cuerpo = bytearray()
    async for trozo in request.stream():
        cuerpo += trozo
        if len(cuerpo) > tope:
            raise HTTPException(413, "cuerpo demasiado grande")
    return bytes(cuerpo)


@app.post("/report", dependencies=[Depends(exigir_token)], status_code=204)
async def reporte(request: Request, x_voicex_client: str | None = Header(default=None)):
    _limitar()
    texto = (await _leer_cuerpo(request, MAX_REPORTE)).decode("utf-8", errors="replace")
    try:
        json.loads(texto)
    except ValueError:
        raise HTTPException(400, "el reporte tiene que ser JSON")
    # El cuerpo va como cadena, no como objeto embebido: nada de lo que mande un
    # cliente puede inyectar estructura en el registro. Se lee con
    # `jq '.reporte | fromjson'`.
    linea = json.dumps({
        "ts": datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds"),
        "tester": TESTER,
        "app": x_voicex_client or "",
        "reporte": texto,
    }, ensure_ascii=False)
    REPORTES.mkdir(parents=True, exist_ok=True)
    # Se abre, se escribe y se cierra en cada reporte: así quien procesa puede
    # renombrar el archivo en cualquier momento sin que haya que avisarle a
    # este proceso (con nginx hacía falta `nginx -s reopen`).
    with (REPORTES / "reportes.jsonl").open("a", encoding="utf-8") as f:
        f.write(linea + "\n")
    log.info("reporte de %s (%d bytes)", x_voicex_client or "?", len(texto))


@app.put("/report/audio/{nota}", dependencies=[Depends(exigir_token)], status_code=204)
async def nota_de_voz(nota: str, request: Request):
    if not NOTA_RE.match(nota):
        raise HTTPException(404, "no existe")
    _limitar()
    audio = await _leer_cuerpo(request, MAX_NOTA)
    if not audio:
        raise HTTPException(400, "nota vacía")
    destino = REPORTES / "notas" / nota
    destino.parent.mkdir(parents=True, exist_ok=True)
    temporal = destino.with_suffix(".parte")
    temporal.write_bytes(audio)
    temporal.replace(destino)  # nunca queda una nota a medias a la vista
    log.info("nota de voz %s (%d KB)", nota, len(audio) // 1024)
