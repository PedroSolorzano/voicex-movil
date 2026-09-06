#!/usr/bin/env python3
"""Servidor HTTP para F5-TTS en español.

F5 trae una CLI y una demo de Gradio, pero ninguna sirve como servidor: la
CLI recarga el modelo en cada llamada (~20 s), que es justo lo que hay que
evitar cuando la app pide un párrafo tras otro.

Dos decisiones que vienen de problemas medidos, no de gusto:

**`/tts` es `def`, no `async def`.** FastAPI corre las funciones sincrónicas
en un hilo aparte, así que el bucle de eventos queda libre para contestar
`/health` mientras la GPU sintetiza. Chatterbox no hacía esto y por eso una
síntesis larga bloqueaba hasta su propio sondeo de salud, y la app lo leía
como servidor caído (`docs/bugs/CHATTERBOX_DESCARGAS.md`).

**`nfe_step` es 64 y no el 32 que trae F5 por defecto.** Con 32 aparecen
tartamudeos y repeticiones ("trabajo" -> "trabajo abajo"), verificado
transcribiendo la salida y comparándola con el texto pedido. A 64 la lectura
sale limpia y todavía va más rápido que tiempo real.

Sale MP3, no el WAV nativo de 24 kHz: el WAV sin comprimir es la razón medida
por la que Piper nunca se repartió a probadores (159 MB/hora, ver
`docs/context/ACCESO_REMOTO.md`).
"""
import io
import json
import os
import re
import subprocess
import threading
import time
from pathlib import Path

import numpy as np
import soundfile as sf
from fastapi import FastAPI, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

VOCES = Path(os.environ.get("F5_VOICES", "/voices"))
CKPT = os.environ.get("F5_CKPT", "/models/model.safetensors")
VOCAB = os.environ.get("F5_VOCAB", "/models/vocab.txt")
MODELO = os.environ.get("F5_MODEL", "F5TTS_Base")
NFE_POR_DEFECTO = int(os.environ.get("F5_NFE", "64"))
# Checkpoint español, CC0. La arquitectura es F5TTS_Base, verificada contra
# el transformer_config.yaml del propio repo (dim 1024, depth 22, heads 16).
REPO_HF = os.environ.get("F5_REPO", "jpgallegoar/F5-Spanish")

app = FastAPI(title="VoiceX F5-TTS")

_tts = None
_voces: dict[str, tuple[str, str]] = {}
_sustituciones: list[tuple[re.Pattern, str]] = []
# La GPU es una sola: dos síntesis a la vez no van más rápido, solo compiten
# por VRAM y arriesgan quedarse sin memoria en una tarjeta de 6 GB.
_turno = threading.Lock()


def _cargar_sustituciones() -> None:
    """Arreglos de pronunciación del modelo, no del libro.

    Acá van solo las palabras que este checkpoint pronuncia mal en cualquier
    texto -- "quizá" suena "guizás" y hay que escribirla `kizá`. Los nombres
    propios de cada libro NO van acá: eso depende del libro, no del motor.
    """
    ruta = VOCES / "sustituciones.json"
    if not ruta.exists():
        return
    crudo = json.loads(ruta.read_text(encoding="utf-8"))
    for original, reemplazo in crudo.items():
        patron = re.compile(rf"\b{re.escape(original)}\b", re.IGNORECASE)
        _sustituciones.append((patron, reemplazo))
    print(f"[f5] {len(_sustituciones)} sustituciones cargadas")


def _aplicar_sustituciones(texto: str) -> str:
    for patron, reemplazo in _sustituciones:
        def conservar_mayuscula(m: re.Match) -> str:
            return reemplazo.capitalize() if m.group(0)[:1].isupper() else reemplazo
        texto = patron.sub(conservar_mayuscula, texto)
    return texto


def _cargar_voces() -> None:
    """Cada voz es un .wav y un .txt con su transcripción exacta.

    F5 necesita las dos cosas: alinea la voz de referencia contra su texto.
    Dejar el .txt vacío lo obliga a transcribir con un ASR, que gasta VRAM y
    sale peor que escribir a mano lo que dice el audio.
    """
    for wav in sorted(VOCES.glob("*.wav")):
        txt = wav.with_suffix(".txt")
        if not txt.exists():
            print(f"[f5] {wav.name} sin .txt, se omite")
            continue
        _voces[wav.stem] = (str(wav), txt.read_text(encoding="utf-8").strip())
    print(f"[f5] voces: {', '.join(_voces) or '(ninguna)'}")


def _asegurar_checkpoint() -> None:
    """Baja el modelo español la primera vez, al volumen montado.

    No va dentro de la imagen a propósito: son ~1,3 GB que engordarían cada
    reconstrucción, y así se puede cambiar de checkpoint sin rearmar nada.
    """
    if Path(CKPT).exists() and Path(VOCAB).exists():
        return
    from huggingface_hub import hf_hub_download

    Path(CKPT).parent.mkdir(parents=True, exist_ok=True)
    print(f"[f5] bajando {REPO_HF} (una sola vez)")
    for archivo, destino in [("model_1250000.safetensors", CKPT),
                             ("vocab.txt", VOCAB)]:
        origen = hf_hub_download(REPO_HF, archivo)
        Path(destino).write_bytes(Path(origen).read_bytes())


@app.on_event("startup")
def arrancar() -> None:
    global _tts
    _asegurar_checkpoint()
    from f5_tts.api import F5TTS

    inicio = time.time()
    _tts = F5TTS(model=MODELO, ckpt_file=CKPT, vocab_file=VOCAB)
    _cargar_voces()
    _cargar_sustituciones()
    print(f"[f5] modelo listo en {time.time() - inicio:.1f} s")


class Peticion(BaseModel):
    text: str
    voice: str | None = None
    speed: float = 1.0
    nfe_step: int | None = None


@app.get("/health")
def salud() -> dict:
    """Sondeo barato: no toca la GPU ni espera a que termine una síntesis."""
    return {
        "status": "ok" if _tts is not None else "loading",
        "model": MODELO,
        "voices": sorted(_voces),
        "nfe_step": NFE_POR_DEFECTO,
        "busy": _turno.locked(),
    }


@app.post("/tts")
def sintetizar(p: Peticion) -> Response:
    if _tts is None:
        raise HTTPException(503, "el modelo todavía está cargando")
    if not p.text.strip():
        raise HTTPException(400, "texto vacío")

    nombre = p.voice or next(iter(_voces), None)
    if nombre not in _voces:
        raise HTTPException(404, f"voz desconocida: {nombre!r}")
    ref_wav, ref_txt = _voces[nombre]

    texto = _aplicar_sustituciones(p.text)

    with _turno:
        onda, sr, _ = _tts.infer(
            ref_file=ref_wav,
            ref_text=ref_txt,
            gen_text=texto,
            nfe_step=p.nfe_step or NFE_POR_DEFECTO,
            speed=p.speed,
            show_info=lambda *_: None,
            progress=None,
        )

    return Response(content=_a_mp3(onda, sr), media_type="audio/mpeg")


def _a_mp3(onda: np.ndarray, sr: int) -> bytes:
    """WAV en memoria -> ffmpeg -> MP3, sin archivos temporales."""
    buf = io.BytesIO()
    sf.write(buf, onda, sr, format="WAV", subtype="PCM_16")
    hecho = subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error",
         "-f", "wav", "-i", "pipe:0", "-b:a", "96k", "-f", "mp3", "pipe:1"],
        input=buf.getvalue(), capture_output=True,
    )
    if hecho.returncode != 0:
        raise HTTPException(500, f"ffmpeg falló: {hecho.stderr.decode()[:200]}")
    return hecho.stdout
