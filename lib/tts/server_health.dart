import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'tts_endpoint.dart';

/// Outcome of asking a self-hosted server whether it is there.
///
/// The distinction that matters is [unauthorized]: a revoked or mistyped token
/// is not a server that went down, and the two need different words on screen.
/// Before this, every failure collapsed into a single `false` whose reason only
/// ever reached `dev.log`.
///
/// [busy] is the server answering that it is there but occupied: F5 serves
/// `/health` off the synthesis thread and reports `busy` while its single GPU
/// lock is taken (`tools/f5/server.py`). Sending it work anyway does not fail
/// fast -- the request blocks on that lock and burns the client's synthesis
/// budget waiting in line -- so it counts as not usable, but for a different
/// reason and with different words on screen.
enum ServerHealth { ok, unreachable, unauthorized, error, busy }

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
      // A busy server is the one verdict that flips on its own, without
      // anything changing on this end: the short TTL is what lets a download
      // come back to it as soon as the lock frees, instead of finishing the
      // chapter on Edge.
      _ => _ttlFail,
    };

final Map<String, ({DateTime at, ServerHealth health})> _cache = {};

/// Until when a server is assumed still busy with a request the client gave
/// up waiting for, keyed the same way as [_cache].
final Map<String, DateTime> _busyUntil = {};

/// Forgets every cached verdict, so the next probe really asks the server.
///
/// Deliberately does **not** clear [_busyUntil]. The cache holds what this
/// phone knows about *its own connection* -- worthless the moment the network
/// changes -- while the busy window holds what it knows about *the server*,
/// which a change of Wi-Fi says nothing about. Clearing both together is how
/// the download bug came back after its first fix: the two callers that reset
/// on network change (the button in Ajustes, and every
/// `onConnectivityChanged` event) reopened the window against a server that
/// was still generating, and the paragraphs behind it queued up and timed out
/// (`docs/bugs/CHATTERBOX_DESCARGAS.md`).
void resetServerHealthCache() => _cache.clear();

/// Forgets the busy windows too. Only for tests: nothing in the app knows
/// better than the server whether it is still working.
void resetBusyWindows() => _busyUntil.clear();

/// Marks the server behind [healthUri] as likely still finishing a synthesis
/// the client gave up waiting for, so [probeServer] skips the network and
/// reports [ServerHealth.busy] until [cooldown] elapses.
///
/// This is the *inferred* half of the same verdict a server can now report
/// itself. It still earns its place: it covers the servers that say nothing
/// (Kokoro, Piper) and the moment before the next probe. Chatterbox was the
/// worst case — a single-worker, autoregressive server whose health endpoint
/// was blocked by its own synthesis, so it could not answer at all — and F5
/// keeps the part that matters: a request abandoned by the client is not
/// cancelled server-side, and the GPU stays taken until it finishes. Without
/// this, every following paragraph of the same download re-probes health
/// every ~13 s and fails the same way for minutes (see
/// `docs/bugs/CHATTERBOX_DESCARGAS.md`).
void markServerBusy(Uri healthUri, {required Duration cooldown}) {
  _busyUntil[healthUri.toString()] = DateTime.now().add(cooldown);
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
  final busyUntil = _busyUntil[key];
  if (busyUntil != null) {
    if (DateTime.now().isBefore(busyUntil)) return ServerHealth.busy;
    _busyUntil.remove(key);
  }

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
  // The 200 branch reads the body instead of draining it: draining a stream
  // that was already listened to throws.
  if (resp.statusCode == 200) return _readVerdict(resp);

  final health = switch (resp.statusCode) {
    401 || 403 => ServerHealth.unauthorized,
    _ => ServerHealth.error,
  };
  await resp.drain<void>();
  return health;
}

/// A 200 is not always a free server: F5 answers `{"busy": true}` while its GPU
/// lock is taken, and the body was being thrown away.
///
/// That flag is the one thing the phone cannot work out for itself. Guessing it
/// from a timeout costs a whole synthesis budget first, and the guess expires on
/// a fixed cooldown rather than when the server actually frees up. Servers that
/// say nothing — Kokoro, Piper, anything in front of them — read as [ok] exactly
/// as before.
///
/// Same rule as everywhere else in this app: trust `content-type`, not the shape
/// of the body. An intermediary answering 200 with an HTML page must not be
/// parsed as JSON (see the note in CLAUDE.md).
Future<ServerHealth> _readVerdict(HttpClientResponse resp) async {
  if (resp.headers.contentType?.mimeType != 'application/json') {
    await resp.drain<void>();
    return ServerHealth.ok;
  }
  try {
    final body = await resp.transform(utf8.decoder).join();
    final json = jsonDecode(body);
    if (json is Map && json['busy'] == true) return ServerHealth.busy;
  } catch (e) {
    // A health endpoint that answers 200 with something unreadable is still a
    // server that is up; the verdict it could not refine stays the optimistic
    // one, and the download falls back on the inferred busy window.
    dev.log('[health] ${resp.headers.contentType} body unreadable: $e');
  }
  return ServerHealth.ok;
}
