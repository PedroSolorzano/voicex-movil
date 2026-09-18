# Verificación en teléfono de 0.10.0-preview.1

**Fecha:** 2026-09-18, 06:43–06:47. Samsung R3CR702WCDZ, Android en modo
oscuro, piel de biblioteca *Clásica*. APK compilado con
`compilar.ps1 -Limpio -Instalar` desde `feat/rangos-lector` (`318699e`).

Verificación rápida, sin corregir nada: solo se documenta, por pedido
explícito. Se corrige en la siguiente sesión.

---

## Lo que funciona

- **Instalación y versión**: `versionName=0.10.0-preview.1` dentro del APK,
  motores F5, Kokoro y Piper confirmados en el binario.
- **Migración 8 → 9**: actualizando sobre 0.9.1, los libros, las portadas y el
  progreso (*El talismán* 22 %) siguen intactos.
- **Cabecera de rango** en piel Clásica, como ex libris: `Lector novel · Nivel
  1`, `0 páginas`, `Faltan 40 para Aprendiz`.
- **Crédito por escuchar**: ~75 s de audio de *El talismán* con Edge (cap. 10,
  unos cinco párrafos) → la cabecera pasa a `0,8 páginas`, `Faltan 39`, y la
  barra se mueve. El refresco al volver del lector funciona.
- **Tu progreso**: cita del día (Bacon), rango, páginas hoy/semana/total, cifra
  de INEGI con su fuente, escalera de rangos con el actual marcado. Fondo de
  pergamino correcto con el teléfono en modo oscuro.
- **Recordatorio diario**: el interruptor abre el selector de hora; al aceptar
  queda `Todos los días a las 21:30` y `dumpsys alarm` muestra la alarma de
  `ScheduledNotificationReceiver` para `2026-09-18 21:30`. No hubo diálogo de
  permiso: `POST_NOTIFICATIONS` ya estaba concedido por la notificación del
  audio.
- **Log**: ninguna excepción de Flutter ni `reading credit failed` en
  `logcat` durante toda la prueba.

**Quedó encendido** el recordatorio de las 21:30, para comprobar esta noche que
la notificación llega de verdad y que tocarla abre *Tu progreso*. Se apaga en
Ajustes → Biblioteca.

---

## Hallazgos

Los cuatro quedaron corregidos el mismo 2026-09-18: `bfe9683` (lomo),
`abcbae4` (selector en español), `3069737` ("hacia las") y `2bb2c55` (semana
vacía). Se deja la descripción original de cada uno.

### 1. El lomo "En curso" no deja leer el título — error visual · corregido

En *Tu pila de libros*, sin libros terminados, el único lomo dice
`EN CURSO: E…`. Su ancho es la fracción leída del libro
(`widthFactor: (c.at / c.totalParagraphs).clamp(0.25, 1.0)`,
`lib/ui/widgets/book_tower.dart`), así que con 22 % leído queda en el mínimo
de 25 % del ancho y el título no cabe.

La idea era que el lomo "creciera" con el avance, pero comunica peor que un
lomo entero: nadie entiende que la anchura es el progreso, y sí nota que el
título está cortado. **Propuesta**: lomo del ancho normal y el progreso como
relleno translúcido dentro de él (o el porcentaje escrito: `En curso · 22 % —
El talismán`).

### 2. El selector de hora sale en inglés — menor · corregido

`showTimePicker` muestra **Cancel** y **OK**. La app no tiene
`flutter_localizations` (está anotado en `IMPROVEMENTS.md`, "La app solo habla
español"), así que los diálogos de Material salen en inglés. Es el primer
diálogo de Material con botones de texto que aparece en la app, por eso no se
había notado.

**Arreglo mínimo** sin traducir toda la app: agregar `flutter_localizations`
con `locale: Locale('es')`, `supportedLocales` y los tres
`localizationsDelegates` en `MaterialApp.router` (`lib/ui/app.dart`). Eso
traduce los diálogos de Material (selector de hora, `showDatePicker`, menús
de copiar/pegar) sin tocar ninguna cadena propia.

### 3. El recordatorio puede llegar hasta una hora tarde — decisión de diseño · corregido con el texto

La alarma es inexacta a propósito (`inexactAllowWhileIdle`, para no pedir
`SCHEDULE_EXACT_ALARM`), y Android le dio **una ventana de una hora**
(`window=+1h0m0s0ms` en `dumpsys alarm`): la de las 21:30 puede llegar a las
22:30. En cambio, Ajustes promete *"Todos los días a las 21:30"*.

Dos salidas: decir la verdad en el texto (*"hacia las 21:30"*), o usar
`AndroidScheduleMode.exactAllowWhileIdle` solo para el recordatorio diario,
que en Android 14+ exige el permiso de alarmas exactas y un paso más para
quien lo encienda. Se inclina por lo primero: un recordatorio para leer no
necesita puntualidad de despertador.

### 4. Una semana sin lectura deja un hueco grande — cosmético · corregido

*Los últimos siete días* reserva 120 px de alto aunque todos los días estén en
cero: queda un bloque vacío con siete rayitas abajo. Con lectura se ve bien.
Sin ella convendría una línea como *"Todavía no hay lectura esta semana"* en
vez del gráfico vacío.

---

## Lo que no se alcanzó a probar

- Crédito por **lectura en silencio** (desplazar 1–3 párrafos y que sume;
  saltar desde el índice y que no).
- Cabecera y *Tu progreso* en las pieles **Moderna** y **Fichas**.
- **Subir de rango** y **terminar un libro** (los `SnackBar`): hacen falta 40
  páginas o el final de un libro; con *Alice* se puede.
- El **resumen semanal**: se programa para el domingo 20:00 y solo si hubo
  lectura en la semana.
- Que tocar la notificación abra *Tu progreso* (se verá esta noche).
