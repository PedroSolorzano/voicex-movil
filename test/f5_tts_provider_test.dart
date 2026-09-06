import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/tts/f5_tts_provider.dart';
import 'package:voicex_movil/tts/server_health.dart';

/// Reproduces the incident in `docs/bugs/CHATTERBOX_DESCARGAS.md`: a paragraph
/// that outlasts its synthesis timeout should not leave the following
/// health-checks free to hammer a server that is (as far as the client can
/// tell) still busy with the abandoned request.
void main() {
  late HttpServer server;
  late String baseUrl;

  Future<void> serve(void Function(HttpRequest req) handler) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(handler);
    baseUrl = 'http://${server.address.address}:${server.port}';
  }

  setUp(() {
    resetServerHealthCache();
    resetBusyWindows();
  });

  tearDown(() async {
    TtsDiagnostics.clear();
    await server.close(force: true);
  });

  test(
      'a paragraph that outlasts its timeout marks the server busy for the '
      'next health check', () async {
    var healthHits = 0;
    await serve((req) {
      if (req.uri.path == '/health') {
        healthHits++;
        req.response
          ..statusCode = 200
          ..close();
      }
      // POST /tts: never responds, forcing the client's own timeout.
    });

    final provider = F5TtsProvider(baseUrl,
        synthesisTimeout: const Duration(milliseconds: 50));

    await expectLater(
      provider.synthesize(
          text: 'hola', voice: 'esposa', rate: '1.0', volume: '1.0'),
      throwsA(isA<TimeoutException>()),
    );

    expect(await F5TtsProvider.healthOf(baseUrl), ServerHealth.busy);
    expect(healthHits, 0,
        reason: 'la probe tiene que saltarse, no solo fallar');
  });

  test('a plain error response does not mark the server busy', () async {
    await serve((req) {
      if (req.uri.path == '/tts') {
        req.response
          ..statusCode = 500
          ..close();
      } else {
        req.response
          ..statusCode = 200
          ..close();
      }
    });

    final provider = F5TtsProvider(baseUrl);

    await expectLater(
      provider.synthesize(
          text: 'hola', voice: 'esposa', rate: '1.0', volume: '1.0'),
      throwsA(isA<HttpException>()),
    );

    expect(await F5TtsProvider.healthOf(baseUrl), ServerHealth.ok);
  });

  test('el silencio no se encoge al presupuesto de esa síntesis', () async {
    // El cooldown es una constante aparte a propósito. Atarlo al presupuesto
    // de síntesis —que ahora se estira según lo que tarde la máquina— tendría
    // el defecto en los dos extremos: un presupuesto corto levantaría el
    // silencio antes de que el servidor termine, y uno de quince minutos
    // dejaría la app replegada a Edge un cuarto de hora por un solo párrafo.
    // La expiración en sí se prueba en `server_health_test.dart`.
    var healthHits = 0;
    await serve((req) {
      if (req.uri.path == '/health') {
        healthHits++;
        req.response
          ..statusCode = 200
          ..close();
      }
    });

    final provider = F5TtsProvider(baseUrl,
        synthesisTimeout: const Duration(milliseconds: 50));

    await expectLater(
      provider.synthesize(
          text: 'hola', voice: 'esposa', rate: '1.0', volume: '1.0'),
      throwsA(isA<TimeoutException>()),
    );

    // Muy por encima de los 50 ms de esa síntesis, muy por debajo del cooldown.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(await F5TtsProvider.healthOf(baseUrl), ServerHealth.busy);
    expect(healthHits, 0);
  });
}
