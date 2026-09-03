import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicex_movil/config/settings.dart';

/// Retiring an engine leaves its name behind in SharedPreferences on every
/// phone that had it selected. `load()` has to bring that back to an engine the
/// app still ships, or the reader boots naming one that no longer exists —
/// poisoning the cache key and the status bar even though the factory quietly
/// hands back Edge.
void main() {
  group('resolveEngine', () {
    test('keeps the engines the app still has', () {
      for (final engine in ttsEngines) {
        expect(AppSettings.resolveEngine(engine), engine);
      }
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

  group('load', () {
    test('a phone left on Android TTS comes back on Edge', () async {
      SharedPreferences.setMockInitialValues({'ttsProvider': 'android'});

      final settings = await AppSettings.load();

      expect(settings.ttsProvider, 'edge');
      // usesSelfHostedServer drives the server probe; a stale name must not
      // send the reader looking for a machine on the network.
      expect(settings.usesSelfHostedServer, isFalse);
    });

    test('leaves a valid engine alone, with its settings', () async {
      SharedPreferences.setMockInitialValues({
        'ttsProvider': 'kokoro',
        'kokoroBaseUrl': 'http://192.168.1.50:8880',
      });

      final settings = await AppSettings.load();

      expect(settings.ttsProvider, 'kokoro');
      expect(settings.usesSelfHostedServer, isTrue);
      expect(settings.selfHostedUrl, 'http://192.168.1.50:8880');
    });
  });
}
