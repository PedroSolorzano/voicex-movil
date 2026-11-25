# Cómo usar las herramientas del Mac

Todo lo que corre en el Mac (servidor de voz, reportes, audios por cable,
compilar) se lanza desde la terminal. Esta guía dice **desde dónde**, **con qué
comando** y qué hacer cuando la terminal contesta `command not found` o
`no such file or directory`.

## 1. Ponerse en la ruta correcta

Casi todos los comandos son rutas **relativas a la raíz del proyecto**
(`tools/...`). Si la terminal está en otra carpeta, fallan con
`no such file or directory`. Hay dos maneras de no pensarlo:

**La cómoda, una sola vez.** Agrega esta línea a `~/.zshrc` y abre una terminal nueva:

```bash
alias voicex='source ~/Projects/Personal/voicex-movil/tools/entorno.sh'
```

Desde entonces, en cualquier terminal, escribes `voicex`. Eso:

- te lleva a la carpeta del proyecto;
- agrega `adb`, `ffmpeg` y Java al PATH;
- crea atajos: `servidor`, `reportes`, `bajar`, `pasar`, `traer-libros`, `compilar`;
- te dice si ve el celular conectado.

**La directa, sin configurar nada:**

```bash
cd ~/Projects/Personal/voicex-movil
source tools/entorno.sh
```

Debe ser **`source`**, no `./entorno.sh`: un script ejecutado normal cambia la
carpeta y el PATH de *su propio* proceso, que desaparece al terminar.

## 2. Si dice "command not found" o "el ejecutable no está en la ruta"

| Mensaje | Causa | Qué hacer |
|---|---|---|
| `command not found: adb` | `adb` vive en el SDK de Android, que Homebrew no pone en el PATH | `voicex` (o `source tools/entorno.sh`). Los scripts `pasar.sh` y `traer-libros.sh` además lo buscan solos en `/opt/homebrew/share/android-commandlinetools/platform-tools` |
| `command not found: dart` / `flutter` | Homebrew no está en el PATH de esa terminal | `export PATH=/opt/homebrew/bin:$PATH`, o `voicex` |
| `no such file or directory: tools/...` | No estás en la raíz del proyecto | `cd ~/Projects/Personal/voicex-movil`, o `voicex` |
| `permission denied` al correr un `.sh` | Perdió el permiso de ejecución | `chmod +x tools/audios/*.sh tools/reportes/procesar.sh tools/release/compilar.sh tools/mlx/arrancar.sh` |
| `ffmpeg` no se encuentra al sintetizar | El servidor lo busca en `~/.local/bin` | `tools/mlx/arrancar.sh` ya lo agrega; si arrancas `uvicorn` a mano, no |
| `Falta el entorno` al arrancar el servidor | No existe `tools/mlx/.venv` | Ver «Instalación» en `tools/mlx/README.md` |
| `procesar.sh` no hace nada y sale sin mensaje | Hay otra corrida en curso (candado) | Espera a que termine; si se quedó colgado: `rmdir tools/reportes/estado/.lock.d` |
| `procesar.sh`: `.venv/bin/python3: No such file` | Falta el entorno de reportes | `cd tools/reportes && uv venv --python 3.12 .venv && uv pip install --python .venv/bin/python -r requirements.txt` |
| `adb pull`: `remote open failed: Permission denied` | La app crea sus archivos en modo 600 y `adb` corre como otro usuario | Tocar de nuevo *Dejar mis libros listos para el Mac* (la app los deja en 644 desde la 0.13.1) |
| `adb push`: `secure_mkdirs failed: Operation not permitted` | `adb push` no puede crear carpetas dentro de `Android/data` | Ya lo resuelve `pasar.sh` (crea la carpeta antes). Si empujas a mano: `adb shell mkdir -p <ruta>` primero, y sin tildes en el nombre |
| «ese libro no está en tu biblioteca» al importar | El EPUB con el que generaste no es byte a byte el de la app (otra edición del mismo libro) | Genera con el que sale de `traer-libros.sh` |
| `adb: no devices/emulators found` | Celular desconectado o sin depuración USB | Cable, desbloquear, aceptar «¿Permitir depuración USB?», y `adb devices` debe decir `device` (no `unauthorized`) |

`.venv` **no** va en el PATH ni se «activa»: los scripts llaman al Python de su
propio `.venv` con ruta completa. Por eso `procesar.sh` y `arrancar.sh` funcionan
aunque no actives nada.

## 3. Comandos

Todos desde la raíz del proyecto (`voicex` te deja ahí).

### Servidor de voz (el Mac sirve Qwen3 y Chatterbox)

```bash
tools/mlx/arrancar.sh        # o: servidor        — puerto 8765, token en tools/mlx/.token
```

Déjalo corriendo en su propia terminal. `Ctrl+C` lo detiene. Detalles:
`tools/mlx/README.md`.

### Reportes de testers («Contar un problema»)

```bash
tools/reportes/procesar.sh --dry-run    # ver qué haría, sin escribir nada
tools/reportes/procesar.sh              # o: reportes — vuelca a docs/bugs y docs/tasks
```

Transcribe las notas de voz **en este Mac** (nunca en la nube) y las pasa a
`docs/bugs/REPORTES_TESTERS.md` y `docs/tasks/IMPROVEMENTS.md`. Detalles:
`tools/reportes/README.md`.

### Audios por cable: generar en el Mac, escuchar sin red

Teléfono conectado por USB, servidor corriendo. Detalles: `tools/audios/README.md`.

```bash
# 0. En la app: Ajustes → Almacenamiento → Ver qué ocupa cada libro →
#    «Dejar mis libros listos para el Mac». Luego, en el Mac:
tools/audios/traer-libros.sh                       # o: traer-libros → epubs/del-telefono/

#    (también deja un inventario de lo que ya tienes: bajar.dart lo usa para
#     no generar de nuevo lo que el teléfono ya tiene)

# 1. Qué capítulos hay, cuántas horas de escucha son, cuáles ya tiene el teléfono
#    y cómo partir los largos
dart run tools/audios/bajar.dart "epubs/del-telefono/Visión ciega.epub" --lista

# 2. Generar (un capítulo, un rango, o solo ~1,2 horas de uno largo)
dart run tools/audios/bajar.dart "epubs/del-telefono/Visión ciega.epub" 3
dart run tools/audios/bajar.dart "epubs/del-telefono/Visión ciega.epub" 4 --horas 1.2
dart run tools/audios/bajar.dart "epubs/del-telefono/Visión ciega.epub" 4 --desde 340 --horas 1.2
#    (--horas imprime el comando exacto para la siguiente parte)

# 3. Pasar al teléfono
tools/audios/pasar.sh                              # o: pasar

# 4. En la app: Ajustes → Almacenamiento → Ver qué ocupa cada libro →
#    «Importar audios del Mac»
```

Con los atajos de `voicex`: `bajar "epubs/del-telefono/Visión ciega.epub" 3`.

Las comillas son obligatorias cuando el nombre lleva espacios o tildes.

### Compilar e instalar en el celular

```bash
tools/release/compilar.sh -l -i      # o: compilar -l -i   (-l si cambió la versión, -i instala por adb)
```

Nunca `flutter build apk` a mano: ver `CLAUDE.md` y `tools/release/README.md`.

### Pruebas y análisis

```bash
flutter analyze && flutter test
```

## 4. Orden típico de una tarde de escucha

1. `voicex` → `servidor` (en una terminal aparte).
2. Conectar el celular. `traer-libros` si agregaste libros nuevos.
3. `bajar "<libro>.epub" <capítulos> --horas 1.2` (repetir para las siguientes partes).
4. `pasar` → en la app, *Importar audios del Mac*.
5. Desconectar y escuchar sin red.
