import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Network budgets for the self-hosted engines, in one place.
///
/// They used to be literals repeated across both providers, which made them
/// impossible to compare and impossible to shorten from a test. The probe
/// numbers in particular are not arbitrary: they are the difference between
/// reaching a server through a tunnel on mobile data and falling back to Edge
/// while the server is perfectly alive.
class TtsTimeouts {
  /// Opening the socket. Wide enough for a WireGuard handshake.
  static const connect = Duration(seconds: 5);

  /// First reachability probe. A server on the LAN answers in milliseconds;
  /// the same server through a tunnel on 4G can take most of a second before
  /// the first byte, and that is still a healthy server.
  static const probe = Duration(seconds: 5);

  /// Second probe, after the first timed out. Wider on purpose — the retry
  /// exists precisely for the slow case, so repeating the same budget would
  /// only fail the same way twice.
  static const probeRetry = Duration(seconds: 8);

  /// Pause before the retry, long enough to ride out a momentary stall and
  /// short enough that nobody notices it before a paragraph starts.
  static const probeBackoff = Duration(milliseconds: 400);

  /// Synthesis. Kokoro runs ~5x realtime on CPU, so a long paragraph
  /// legitimately takes seconds; Piper is faster.
  static const synthesisKokoro = Duration(seconds: 180);
  static const synthesisPiper = Duration(seconds: 120);

  /// Chatterbox corre en GPU pero es autoregresivo: ~55-75 s medidos para un
  /// párrafo de ~25 s de audio (más lento que tiempo real). Generoso a
  /// propósito para no cortar un párrafo largo a mitad de síntesis.
  ///
  /// Es el punto de partida, no el techo definitivo de una descarga: ver
  /// [adaptiveSynthesis].
  static const synthesisChatterbox = Duration(seconds: 240);

  /// Cuánto se asume que un servidor sigue ocupado tras abandonar una síntesis.
  ///
  /// Constante aparte del presupuesto de síntesis a propósito: ese presupuesto
  /// ahora se estira según la máquina (ver [adaptiveSynthesis]), y atar el
  /// silencio a un número que puede llegar a quince minutos dejaría a la app
  /// replegada a Edge un cuarto de hora por un solo párrafo lento.
  static const busyCooldown = Duration(seconds: 240);

  /// Techo de síntesis derivado de lo que esta máquina viene tardando de
  /// verdad, en vez de un número fijo calibrado en otro hardware.
  ///
  /// El 240 s de [synthesisChatterbox] sale de medir ~55-75 s por párrafo. Una
  /// GPU más justa tarda varias veces eso, y el resultado es el peor
  /// desperdicio posible: el servidor **termina** el audio y el cliente ya se
  /// rindió, así que se tira a la basura una generación entera —medido en
  /// `docs/bugs/CHATTERBOX_DESCARGAS.md`, un párrafo de 4 m 37 s abandonado a
  /// los 4 m.
  ///
  /// Cinco veces el promedio observado cubre ese caso con margen sin volverse
  /// una espera infinita. El suelo es el valor de siempre —esto solo puede
  /// hacer la app más paciente, nunca menos— y el techo evita que una racha
  /// lenta convierta un servidor colgado en una espera de media hora.
  static Duration adaptiveSynthesis({
    required Duration measured,
    required int samples,
  }) {
    if (samples <= 0 || measured <= Duration.zero) return synthesisChatterbox;
    final scaled = measured * 5;
    if (scaled < synthesisChatterbox) return synthesisChatterbox;
    if (scaled > adaptiveSynthesisCeiling) return adaptiveSynthesisCeiling;
    return scaled;
  }

  /// Tope duro de [adaptiveSynthesis].
  static const adaptiveSynthesisCeiling = Duration(minutes: 20);

  /// Reading the response body once the headers arrived.
  ///
  /// Without this the read has no ceiling at all: a connection that degrades
  /// after the headers hangs forever, and the failure never even reaches the
  /// error message. Generous, because the body can be megabytes of audio over
  /// a slow link.
  static const body = Duration(seconds: 120);

  /// Voice catalogue: small payload, no reason to wait long.
  static const catalogue = Duration(seconds: 10);

  /// Sockets idle longer than this are dropped rather than reused. Matters
  /// after a body read times out, because the response can no longer be
  /// drained and the connection would otherwise sit there occupying a slot.
  static const idle = Duration(seconds: 10);
}

/// Brings a server address typed or pasted by a human to a usable base URL.
///
/// Two failures this prevents, both of which used to look exactly like a dead
/// server. A trailing slash made the probe request `//health`, which answers
/// 404 while synthesis kept working, because only the constructors trimmed it.
/// A missing scheme made `Uri.parse` yield no host and `getUrl` throw, which
/// the probe swallowed into the same generic "no responde".
///
/// The path prefix is preserved: behind the proxy the base is
/// `https://host.ts.net/kokoro`, and dropping that segment would point every
/// request at the wrong place.
String normalizeBaseUrl(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';
  if (!s.contains('://')) s = 'http://$s';

  // Only strip slashes that belong to the path, never the pair in `://`.
  final afterScheme = s.indexOf('://') + 3;
  var end = s.length;
  while (end > afterScheme && s[end - 1] == '/') {
    end--;
  }
  return s.substring(0, end);
}

/// Joins a base address and an absolute path, normalising the base first.
Uri buildUri(String baseUrl, String path) =>
    Uri.parse('${normalizeBaseUrl(baseUrl)}$path');

/// Bearer credentials for the proxy that fronts the self-hosted engines.
///
/// Empty when there is no token, so a server reached directly on the LAN keeps
/// working unchanged. Never put the token in a query string: it would land in
/// the proxy's access log.
Map<String, String> authHeaders(String token) => token.isEmpty
    ? const {}
    : {HttpHeaders.authorizationHeader: 'Bearer $token'};

/// Version of the app, stamped on every request so a report can be tied to the
/// build that produced it. Set once at startup; empty is harmless.
String appVersionTag = '';

/// Applies credentials and the telemetry the proxy cannot work out on its own.
///
/// [chars] is the length of the text being synthesized, declared by the client
/// on purpose: nginx knows how many bytes arrived, but recovering the real
/// character count would mean inspecting the request body — which is the
/// paragraph of somebody's book, the one thing we refuse to look at. Declaring
/// it gives the exact number without reading a word. It is not a figure to
/// trust in a security sense; what bounds abuse is the rate limit, which acts
/// on facts.
void applyRequestHeaders(
  HttpClientRequest req, {
  required String token,
  required String engine,
  int? chars,
  int? attempt,
}) {
  authHeaders(token).forEach(req.headers.set);
  req.headers.set('X-Voicex-Engine', engine);
  if (appVersionTag.isNotEmpty) {
    req.headers.set('X-Voicex-Client', appVersionTag);
  }
  if (chars != null) req.headers.set('X-Voicex-Chars', '$chars');
  if (attempt != null) req.headers.set('X-Voicex-Attempt', '$attempt');
}

/// Reads a response body whole, with a ceiling on the entire read.
Future<List<int>> readBodyBytes(
  HttpClientResponse resp, {
  Duration timeout = TtsTimeouts.body,
}) async {
  final builder = BytesBuilder(copy: false);
  await resp.forEach(builder.add).timeout(timeout);
  return builder.takeBytes();
}

/// Same, decoding as UTF-8.
Future<String> readBodyString(
  HttpClientResponse resp, {
  Duration timeout = TtsTimeouts.body,
}) =>
    resp.transform(utf8.decoder).join().timeout(timeout);
