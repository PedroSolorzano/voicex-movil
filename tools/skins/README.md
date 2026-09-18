# Texturas de las pieles de biblioteca

Las pieles *Fichas* y *Clásica* de la biblioteca usan dos texturas que se
repiten como azulejo: `assets/skins/parchment.png` (el papel) y
`assets/skins/wood.png` (la madera de la barra superior).

**Se generan, no se descargan**, con [`generar_texturas.py`](generar_texturas.py):

```bash
python tools/skins/generar_texturas.py
```

Necesita Pillow y numpy. La razón de generarlas es que no hay licencia que
rastrear, y que se pueden retocar desde el código (tono, cantidad de manchas,
veta) en vez de buscar otra imagen que encaje.

## Por qué repiten sin costura

Todo el ruido se construye sobre una rejilla periódica (`periodic_noise`): el
borde derecho continúa al izquierdo y el de abajo al de arriba. La veta de la
madera es un seno con frecuencia entera sobre el ancho del azulejo, por el mismo
motivo. Si se cambia `SIZE` o la frecuencia (`13 * x`), tiene que seguir siendo
un entero de ciclos por azulejo o aparece una línea cada 256 px.

## El pergamino tiene que ser tenue

El texto de las fichas se lee encima, y la prueba de contraste
(`test/library_skin_test.dart`) mide la tinta contra el color **plano** del
papel de `LibrarySkin`, no contra la textura. Las manchas se mantienen por
debajo del 15 % de oscurecimiento (`0.10 * stains + 0.05 * grain`) para que esa
medición siga siendo verdad en la pantalla.

## Reemplazarlas

Cualquier PNG con el mismo nombre sirve sin tocar código: la app las pinta con
`ImageRepeat.repeat`. Si se reemplaza el pergamino por uno más oscuro, repetir
la medición de contraste a mano sobre la zona más oscura.

## Las fuentes

Van en `assets/fonts/` y no las genera nada: **Cinzel** (títulos, versalitas) y
**EB Garamond** (cuerpo y cursiva), ambas con licencia SIL OFL 1.1, bajadas del
repositorio `google/fonts`. La licencia exige que el texto viaje con la fuente:
por eso están `OFL-Cinzel.txt` y `OFL-EBGaramond.txt` al lado.

Son fuentes **variables** —Google Fonts ya no publica instancias estáticas de
estas dos familias—, así que el peso se elige con
`FontVariation('wght', …)`, no solo con `FontWeight`. Pesan 1,7 MB sin
comprimir, más de lo que costarían dos pesos estáticos.
