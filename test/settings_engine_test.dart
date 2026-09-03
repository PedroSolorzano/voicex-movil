import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicex_movil/config/server_config.dart';
import 'package:voicex_movil/config/settings.dart';

/// A stored engine name outlives the engine twice over: once when one is
/// retired for good (Android TTS, in 0.6.0), and once per build, because from
/// 0.7.0 the self-hosted engines exist only where their address was compiled
/// in. `load()` has to bring the name back to something this build can use, or
/// the reader boots naming an engine that is not there — poisoning the cache
/// key and the status bar, and sending the probe after a machine it will never
/// find, even though the factory quietly hands back Edge.
///
/// These tests run without `--dart-define`, so the build under test has no
/// server: exactly the shape of an APK handed to a tester without Kokoro.
void main() {
  group('resolveEngine', () {
    test('keeps the engines this build can actually use', () {
      for (final engine in TtsServerConfig.availableEngines) {
        expect(AppSettings.resolveEngine(engine), engine);
      }
    });

    test('an engine the app ships but this build cannot reach goes to Edge',
        () {
      // 'kokoro' is a real engine and still listed in ttsEngines; what it is
      // missing here is an address, and without one it is no more usable than
      // an engine that was retired outright.
      expect(ttsEngines, contains('kokoro'));
      expect(AppSettings.resolveEngine('kokoro'), 'edge');
    });

    test('brings a retired engine back to Edge', () {
      expect(AppSettings.resolveEngine('android'), 'edge');
    });

    test('falls back to Edge for an absent or unknown value', () {
      expect(AppSettings.resolveEngine(null), 'edge');
      expect(AppSettings.resolveEngine(''), 'edge');
      expect(AppSettings.resolveEngine('kokoro-v2'), 'edge');
    });
  });

  group('un motor que esta compilación no trae', () {
    // Los tests corren sin --dart-define, así que esta compilación no tiene
    // servidor: solo Edge existe. Es exactamente la situación del APK de un
    // probador al que no se le compiló Kokoro.
    test('los motores disponibles se reducen a Edge', () {
      expect(TtsServerConfig.availableEngines, ['edge']);
      expect(TtsServerConfig.hasKokoro, isFalse);
    });

    test('un kokoro guardado vuelve a Edge', () async {
      // Sin esto el lector arrancaría nombrando un motor que la interfaz ni
      // siquiera ofrece, envenenando la clave de caché y la barra de estado, y
      // mandando el sondeo a buscar una máquina que no existe. Es el mismo
      // fallo que se arregló al retirar el TTS de Android en 0.6.0, con otra
      // causa.
      SharedPreferences.setMockInitialValues({'ttsProvider': 'kokoro'});

      final settings = await AppSettings.load();

      expect(settings.ttsProvider, 'edge');
      expect(settings.usesSelfHostedServer, isFalse);
    });

    test('la dirección guardada por una versión anterior se ignora', () async {
      // La dirección ya no se lee de SharedPreferences: viene compilada. Una
      // que quedara en disco no debe resucitar.
      SharedPreferences.setMockInitialValues({
        'ttsProvider': 'edge',
        'kokoroBaseUrl': 'http://192.168.1.50:8880',
      });

      final settings = await AppSettings.load();

      expect(settings.kokoroBaseUrl, '');
      expect(settings.hasKokoroServer, isFalse);
    });
  });

  group('load', () {
    test('a phone left on Android TTS comes back on Edge', () async {
      SharedPreferences.setMockInitialValues({'ttsProvider': 'android'});

      final settings = await AppSettings.load();

      expect(settings.ttsProvider, 'edge');
      // usesSelfHostedServer drives the server probe; a stale name must not
      // send the reader looking for a machine on the network.
      expect(settings.usesSelfHostedServer, isFalse);
    });

    test('leaves a usable engine alone, with its settings', () async {
      SharedPreferences.setMockInitialValues({
        'ttsProvider': 'edge',
        'edgeVoiceEs': 'es-ES-ElviraNeural',
        'piperLengthScale': 1.25,
      });

      final settings = await AppSettings.load();

      expect(settings.ttsProvider, 'edge');
      expect(settings.edgeVoiceEs, 'es-ES-ElviraNeural');
      // Los ajustes de un motor que esta compilación no trae sobreviven: si
      // más adelante se compila con servidor, el ritmo de Piper sigue ahí.
      expect(settings.piperLengthScale, 1.25);
    });
  });
}
