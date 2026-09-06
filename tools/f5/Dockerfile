# Servidor de voz F5-TTS en español para VoiceX Móvil.
#
# A diferencia de Kokoro y Piper, este necesita GPU, así que corre en la
# laptop y no en `voicex-server` -- el mismo sitio donde estaba Chatterbox, al
# que reemplaza (ver docs/context/TTS_ESPANOL.md).
FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-runtime

# ffmpeg convierte la salida a MP3: F5 emite WAV a 24 kHz y el WAV sin
# comprimir es la razón medida por la que Piper nunca se repartió.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir f5-tts fastapi uvicorn

# torchcodec llega como dependencia y espera CUDA 13, pero esta imagen trae
# 12.4: al importarse revienta con `libnvrtc.so.13: cannot open shared object
# file`. No hace falta para nada de lo que usamos, y sin él transformers cae
# al ffmpeg de arriba.
RUN pip uninstall -y torchcodec

COPY server.py /app/server.py
WORKDIR /app

# El checkpoint NO se hornea en la imagen: son ~1,3 GB y se baja al volumen
# montado la primera vez que arranca (ver `_asegurar_checkpoint`).
ENV F5_VOICES=/voices \
    F5_CKPT=/models/model.safetensors \
    F5_VOCAB=/models/vocab.txt

EXPOSE 8005
CMD ["uvicorn", "server:app", "--host", "0.0.0.0", "--port", "8005"]
