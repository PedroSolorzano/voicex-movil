import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicex_movil/config/server_config.dart';
import 'package:voicex_movil/config/settings.dart';

/// A stored engine name can outlive the engine: because one was retired, or —
/// desde 0.7.0— porque los motores de servidor solo existen en la compilación
/// que traiga su dirección. `load()` has to bring the name back to something
/// this build can use, or the reader boots naming an engine that is not there —
/// poisoning the cache key and the status bar, and sending the probe after a
/// machine it will never find, even though the factory quietly hands back Edge.
///
/// These tests run without `--dart-define`, so the build under test has no
/// server: exactly the shape of an APK handed to a tester without one.
void main() {
  group('resolveEngine', () {
    test('keeps the engines this build can actually use', () {
      for (final engine in TtsServerConfig.availableEngines) {
        expect(AppSettings.resolveEngine(engine), engine);
      }
    });

    test('an engine the app ships but this build cannot reach goes to Edge',
        () {
      // 'qwen3' is a real engine and listed in ttsEngines; what it is missing
      // here is an address, and without one it is no more usable than an
      // engine that was retired outright.
      expect(ttsEngines, containsAll(TtsServerConfig.serverEngines));
      for (final engine in TtsServerConfig.serverEngines) {
        expect(AppSettings.resolveEngine(engine), 'edge');
      }
    });

    test('brings a retired engine back to Edge', () {
      // Kokoro, Piper and F5 left with the home server that hosted them, and
      // `chatterbox` with 0.8.0. A phone that still has one selected must not
      // boot naming it.
      for (final retired in ['kokoro', 'piper', 'f5', 'chatterbox']) {
        expect(AppSettings.resolveEngine(retired), 'edge', reason: retired);
        expect(ttsEngines, isNot(contains(retired)));
      }
      expect(AppSettings.resolveEngine('festival'), 'edge');
      expect(AppSettings.resolveEngine('android-v2'), 'edge');
    });

    test('falls back to Edge for an absent or unknown value', () {
      expect(AppSettings.resolveEngine(null), 'edge');
      expect(AppSettings.resolveEngine(''), 'edge');
      expect(AppSettings.resolveEngine('qwen3-v2'), 'edge');
    });
  });

  group('un motor que esta compilación no trae', () {
    // Los tests corren sin --dart-define, así que esta compilación no tiene
    // servidor. Es exactamente la situación del APK de un probador al que no
    // se le compiló la dirección.
    test('sin servidor quedan los dos motores que no lo necesitan', () {
      // Edge necesita internet y nada más; el del teléfono ni siquiera eso.
      // Qwen3 y Chatterbox dependen de que la compilación traiga la dirección.
      expect(TtsServerConfig.availableEngines, ['edge', 'android']);
      expect(TtsServerConfig.hasServer, isFalse);
    });

    test('un qwen3 guardado vuelve a Edge', () async {
      // Sin esto el lector arrancaría nombrando un motor que la interfaz ni
      // siquiera ofrece, envenenando la clave de caché y la barra de estado, y
      // mandando el sondeo a buscar una máquina que no existe.
      SharedPreferences.setMockInitialValues({'ttsProvider': 'qwen3'});

      final settings = await AppSettings.load();

      expect(settings.ttsProvider, 'edge');
      expect(settings.usesSelfHostedServer, isFalse);
    });

    test('un motor retirado, guardado por una versión anterior, vuelve a Edge',
        () async {
      for (final retired in ['kokoro', 'piper', 'f5']) {
        SharedPreferences.setMockInitialValues({'ttsProvider': retired});

        final settings = await AppSettings.load();

        expect(settings.ttsProvider, 'edge', reason: retired);
      }
    });

    test('la dirección guardada por una versión anterior se ignora', () async {
      // La dirección ya no se lee de SharedPreferences: viene compilada. Una
      // que quedara en disco no debe resucitar.
      SharedPreferences.setMockInitialValues({
        'ttsProvider': 'edge',
        'kokoroBaseUrl': 'http://192.168.1.50:8880',
        'f5BaseUrl': 'http://192.168.1.60:8005',
      });

      final settings = await AppSettings.load();

      expect(settings.serverBaseUrl, '');
      expect(settings.hasServer, isFalse);
    });
  });

  group('load', () {
    test('un teléfono con el motor del sistema seleccionado lo conserva',
        () async {
      // Lo contrario de lo que afirmaba en 0.6.0: entonces 'android' era un
      // motor retirado y había que devolverlo a Edge. Vuelve en 0.7.0 porque es
      // el único que lee sin red ni servidor.
      SharedPreferences.setMockInitialValues({'ttsProvider': 'android'});

      final settings = await AppSettings.load();

      expect(settings.ttsProvider, 'android');
      // No es un motor de servidor: no debe disparar ningún sondeo.
      expect(settings.usesSelfHostedServer, isFalse);
    });

    test('leaves a usable engine alone, with its settings', () async {
      SharedPreferences.setMockInitialValues({
        'ttsProvider': 'edge',
        'edgeVoiceEs': 'es-ES-ElviraNeural',
        'qwen3Voice': 'otra',
      });

      final settings = await AppSettings.load();

      expect(settings.ttsProvider, 'edge');
      expect(settings.edgeVoiceEs, 'es-ES-ElviraNeural');
      // Los ajustes de un motor que esta compilación no trae sobreviven: si
      // más adelante se compila con servidor, la voz elegida sigue ahí.
      expect(settings.qwen3Voice, 'otra');
    });
  });

  group('voces de los motores del servidor', () {
    // Cada motor guarda la suya: no suenan igual con la misma grabación, y
    // la que le gusta a uno no tiene por qué ser la del otro.
    test('cada motor lee con su propia voz por defecto', () {
      final s = AppSettings();

      expect(s.voiceForEngine('qwen3', 'es'), 'esposa');
      expect(s.voiceForEngine('chatterbox2', 'es'), 'colombiana');
    });

    test('no hay variante en inglés: la voz es la misma para cualquier idioma',
        () {
      final s = AppSettings();

      expect(s.voiceForEngine('qwen3', 'en'), s.voiceForEngine('qwen3', 'es'));
    });

    test('elegir la voz de un motor no toca la del otro', () {
      final s = AppSettings().copyWith(qwen3Voice: 'nueva');

      expect(s.voiceForEngine('qwen3', 'es'), 'nueva');
      expect(s.voiceForEngine('chatterbox2', 'es'), 'colombiana');
    });

    test('la elección sobrevive a guardar y cargar', () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings(qwen3Voice: 'guardada', chatterbox2Voice: 'otra').save();

      final loaded = await AppSettings.load();

      expect(loaded.qwen3Voice, 'guardada');
      expect(loaded.chatterbox2Voice, 'otra');
    });
  });

  group('usesSelfHostedServer', () {
    test('solo los motores del servidor dependen de él', () {
      for (final engine in TtsServerConfig.serverEngines) {
        expect(AppSettings(ttsProvider: engine).usesSelfHostedServer, isTrue);
      }
      for (final engine in ['edge', 'android']) {
        expect(AppSettings(ttsProvider: engine).usesSelfHostedServer, isFalse);
      }
    });

    test('un motor propio sin dirección no tiene a dónde ir', () {
      // selfHostedUrl vacío es lo que hace que el lector vuelva a Edge.
      expect(AppSettings(ttsProvider: 'qwen3').selfHostedUrl, '');
      expect(
          AppSettings(ttsProvider: 'qwen3', serverBaseUrl: 'http://mac:8765')
              .selfHostedUrl,
          'http://mac:8765');
      expect(
          AppSettings(ttsProvider: 'edge', serverBaseUrl: 'http://mac:8765')
              .selfHostedUrl,
          '');
    });

    test('los dos motores comparten una sola credencial', () {
      expect(AppSettings().serverToken, TtsServerConfig.voiceToken);
    });
  });
}
