import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/tts/server_health.dart';

/// Probes run against a real server on loopback rather than a mocked client:
/// the same choice `audio_cache_repo_test.dart` makes with SQLite, and the only
/// way to exercise a socket that accepts a connection and then says nothing —
/// which is precisely the failure a tunnel over mobile data produces.
///
/// Budgets are injected in milliseconds, so the suite stays fast.
void main() {
  late HttpServer server;
  late Uri uri;

  /// Starts a server that answers each request with [handler].
  ///
  /// `listen` rather than `await for`: a handler that never responds must not
  /// block the next request, or the retry test would deadlock.
  Future<void> serve(void Function(HttpRequest req) handler) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handler);
    uri = Uri.parse('http://${server.address.address}:${server.port}/health');
  }

  setUp(() {
    resetServerHealthCache();
    // Aparte a propósito: la app ya no borra la ventana de ocupado, solo los
    // tests la limpian entre casos.
    resetBusyWindows();
  });

  tearDown(() async {
    TtsDiagnostics.clear();
    await server.close(force: true);
  });

  test('a healthy server carries the token and answers ok', () async {
    String? seen;
    await serve((req) {
      seen = req.headers.value(HttpHeaders.authorizationHeader);
      req.response
        ..statusCode = 200
        ..close();
    });

    expect(await probeServer(uri, token: 'secreto', engine: 'kokoro'),
        ServerHealth.ok);
    expect(seen, 'Bearer secreto');
  });

  test('a rejected token is not a server that went down', () async {
    // The distinction the old boolean could not make. A tester whose key was
    // revoked needs a different sentence than one whose server is off.
    await serve((req) => req.response
      ..statusCode = 401
      ..close());

    expect(await probeServer(uri), ServerHealth.unauthorized);
  });

  test('a broken server is an error, not an absent one', () async {
    await serve((req) => req.response
      ..statusCode = 500
      ..close());

    expect(await probeServer(uri), ServerHealth.error);
  });

  test('a server that accepts and then says nothing is unreachable', () async {
    await serve((req) {/* never responds */});

    final health = await probeServer(
      uri,
      timeout: const Duration(milliseconds: 120),
      retryTimeout: const Duration(milliseconds: 120),
      backoff: Duration.zero,
    );

    expect(health, ServerHealth.unreachable);
  });

  test('a timeout is retried once, with a wider budget', () async {
    // The whole point of the asymmetric policy: the first attempt runs out of
    // time on a slow link, the second one gets through.
    var seen = 0;
    await serve((req) {
      seen++;
      if (seen == 1) return; // hang, so attempt 1 times out
      req.response
        ..statusCode = 200
        ..close();
    });

    final health = await probeServer(
      uri,
      timeout: const Duration(milliseconds: 120),
      retryTimeout: const Duration(seconds: 3),
      backoff: const Duration(milliseconds: 10),
    );

    expect(health, ServerHealth.ok);
    expect(seen, 2, reason: 'exactamente un reintento, no más');
  });

  test('a refused connection is not retried', () async {
    // Nothing is listening, so waiting another eight seconds would not conjure
    // a server. Retrying here is the waste the asymmetry exists to avoid.
    await serve((req) {});
    final port = server.port;
    await server.close(force: true);

    final dead = Uri.parse('http://127.0.0.1:$port/health');
    expect(await probeServer(dead), ServerHealth.unreachable);
    expect(TtsDiagnostics.entries.length, 1);

    // tearDown closes it again, which is harmless.
    await serve((req) {});
  });

  test('the verdict is cached, so a chapter does not probe per paragraph',
      () async {
    var seen = 0;
    await serve((req) {
      seen++;
      req.response
        ..statusCode = 200
        ..close();
    });

    await probeServer(uri);
    await probeServer(uri);

    expect(seen, 1);
  });

  test('a failure is forgotten quickly, a success is not', () async {
    // The old symmetric 30 s cached failures too, so one pothole in the network
    // froze the fallback to Edge and dragged the following paragraphs with it.
    var seen = 0;
    await serve((req) {
      seen++;
      req.response
        ..statusCode = seen == 1 ? 500 : 200
        ..close();
    });

    expect(await probeServer(uri), ServerHealth.error);
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(await probeServer(uri), ServerHealth.ok,
        reason: 'el fallo caduca en 5 s');

    await probeServer(uri);
    expect(seen, 2, reason: 'el éxito sigue cacheado');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('a server marked busy is skipped, even though it would answer ok',
      () async {
    var hits = 0;
    await serve((req) {
      hits++;
      req.response
        ..statusCode = 200
        ..close();
    });

    markServerBusy(uri, cooldown: const Duration(milliseconds: 200));

    expect(await probeServer(uri), ServerHealth.busy);
    expect(hits, 0, reason: 'la probe no debe llegar a tocar la red');
  });

  test('the busy window expires and a real probe runs again', () async {
    await serve((req) => req.response
      ..statusCode = 200
      ..close());

    markServerBusy(uri, cooldown: const Duration(milliseconds: 50));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(await probeServer(uri), ServerHealth.ok);
  });

  test('resetServerHealthCache keeps the busy window', () async {
    // La recaída de `docs/bugs/CHATTERBOX_DESCARGAS.md`: cambiar de red, o
    // tocar "Probar conexión", no dice nada sobre si el servidor terminó la
    // síntesis que dejó a medias. Borrar las dos cosas juntas reabría la cola
    // contra un servidor todavía ocupado.
    await serve((req) => req.response
      ..statusCode = 200
      ..close());

    markServerBusy(uri, cooldown: const Duration(seconds: 30));
    resetServerHealthCache();

    expect(await probeServer(uri), ServerHealth.busy);
  });

  test('a 200 that says it is busy is not a free server', () async {
    // F5 contesta /health fuera del hilo de síntesis, así que responde 200 al
    // instante mientras la GPU está tomada. El cuerpo era lo único que lo
    // decía y se estaba tirando.
    await serve((req) => req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write('{"status":"ok","busy":true}')
      ..close());

    expect(await probeServer(uri), ServerHealth.busy);
  });

  test('the same server free again answers ok', () async {
    await serve((req) => req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write('{"status":"ok","busy":false}')
      ..close());

    expect(await probeServer(uri), ServerHealth.ok);
  });

  test('a 200 that is not JSON is still a healthy server', () async {
    // Kokoro y Piper no mandan `busy`, y un intermediario puede contestar 200
    // con HTML: ninguno de los dos casos debe leerse como JSON.
    await serve((req) => req.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write('<html>ok</html>')
      ..close());

    expect(await probeServer(uri), ServerHealth.ok);
  });

  test('every attempt leaves a line in the on-device ring', () async {
    // The half the proxy log cannot give: a probe that times out on the phone
    // shows up server-side as a clean 200.
    await serve((req) => req.response
      ..statusCode = 200
      ..close());

    await probeServer(uri);

    expect(TtsDiagnostics.entries, hasLength(1));
    final entry = TtsDiagnostics.entries.single;
    expect(entry.result, ServerHealth.ok);
    expect(entry.attempt, 1);
    expect(TtsDiagnostics.asText(), contains('/health'));
  });
}
