# Edge TTS WebSocket — Registro de Error 403

**Archivo afectado:** `lib/tts/edge_tts_provider.dart`  
**Error persistente:** `WebSocketException: Connection to 'wss://speech.platform.bing.com/...' was not upgraded to websocket, HTTP status code: 403`

---

## Descripción del protocolo

El proveedor Edge TTS se conecta vía WebSocket a:
```
wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1
```

La autenticación usa tres mecanismos obligatorios:
1. `TrustedClientToken` — constante fija en la URL
2. `Sec-MS-GEC` — hash SHA-256 dinámico basado en el tiempo (ventana de 300 s)
3. `Cookie: muid=<32 hex aleatorio>` — en las cabeceras HTTP

**Fuente de verdad:** [`rany2/edge-tts`](https://github.com/rany2/edge-tts) (Python)

---

## Historial de fixes aplicados

### Fix 1 — Agregar token Sec-MS-GEC (primer error: "was not upgraded to websocket")
**Fecha:** 2026-04-29  
**Síntoma:** `WebSocketException: Connection was not upgraded to websocket` (sin código HTTP)  
**Causa:** No se enviaba el token `Sec-MS-GEC` ni los headers de autenticación. Se usaba `web_socket_channel` sin headers.  
**Cambios:**
- Reemplazado `web_socket_channel` por `dart:io` `WebSocket.connect()` con headers custom
- Agregado paquete `crypto: ^3.0.7` al `pubspec.yaml`
- Implementada función `_generateSecMsGec()` con SHA-256
- Agregados headers: `Origin`, `User-Agent`, `Pragma`, `Cache-Control`, `Accept-Encoding`, `Accept-Language`
- Agregado `TrustedClientToken` y `Sec-MS-GEC` a la URL

**Resultado:** Error cambia a HTTP 403

---

### Fix 2 — Corrección del cálculo del epoch de Windows (primer 403)
**Fecha:** 2026-04-29  
**Síntoma:** HTTP 403  
**Causa:** El cálculo de `Sec-MS-GEC` usaba `unixSec - 11644473600` (resta) en vez de suma. El epoch de Windows (01/01/1601) está ANTES del epoch de Unix (01/01/1970), por lo que hay que SUMAR el offset.  
**Fórmula correcta:**
```dart
var ticks = unixSec + 11644473600;  // +, no -
ticks -= ticks % 300;               // redondear hacia abajo a múltiplo de 300
ticks *= 10000000;                  // convertir a intervalos de 100 nanosegundos
```
**Resultado:** 403 persiste — había más causas

---

### Fix 3 — Versión de Chromium desactualizada + User-Agent format + MUID cookie (403 persistente)
**Fecha:** 2026-04-29  
**Síntoma:** HTTP 403 persistente  
**Causa (3 problemas identificados):**
1. `_chromiumVersion = '130.0.2849.68'` — Chrome 130 era de oct 2024. Microsoft valida que la versión sea reciente.
2. User-Agent usaba versión completa (`Chrome/130.0.2849.68`) en vez del formato `Chrome/143.0.0.0` (mayor + `.0.0.0`)
3. Faltaba el header `Cookie: muid=<32 hex uppercase>` — requerido por el servidor

**Fuente verificada:** [`constants.py`](https://github.com/rany2/edge-tts/blob/master/src/edge_tts/constants.py) del repo oficial

**Cambios:**
```dart
const _chromiumFullVersion = '143.0.3650.75';
const _chromiumMajorVersion = '143';

// User-Agent: Chrome/143.0.0.0 Safari/537.36 Edg/143.0.0.0
// Cookie: muid=<UUID v4 sin guiones, uppercase>
```
**Resultado:** 403 persiste — causas adicionales descubiertas

---

### Fix 4 — Clock skew correction + MUID con Random.secure() + orden de parámetros URL
**Fecha:** 2026-04-29  
**Síntoma:** HTTP 403 persistente  
**Causa:** La librería Python tiene un mecanismo de corrección de desfase de reloj (`DRM.clock_skew_seconds`) que nosotros no teníamos. Si el reloj del dispositivo difiere del reloj del servidor de Microsoft por más de unos segundos cruzando un límite de 300 s, el token `Sec-MS-GEC` cae en la ventana incorrecta.

**Fuente verificada:** [`drm.py`](https://github.com/rany2/edge-tts/blob/master/src/edge_tts/drm.py) del repo oficial

**Cambios:**
- `_clockSkewSeconds` persistente a nivel de módulo
- Método `_adjustClockSkew()`: hace GET al endpoint de voces, lee header `Date`, calcula diferencia con reloj local
- Loop de reintento en `synthesize()`: en el primer 403, corrige el skew y reintenta
- MUID cambiado de UUID v4 (bits constrained) a `Random.secure()` (verdaderamente aleatorio, igual que Python's `secrets.token_hex(16)`)
- Orden de parámetros URL ajustado a: `TrustedClientToken → ConnectionId → Sec-MS-GEC → Sec-MS-GEC-Version`

**Código clave:**
```dart
// Retry con skew correction, igual que Python DRM retry
for (var attempt = 0; attempt <= 1; attempt++) {
  try {
    return await _synthesizeOnce(...);
  } on WebSocketException catch (e) {
    if (attempt == 0 && e.message.contains('403')) {
      await _adjustClockSkew();
      continue;
    }
    rethrow;
  }
}
```
**Resultado:** 403 persiste — causa raíz aún sin confirmar

---

### Fix 5 — Logging en release mode (diagnóstico)
**Fecha:** 2026-04-29  
**Síntoma:** Imposible diagnosticar porque `debugPrint()` no funciona en release builds  
**Cambio:** Reemplazado `debugPrint()` por `dart:developer`'s `dev.log()` que funciona en AMBOS modos (debug y release)  
**Cómo ver los logs:**
```bash
adb logcat -s flutter 2>&1 | grep -i edgetts
```

---

---

### Fix 6 — CAUSA RAÍZ ENCONTRADA: headers duplicados por `WebSocket.connect()` ✅
**Fecha:** 2026-04-30  
**Síntoma:** HTTP 403 persistente en todos los intentos anteriores  

**Diagnóstico:** Se construyó un script Dart de prueba que comparó:
1. Handshake manual con `HttpClient.getUrl()` + `req.headers.set()` → **101 OK** ✅
2. `WebSocket.connect()` con headers custom → **403** ❌
3. `WebSocket.connect()` con `customClient` (userAgent=null, sin Sec-WebSocket-Version) → **✅ CONECTADO**

**Causa raíz:** `dart:io`'s `WebSocket.connect()` usa `headers.add()` (NO `set()`) para aplicar los headers custom. `add()` agrega el valor en lugar de reemplazarlo. Esto produce headers DUPLICADOS:

| Header | Quién lo agrega | Resultado |
|--------|----------------|-----------|
| `User-Agent: Dart/3.x (dart:io)` | `HttpClient` automáticamente | → dos User-Agent |
| `User-Agent: Mozilla/5.0...Edge` | Nuestros custom headers vía `add()` | → servidor rechaza con 403 |
| `Sec-WebSocket-Version: 13` | WebSocket framework vía `set()` | → duplicado |
| `Sec-WebSocket-Version: 13` | Nuestros custom headers vía `add()` | → `13, 13` → 403 |

**Cambios:**
```dart
// 1. Quitar 'Sec-WebSocket-Version' de _buildHeaders() — Dart lo agrega solo
// 2. Crear HttpClient con userAgent=null para suprimir "Dart/3.x (dart:io)"
// 3. Pasar el HttpClient via customClient

final httpClient = HttpClient()..userAgent = null;
final ws = await WebSocket.connect(
  wsUrl,
  headers: _buildHeaders(muid),   // sin Sec-WebSocket-Version
  customClient: httpClient,        // sin "Dart/3.x" User-Agent
);
```

**Resultado:** ✅ WebSocket conecta exitosamente (confirmado en desktop Dart puro)

---

### Fix 7 — `_extractAudioChunk` nunca extraía audio ✅
**Fecha:** 2026-04-30

**Síntoma:** TTS conectaba y completaba (turn.end llegaba) pero no reproducía audio.

**Causa raíz:** `_extractAudioChunk` buscaba `\r\n\r\n` en los mensajes binarios, pero el formato real de Edge TTS es:
```
[2 bytes big-endian: header length][header text][audio MP3 data]
```
Los mensajes binarios NO contienen `\r\n\r\n` → la función siempre retornaba `null` → 0 bytes de audio.

**Fix:**
```dart
Uint8List? _extractAudioChunk(Uint8List bytes) {
  if (bytes.length < 2) return null;
  final headerLen = (bytes[0] << 8) | bytes[1];
  final audioStart = 2 + headerLen;
  if (bytes.length <= audioStart) return null;
  return bytes.sublist(audioStart);
}
```

**Resultado:** ✅ Audio reproduce correctamente en emulador Android.

---

## Estado actual

**Fix 7 aplicado** — TTS funciona end-to-end: WebSocket conecta (Fix 6) y audio se extrae correctamente (Fix 7).

---

## Headers requeridos (según fuente oficial Python)

```
WSS URL params:  TrustedClientToken, ConnectionId, Sec-MS-GEC, Sec-MS-GEC-Version
Headers HTTP:    Pragma: no-cache
                 Cache-Control: no-cache
                 Origin: chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold
                 Accept-Encoding: gzip, deflate, br, zstd
                 Accept-Language: en-US,en;q=0.9
                 User-Agent: Mozilla/5.0...Chrome/143.0.0.0...Edg/143.0.0.0
                 Sec-WebSocket-Version: 13
                 Cookie: muid=<32 hex uppercase>;
```

## Algoritmo Sec-MS-GEC

```dart
// Mirrors Python DRM.generate_sec_ms_gec()
String _generateSecMsGec() {
  // 1. Tiempo Unix actual (con corrección de skew si aplica)
  final unixSec = DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0
      + _clockSkewSeconds;
  // 2. Convertir a Windows File Time epoch (1601-01-01)
  var ticks = unixSec + 11644473600;
  // 3. Redondear hacia abajo al múltiplo de 300 más cercano (ventana de 5 min)
  ticks -= ticks % 300;
  // 4. Convertir a intervalos de 100 nanosegundos
  ticks *= 10000000;
  // 5. SHA-256 de "{ticks}{token}" en ASCII → uppercase hex
  final payload = '${ticks.toStringAsFixed(0)}$_token';
  return sha256.convert(ascii.encode(payload)).toString().toUpperCase();
}
```

## Recursos consultados

- [edge-tts drm.py](https://github.com/rany2/edge-tts/blob/master/src/edge_tts/drm.py) — algoritmo oficial Python
- [edge-tts constants.py](https://github.com/rany2/edge-tts/blob/master/src/edge_tts/constants.py) — versión Chromium, headers
- [edge-tts communicate.py](https://github.com/rany2/edge-tts/blob/master/src/edge_tts/communicate.py) — flujo WebSocket y retry
- [edge-tts-universal drm.ts](https://github.com/travisvn/edge-tts-universal) — implementación TypeScript equivalente
- [Issue #290](https://github.com/rany2/edge-tts/issues/290) — introducción del token Sec-MS-GEC
- [Issue #401](https://github.com/rany2/edge-tts/issues/401) — 403 persistente, endpoint nuevo `api.msedgeservices.com`
- [Issue #458](https://github.com/rany2/edge-tts/issues/458) — 403 por versión Chromium desactualizada
