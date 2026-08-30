# Servidor de voz Piper para VoiceX Móvil.
#
# Piper no publica una imagen oficial, así que se arma aquí: es poco más que
# el paquete de PyPI, Flask para su servidor HTTP, y los modelos de voz.
#
# Las voces de Piper están entrenadas una por idioma, así que hace falta un
# modelo por cada idioma que se quiera leer. Van todos al mismo directorio y
# la app elige cuál usar en cada petición.
FROM python:3.12-slim

# espeak-ng hace la conversión de texto a fonemas; sin él Piper no arranca.
RUN apt-get update \
    && apt-get install -y --no-install-recommends espeak-ng curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir piper-tts flask

ARG VOICE_ES=es_AR-daniela-high
ARG VOICE_ES_PATH=es/es_AR/daniela/high
ARG VOICE_EN=en_US-lessac-high
ARG VOICE_EN_PATH=en/en_US/lessac/high

WORKDIR /voices
RUN set -eux; \
    base="https://huggingface.co/rhasspy/piper-voices/resolve/main"; \
    for pair in "${VOICE_ES}:${VOICE_ES_PATH}" "${VOICE_EN}:${VOICE_EN_PATH}"; do \
      name="${pair%%:*}"; path="${pair#*:}"; \
      curl -fsSL -o "${name}.onnx"      "${base}/${path}/${name}.onnx"; \
      curl -fsSL -o "${name}.onnx.json" "${base}/${path}/${name}.onnx.json"; \
    done

ENV DEFAULT_VOICE=${VOICE_ES}
EXPOSE 5000

# --data-dir permite servir cualquier modelo del directorio: la app manda el
# nombre en cada petición y el servidor lo carga bajo demanda.
# --length-scale se deja en 1.0 porque la app también lo manda por petición.
CMD ["sh", "-c", "python -m piper.http_server -m /voices/${DEFAULT_VOICE}.onnx --data-dir /voices --host 0.0.0.0 --port 5000"]
