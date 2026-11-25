# Audios generados en el Mac, para llevarlos por cable

Para escuchar sin descargar en tiempo real: generas capítulos completos en el
Mac, conectas el teléfono y los pasas. Quedan como cualquier descarga: se oyen
sin conexión y aparecen en *Descargas y caché*.

**¿Solo quieres los comandos?** Están, uno por paso y listos para copiar, en
[`docs/context/USO_HERRAMIENTAS.md`](../../docs/context/USO_HERRAMIENTAS.md#inicio-rápido-bajar-audio-y-pasarlo-al-celular).

```
bajar.dart  ──►  tools/audios/salida/<libro>/  ──►  pasar.sh (adb)  ──►  teléfono  ──►  «Importar audios del Mac»
```

## 0. El EPUB tiene que ser el del teléfono

La app reconoce el audio por el **hash del archivo**, no por el título: otra
copia del mismo libro, u otra edición, no coincide. Por eso el Mac no debe usar
el EPUB que tenga a mano, sino el que tiene el teléfono. Con el cable puesto:

1. En la app: *Ajustes → Almacenamiento → Ver qué ocupa cada libro → Dejar mis
   libros listos para el Mac*.
2. En el Mac: `tools/audios/traer-libros.sh`. Los deja, con el nombre del libro,
   en `epubs/del-telefono/`.

Ese mismo botón deja también un **inventario** (`inventario.json`) de lo que el
teléfono ya tiene descargado, por libro y por voz. `traer-libros.sh` lo trae junto
a los EPUB, y `bajar.dart` lo lee solo (si está junto al EPUB) para **no generar
lo que el teléfono ya tiene**: `--lista` marca por capítulo cuántos párrafos hay
ya en el teléfono, y al generar salta esos. Lo saltado tampoco gasta el tope de
`--horas`. Es una foto del momento: si descargaste algo desde entonces, repite
los dos pasos. `--sin-inventario` lo ignora y `--inventario <archivo>` usa otro.

Desde ahí se usan en los comandos de abajo. (Los libros que importes después,
con una copia en el Mac o sin ella, se traen igual repitiendo los dos pasos.)

## 1. Ver los capítulos

Para saber qué número tiene cada capítulo, sin más ruido, `--indice` imprime una
tabla corta (número, título, párrafos y cuántos ya tiene el teléfono). Y al
generar se puede pedir el capítulo **por nombre** (`Teseo`) en vez de por número.

```bash
dart run tools/audios/bajar.dart "epubs/Visión ciega.epub" x --lista
```

Los números son los de la app (1 = el primero). Cada capítulo dice cuántos
párrafos tiene, **cuántas horas de escucha son** a velocidad estándar y cuánto
tarda en generarse (~35 min por cada hora de audio en este Mac). Los de más de
hora y media salen con una sugerencia para partirlos: Teseo, de ~3 h 38 min, se
propone en 3 partes de ~1 h 13 min. Son estimaciones medidas con 361 párrafos de
Chatterbox (17,7 caracteres por segundo hablado; el servidor genera 1,8 veces
más rápido que el tiempo real), no un cronómetro.

## 2. Generar

El servidor de voz tiene que estar corriendo (`tools/mlx/arrancar.sh`).

```bash
dart run tools/audios/bajar.dart "epubs/Visión ciega.epub" 3          # un capítulo
dart run tools/audios/bajar.dart "epubs/Visión ciega.epub" 3-5        # varios
dart run tools/audios/bajar.dart "epubs/Visión ciega.epub" 3 --desde 45   # desde el párrafo 45
dart run tools/audios/bajar.dart "epubs/Visión ciega.epub" 3 --motor qwen3
```

- Usa el **mismo lector de EPUB que la app** (`lib/epub/parser.dart`), así que el
  párrafo N de aquí es el párrafo N del teléfono.
- Por defecto, Chatterbox con la voz `colombiana`; con `--motor qwen3`, la
  `esposa`. `--voz` elige otra.
- **`--horas 1.2` genera solo ~1,2 horas de audio** y para en un límite de párrafo.
  Al terminar imprime el comando exacto para la siguiente parte (con su
  `--desde`), así un capítulo de 4 o 6 horas se hace en 3 o 4 tandas cortas, y
  cada una se puede pasar al teléfono antes de empezar la siguiente.
- Se puede cortar con Ctrl+C y repetir el mismo comando: continúa donde quedó, y
  lo que ya está generado no se vuelve a pedir.
- Solo libros en español: los demás los lee Edge en la app, y este audio no se
  usaría.

## 3. Pasar al teléfono

Teléfono por cable, depuración USB aceptada:

```bash
tools/audios/pasar.sh
```

Después, en la app: **Ajustes → Almacenamiento → Ver qué ocupa cada libro →
Importar audios del Mac**. Los archivos se **mueven** a la app (no quedan dos
copias en el teléfono) y ahí mismo te dice cuántos párrafos entraron.

## Si algo no entra

La app lo dice por carpeta y deja lo pendiente donde está para reintentar:

| Mensaje | Qué pasa |
|---|---|
| "ese libro no está en tu biblioteca" | El libro se reconoce por el hash del EPUB: hay que haber importado **ese mismo archivo** en la app. |
| "audio de otro formato" | La app cambió su formato de caché; regenera con `bajar.dart`. |
| "la voz … es de un motor que la app no tiene" | Motor retirado (Kokoro, Piper, F5). |

El audio generado aquí no lleva marcas de tiempo por palabra, igual que las
descargas de Qwen3 y Chatterbox: el resaltado reparte el tiempo por la longitud.
