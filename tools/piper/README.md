# Servidor de voz Piper

Alternativa a Kokoro con voces **entrenadas en cada idioma**, no prestadas. Es
el más rápido de los tres motores: ~1,7 s para generar 26 s de audio.

## Arrancar

```bash
docker compose -f tools/piper/docker-compose.yml up -d --build
```

La primera construcción descarga el modelo (~110 MB para daniela-high).

Luego, en la app: **Ajustes → Motor de voz → Piper**, y la dirección
`http://<IP-de-la-computadora>:5000`.

## Voces

La imagen trae `es_AR-daniela-high` por defecto, la que mejor resultado dio en
las pruebas de español. Para cambiarla, edita `VOICE` y `VOICE_PATH` en el
compose y reconstruye. El catálogo completo está en
[rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices).

Probadas en español:

| Voz | Notas |
|---|---|
| `es_AR-daniela-high` | Argentina. La preferida; lee rápido a ritmo 1.0 |
| `es_MX-claude-high` | México. Comete errores de lectura |
| `es_MX-ald-medium` | México. Mismo problema |
| `es_ES-*` | Varias de España, sin probar |

## Ritmo

El deslizador **Ritmo** de Ajustes manda `length_scale` en cada petición: alarga
cada fonema al sintetizar, que suena más natural que frenar la reproducción.

- `1.00` — ritmo propio de daniela, rápido
- `1.25` — cómodo para seguir con atención
- `1.60` — al nivel de una lectura pausada normal

**Ojo:** va grabado dentro del audio, así que cambiarlo invalida lo ya
descargado. Para variar la velocidad sobre la marcha sin regenerar nada, usa el
control de velocidad de reproducción del lector.

## Lo que Piper no hace

**No devuelve tiempos por palabra.** Su API contempla alineaciones por fonema,
pero los modelos españoles las devuelven vacías. La app lo detecta y calcula el
resaltado por oración de forma aproximada.

Para escuchar —sobre todo conduciendo— da igual. Si quieres seguir el texto
palabra por palabra, usa Kokoro o Edge, que sí los proveen.

## Parar

```bash
docker compose -f tools/piper/docker-compose.yml down
```
