import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/tts/voice_server_provider.dart';
import 'package:voicex_movil/tts/server_health.dart';

/// Reproduces the incident in `docs/bugs/CHATTERBOX_DESCARGAS.md`: a paragraph
/// that outlasts its synthesis timeout should not leave the following
/// health-checks free to hammer a server that is (as far as the client can
/// tell) still busy with the abandoned request. The incident was with the first
/// engine to run on a home server and it applies to every one that followed.
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

    final provider = VoiceServerTtsProvider(baseUrl,
        engine: 'qwen3',
        synthesisTimeout: const Duration(milliseconds: 50));

    await expectLater(
      provider.synthesize(
          text: 'hola', voice: 'esposa', rate: '1.0', volume: '1.0'),
      throwsA(isA<TimeoutException>()),
    );

    expect(await VoiceServerTtsProvider.healthOf(baseUrl), ServerHealth.busy);
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

    final provider = VoiceServerTtsProvider(baseUrl, engine: 'qwen3');

    await expectLater(
      provider.synthesize(
          text: 'hola', voice: 'esposa', rate: '1.0', volume: '1.0'),
      throwsA(isA<HttpException>()),
    );

    expect(await VoiceServerTtsProvider.healthOf(baseUrl), ServerHealth.ok);
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

    final provider = VoiceServerTtsProvider(baseUrl,
        engine: 'qwen3',
        synthesisTimeout: const Duration(milliseconds: 50));

    await expectLater(
      provider.synthesize(
          text: 'hola', voice: 'esposa', rate: '1.0', volume: '1.0'),
      throwsA(isA<TimeoutException>()),
    );

    // Muy por encima de los 50 ms de esa síntesis, muy por debajo del cooldown.
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(await VoiceServerTtsProvider.healthOf(baseUrl), ServerHealth.busy);
    expect(healthHits, 0);
  });

  group('token', () {
    // El servidor valida su propio token, sin proxy delante: la síntesis y el
    // sondeo tienen que llevarlo, o un 401 se leería como servidor caído.
    test('la síntesis se identifica ante el servidor', () async {
      String? recibido;
      // Contesta 200 sin cuerpo: alcanza para leer la cabecera y corta antes
      // de escribir el MP3, que necesitaría el directorio temporal del
      // teléfono y no hay ninguno bajo `flutter test`.
      await serve((req) {
        recibido = req.headers.value(HttpHeaders.authorizationHeader);
        req.response
          ..statusCode = 200
          ..close();
      });

      await expectLater(
        VoiceServerTtsProvider(baseUrl, engine: 'qwen3', token: 'abc').synthesize(
            text: 'hola', voice: 'esposa', rate: '1.0', volume: '1.0'),
        throwsA(isA<HttpException>()),
      );

      expect(recibido, 'Bearer abc');
    });

    test('el sondeo también, o el 401 se leería como servidor caído', () async {
      String? recibido;
      await serve((req) {
        recibido = req.headers.value(HttpHeaders.authorizationHeader);
        req.response
          ..statusCode = 200
          ..close();
      });

      await VoiceServerTtsProvider.healthOf(baseUrl, token: 'abc');

      expect(recibido, 'Bearer abc');
    });

    test('sin token no se manda cabecera: el servidor puede no pedirla',
        () async {
      String? recibido = 'sin tocar';
      await serve((req) {
        recibido = req.headers.value(HttpHeaders.authorizationHeader);
        req.response
          ..statusCode = 200
          ..close();
      });

      await VoiceServerTtsProvider.healthOf(baseUrl);

      expect(recibido, isNull);
    });
  });

  group('qué se le pide al servidor', () {
    test('la síntesis lleva el motor y la voz elegidos, sin la velocidad',
        () async {
      Map<String, dynamic>? cuerpo;
      await serve((req) async {
        cuerpo = jsonDecode(await utf8.decoder.bind(req).join())
            as Map<String, dynamic>;
        req.response
          ..statusCode = 200
          ..close();
      });

      await expectLater(
        VoiceServerTtsProvider(baseUrl, engine: 'chatterbox2').synthesize(
            text: 'hola', voice: 'colombiana', rate: '+25%', volume: '+0%'),
        throwsA(isA<HttpException>()),
      );

      // La velocidad se aplica al reproducir: mandarla haría que un mismo
      // párrafo tuviera dos audios distintos bajo una sola clave de caché.
      expect(cuerpo,
          {'text': 'hola', 'voice': 'colombiana', 'engine': 'chatterbox2'});
    });

    test('el catálogo son las voces que el propio servidor anuncia', () async {
      await serve((req) {
        req.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'status': 'ok',
            'voices': ['colombiana', 'esposa'],
            'busy': false,
          }))
          ..close();
      });

      final voces =
          await VoiceServerTtsProvider(baseUrl, engine: 'qwen3').listVoices();

      expect(voces.map((v) => v.id), ['colombiana', 'esposa']);
      expect(voces.every((v) => v.locale == 'es'), isTrue);
    });

    test('un servidor que no responde da catálogo vacío, no una excepción',
        () async {
      await serve((req) {
        req.response
          ..statusCode = 500
          ..close();
      });

      final voces =
          await VoiceServerTtsProvider(baseUrl, engine: 'qwen3').listVoices();

      expect(voces, isEmpty);
    });
  });
}
