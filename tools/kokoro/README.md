# Servidor de voz Kokoro

Kokoro corre en la computadora, no en el teléfono. La app lo usa cuando está
accesible y **cae automáticamente a Edge TTS cuando no lo está**, así que tener
el servidor apagado nunca deja la app muda.

## Arrancar

```bash
docker compose -f tools/kokoro/docker-compose.yml up -d
docker compose -f tools/kokoro/docker-compose.yml logs -f   # esperar "Application startup complete"
```

El primer arranque tarda un poco: carga el modelo y 67 paquetes de voz.

## Cómo llega el teléfono hasta aquí

**Ya no escribiendo una IP.** Este servidor solo escucha en `127.0.0.1`: no
sabe autenticar a nadie, así que no puede estar expuesto ni siquiera a la WiFi
de casa. Todo entra por el proxy, que valida un token y limita el ritmo — ver
[`tools/proxy/README.md`](../proxy/README.md).

La dirección y el token van compilados en el APK
(`--dart-define-from-file`), no en un campo de Ajustes. El botón **Probar
conexión** de la app sigue estando, y ahora distingue "no responde" de "clave
rechazada".

Con el servidor apagado la app cae a Edge sola, así que nunca se queda muda.

## Voces

Las españolas propias de Kokoro (`ef_dora`, `em_alex`, `em_santa`) son las
únicas del catálogo **sin grado de calidad asignado**, y suenan flojas. Las
inglesas mejor calificadas —`af_heart` (A) y `af_bella` (A-)— dan mejor
resultado incluso leyendo español, que es por lo que son las de por defecto.

## El detalle del idioma

Kokoro deduce el idioma de la primera letra de la voz: `af_bella` empieza por
`a`, o sea inglés. Sin corregirlo, un párrafo español sale pronunciado con
reglas inglesas — el mismo texto dura 17 s en vez de 26 s y resulta
incomprensible.

La app lo evita mandando `lang_code` explícito en cada petición (`e` español,
`a` inglés). **Verificado en v0.8.1:** el mismo párrafo pasa de 17 s a 27,5 s y
llega con 71 timestamps por palabra.

En versiones anteriores a v0.8 el parámetro se ignora y hay que recurrir a la
variable `DEFAULT_VOICE_CODE`, como explica el compose. La app envía el campo
igualmente, así que funciona con ambas.

**Cómo comprobar que funciona:** sintetiza un párrafo español y mira cuánto
dura. Alrededor de 26 s es correcto; unos 17 s significa que lo está leyendo en
inglés.

## Formato de respuesta

A partir de v0.8 `/dev/captioned_speech` devuelve JSON con el audio en base64 y
los timestamps en el cuerpo, en lugar de audio crudo con los tiempos en una
cabecera. Es mejor: la cabecera tenía un techo de tamaño que un párrafo largo
podía rebasar. La app detecta el formato por el `content-type` y admite los dos.

La app pide además `stream: false`; por defecto el servidor responde con JSON
delimitado por saltos de línea, fragmento a fragmento.

## Rendimiento

Medido en CPU: unos 5 s para generar 26 s de audio (~5× tiempo real). Suficiente
para que la app vaya sintetizando el párrafo siguiente mientras suena el actual,
pero no instantáneo. De ahí que valga la pena la descarga por adelantado.

## Parar

```bash
docker compose -f tools/kokoro/docker-compose.yml down
```
