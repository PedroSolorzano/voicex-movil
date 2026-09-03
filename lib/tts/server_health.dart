import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'tts_endpoint.dart';

/// Outcome of asking a self-hosted server whether it is there.
///
/// The distinction that matters is [unauthorized]: a revoked or mistyped token
/// is not a server that went down, and the two need different words on screen.
/// Before this, every failure collapsed into a single `false` whose reason only
/// ever reached `dev.log`.
enum ServerHealth { ok, unreachable, unauthorized, error }

extension ServerHealthX on ServerHealth {
  bool get isUsable => this == ServerHealth.ok;
}

/// How long a verdict is trusted before probing again.
///
/// Asymmetric on purpose. A success is stable, so caching it for a minute
/// spares a chapter download one probe per paragraph. A failure is not: it may
/// be a pothole in a mobile network, and the old symmetric 30 s meant one bad
/// moment froze the fallback to Edge for half a minute and dragged every
/// following paragraph down with it.
const _ttlOk = Duration(seconds: 60);
const _ttlFail = Duration(seconds: 5);

Duration _ttlFor(ServerHealth health) => switch (health) {
      ServerHealth.ok => _ttlOk,
      // A rejected key will still be rejected in five seconds; re-probing only
      // burns battery and log lines.
      ServerHealth.unauthorized => _ttlOk,
      _ => _ttlFail,
    };

final Map<String, ({DateTime at, ServerHealth health})> _cache = {};

/// Forgets every cached verdict, so the next probe really asks the server.
void resetServerHealthCache() {
  _cache.clear();
}

/// One line of the on-device diagnostic ring.
class ProbeRecord {
  final DateTime at;
  final String host;
  final String path;
  final ServerHealth result;
  final int ms;
  final int attempt;

  const ProbeRecord({
    required this.at,
    required this.host,
    required this.path,
    required this.result,
    required this.ms,
    required this.attempt,
  });

  @override
  String toString() {
    final t = at.toIso8601String().substring(11, 19);
    final tag = attempt > 1 ? ' (intento $attempt)' : '';
    return '$t  $path  ${result.name}  ${ms}ms$tag';
  }
}

/// The last handful of probes, measured **on the phone**.
///
/// This is the half the server's log cannot supply. A probe that times out here
/// shows up in the proxy as a clean 200 with a millisecond response time: the
/// request arrived and was answered, and what was lost was the trip back over
/// the mobile network. Only the device knows the round trip, and the round trip
/// is what decides whether the timeout budget was the problem.
class TtsDiagnostics {
  static const _capacity = 50;
  static final List<ProbeRecord> _ring = [];

  static void record(ProbeRecord entry) {
    _ring.add(entry);
    if (_ring.length > _capacity) _ring.removeAt(0);
  }

  static List<ProbeRecord> get entries => List.unmodifiable(_ring);

  static void clear() => _ring.clear();

  /// Plain text, ready for the share sheet: what a tester sends back instead of
  /// "no me funciona".
  static String asText() {
    if (_ring.isEmpty) return 'Sin registros todavía.';
    final host = _ring.last.host;
    return ['Servidor: $host', ..._ring.map((e) => e.toString())].join('\n');
  }
}

/// Asks a server whether it is reachable, with one retry when — and only when —
/// the first attempt ran out of time.
///
/// A refused connection or a failed lookup means the server genuinely is not
/// there, and waiting another eight seconds will not conjure it. A timeout is
/// the ambiguous case, and the one a tunnel over mobile data produces while the
/// server is perfectly healthy.
///
/// [clientFactory] exists so a test can hand in its own client; the probe used
/// to build an `HttpClient` inside a static method, which made it untestable
/// without a network.
Future<ServerHealth> probeServer(
  Uri uri, {
  String token = '',
  String engine = '',
  HttpClient Function()? clientFactory,
  Duration timeout = TtsTimeouts.probe,
  Duration retryTimeout = TtsTimeouts.probeRetry,
  Duration backoff = TtsTimeouts.probeBackoff,
}) async {
  final key = uri.toString();
  final cached = _cache[key];
  if (cached != null &&
      DateTime.now().difference(cached.at) < _ttlFor(cached.health)) {
    return cached.health;
  }

  var outcome = await _attempt(uri, token, engine, timeout, 1, clientFactory);
  if (outcome.timedOut) {
    await Future<void>.delayed(backoff);
    outcome = await _attempt(uri, token, engine, retryTimeout, 2, clientFactory);
  }

  _cache[key] = (at: DateTime.now(), health: outcome.health);
  return outcome.health;
}

Future<({ServerHealth health, bool timedOut})> _attempt(
  Uri uri,
  String token,
  String engine,
  Duration budget,
  int attempt,
  HttpClient Function()? clientFactory,
) async {
  // Deliberately no `connectionTimeout`: it surfaces as a SocketException, and
  // a slow connect through a tunnel would then be indistinguishable from a
  // refused one — losing the retry in exactly the case it was built for. One
  // timeout around the whole attempt keeps the two apart.
  final client = (clientFactory ?? HttpClient.new)();
  final watch = Stopwatch()..start();
  ServerHealth health;
  var timedOut = false;

  try {
    health = await _run(client, uri, token, engine, attempt).timeout(budget);
  } on TimeoutException {
    health = ServerHealth.unreachable;
    timedOut = true;
  } on SocketException catch (e) {
    dev.log('[health] $uri unreachable: $e');
    health = ServerHealth.unreachable;
  } catch (e) {
    dev.log('[health] $uri failed: $e');
    health = ServerHealth.error;
  } finally {
    client.close(force: true);
  }

  watch.stop();
  TtsDiagnostics.record(ProbeRecord(
    at: DateTime.now(),
    host: uri.host,
    path: uri.path,
    result: health,
    ms: watch.elapsedMilliseconds,
    attempt: attempt,
  ));
  return (health: health, timedOut: timedOut);
}

Future<ServerHealth> _run(
  HttpClient client,
  Uri uri,
  String token,
  String engine,
  int attempt,
) async {
  final req = await client.getUrl(uri);
  applyRequestHeaders(req, token: token, engine: engine, attempt: attempt);
  final resp = await req.close();
  final health = switch (resp.statusCode) {
    200 => ServerHealth.ok,
    401 || 403 => ServerHealth.unauthorized,
    _ => ServerHealth.error,
  };
  await resp.drain<void>();
  return health;
}
