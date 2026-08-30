# Servidor de voz Piper para VoiceX Móvil.
#
# Piper no publica una imagen oficial, así que se arma aquí: es poco más que
# el paquete de PyPI, Flask para su servidor HTTP, y el modelo de voz.
FROM python:3.12-slim

# espeak-ng hace la conversión de texto a fonemas; sin él Piper no arranca.
RUN apt-get update \
    && apt-get install -y --no-install-recommends espeak-ng curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir piper-tts flask

# Voz por defecto: es_AR-daniela-high, la que mejor sonó en las pruebas de
# español. Cámbiala con VOICE_URL si prefieres otra de rhasspy/piper-voices.
ARG VOICE=es_AR-daniela-high
ARG VOICE_PATH=es/es_AR/daniela/high
WORKDIR /voices
RUN curl -fsSL -o "${VOICE}.onnx" \
      "https://huggingface.co/rhasspy/piper-voices/resolve/main/${VOICE_PATH}/${VOICE}.onnx" \
    && curl -fsSL -o "${VOICE}.onnx.json" \
      "https://huggingface.co/rhasspy/piper-voices/resolve/main/${VOICE_PATH}/${VOICE}.onnx.json"

ENV VOICE=${VOICE}
EXPOSE 5000

# --length-scale se deja en 1.0: la app lo manda en cada petición, así que se
# ajusta desde Ajustes sin reconstruir la imagen.
CMD ["sh", "-c", "python -m piper.http_server -m /voices/${VOICE}.onnx --host 0.0.0.0 --port 5000"]
