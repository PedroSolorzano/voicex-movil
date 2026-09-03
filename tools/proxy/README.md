# Proxy de autenticación para Kokoro y Piper

Ni Kokoro-FastAPI ni el servidor de Piper saben autenticar: la "API key" de
Kokoro es la cadena literal `not-needed`, que existe solo porque el cliente de
OpenAI obliga a mandar algo. Publicar cualquiera de los dos tal cual deja la CPU
de esta máquina a disposición de quien encuentre la URL.

Este proxy es la pieza que lo arregla. Valida un token por probador, limita el
ritmo, deja pasar seis rutas y ninguna más, y registra quién usa qué.

```
teléfono ──HTTPS──► Funnel ──► 127.0.0.1:8080 (nginx)
                                    │  valida el token
                                    ├──► 127.0.0.1:8880  Kokoro
                                    └──► 127.0.0.1:5000  Piper
```

## Arranque

```bash
cp tools/proxy/tokens.conf.example tools/proxy/tokens.conf   # y edítalo
mkdir -p tools/proxy/logs && chmod 777 tools/proxy/logs
docker compose -f tools/proxy/docker-compose.yml up -d
```

`tokens.conf` y `logs/` están en `.gitignore`. No los subas: uno lleva
credenciales, el otro registros de personas.

Kokoro y Piper **deben** estar escuchando solo en `127.0.0.1` (así están sus
compose). Si vuelven a publicar en `0.0.0.0`, cualquiera en la WiFi entra por el
8880 saltándose todo esto y el proxy pasa a ser decorativo.

## Tokens

Generar uno:

```bash
openssl rand -base64 32 | tr -d '=+/'
```

Uno por persona, nunca compartido. No es un secreto fuerte —va dentro del APK,
que se puede descompilar— sino **un identificador revocable**: sirve para saber
de quién viene cada petición y para cortarle el paso a uno sin tocar a los
demás.

Revocar:

```bash
# borra su línea de tokens.conf, y luego
docker compose -f tools/proxy/docker-compose.yml exec proxy nginx -s reload
```

La recarga no corta las peticiones en curso. Al cerrar una ronda de pruebas,
rota todos los tokens: uno filtrado caduca solo.

## Log

`logs/access.jsonl`, una línea JSON por petición.

```bash
# Informe por probador
tools/proxy/report.sh
tools/proxy/report.sh 2026-09-03

# En crudo
jq -c 'select(.tester == "hermana1")' tools/proxy/logs/access.jsonl | tail -20

# Solo lo que falló
jq -c 'select(.status | startswith("2") | not)' tools/proxy/logs/access.jsonl
```

**Qué se guarda:** alias del probador, hora, ruta, método, código, duración,
bytes servidos, longitud del texto en caracteres, motor, número de intento y
versión del APK.

**Qué no se guarda, y no por olvido:**

- **El texto que se sintetiza.** Es el párrafo del libro que alguien está
  leyendo. Se registra su longitud, nunca su contenido. No es solo una promesa:
  el `log_format` no incluye `$request_body`, así que nginx ni lo retiene.
- **El token en claro.** La identidad viaja como alias.
- **La IP completa.** Solo la /24. La IP de una conexión móvil dice operador y
  zona aproximada de un familiar, y el alias ya identifica quién es.

## Reportes de los probadores

Dos rutas más, con el mismo token y un ritmo propio más estricto (10/min: un
reporte es un acto humano, no un bucle).

```bash
# Lo que han contado, más reciente al final
jq -r '"\(.ts[11:19])  \(.tester)  \(.reporte | fromjson | .tipo)"' tools/proxy/logs/reportes.jsonl

# Un reporte entero
jq -r 'select(.tester == "hermana1") | .reporte | fromjson' tools/proxy/logs/reportes.jsonl

# Notas de voz
ls tools/proxy/logs/notas/
```

El cuerpo se guarda como **cadena**, no como objeto: con `escape=json` nginx ya
lo escapa, y entre comillas nada de lo que mande un cliente puede inyectar
estructura en el log. De ahí el `fromjson`.

Aquí sí se registra el cuerpo de la petición, y no contradice la regla de
arriba: el cuerpo de `/report` **es** el reporte, no el párrafo de un libro.
Que la app no meta texto del libro ahí lo garantiza su propio saneo, que tiene
tests.

Los reportes duran lo que dure la ronda, no catorce días: son el producto que se
busca. **Las notas de voz se borran en cuanto se ha actuado sobre ellas**, que
son la voz de una persona.

**Cuánto tiempo:** rotación diaria y 14 días de retención para el log de acceso,
con `rotate.sh` desde el cron del host:

```cron
5 4 * * * /home/pedro/Repos/Personales/VoiceXMovil/tools/proxy/rotate.sh
```

Al terminar la ronda: genera el informe agregado y borra los crudos. El
agregado no caduca; las líneas individuales sí.

## Comprobar que sigue cerrado

```bash
TOK=$(grep -oP '"Bearer \K[^"]+' tools/proxy/tokens.conf | head -1)
code() { curl -s -o /dev/null -w '%{http_code}\n' "$@"; }

code http://127.0.0.1:8080/kokoro/health                                  # 401
code -H "Authorization: Bearer inventado" http://127.0.0.1:8080/kokoro/health  # 401
code -H "Authorization: Bearer $TOK" http://127.0.0.1:8080/kokoro/docs    # 404
code -H "Authorization: Bearer $TOK" http://127.0.0.1:8080/kokoro/health  # 200
code -X POST -H "Authorization: Bearer $TOK" http://127.0.0.1:8080/kokoro/health  # 403

# La puerta trasera: desde otra máquina de la WiFi, esto no debe responder.
curl -m 5 http://<IP-de-esta-máquina>:8880/health
```

## Si un token se filtra

1. Borra su línea de `tokens.conf` y recarga. El resto sigue funcionando.
2. `tools/proxy/report.sh` dice qué se hizo con él y desde qué redes.
3. Si hay uso ajeno, `tailscale funnel off` y se acabó la exposición.
4. Compila un APK nuevo para esa persona con un token nuevo.

## Límites que hay puestos

| Qué | Valor | Por qué |
|---|---|---|
| Peticiones por token | 60/min, ráfaga 20 | Kokoro tarda ~5 s por párrafo y la descarga va en serie: el uso legítimo no pasa de ~12/min |
| Conexiones por token | 2 | Leer y descargar a la vez, nada más |
| Peticiones por IP | 120/min, ráfaga 40 | Que el ruido de escaneo no consuma trabajadores |
| Tamaño de petición | 32 kB | Un párrafo, no un libro |
| Rutas | 6 exactas | Kokoro publica además `/docs`, `/redoc` y `/v1/models`, que no tienen por qué existir de cara a internet |

Superar el ritmo devuelve **429**, no un corte: la app lo distingue de un
servidor caído.
