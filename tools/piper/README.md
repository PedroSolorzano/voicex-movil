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

## Voces: una por idioma

**Las voces de Piper están entrenadas cada una en un idioma.** No son
multilingües como las de Kokoro: darle texto en inglés a un modelo español
produce fonética española sobre palabras inglesas, algo directamente
incomprensible. Y el servidor **no avisa**: si le pides un modelo que no tiene,
responde 200 usando el que sea su modelo por defecto.

Por eso la imagen trae dos y la app manda cuál usar en cada petición:

| Idioma | Modelo |
|---|---|
| Español | `es_AR-daniela-high` |
| Inglés | `en_US-lessac-high` |

Para cambiarlos, edita `VOICE_ES` / `VOICE_EN` y sus rutas en el compose y
reconstruye. El catálogo está en
[rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices).

Probadas en español:

| Voz | Notas |
|---|---|
| `es_AR-daniela-high` | Argentina. La preferida; lee rápido a ritmo 1.0 |
| `es_MX-claude-high` | México. Comete errores de lectura |
| `es_MX-ald-medium` | México. Mismo problema |

## Ritmo

El deslizador **Ritmo** de Ajustes manda `length_scale` en cada petición: alarga
cada fonema al sintetizar, que suena más natural que frenar la reproducción.

**Cuidado con la dirección:** es *longitud de fonema*, así que números más altos
hablan más **pausado**. Bajarlo acelera.

- `0.90` — más rápido todavía
- `1.00` — ritmo propio de daniela, ya de por sí rápido
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
