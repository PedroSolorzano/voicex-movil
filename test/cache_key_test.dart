import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/config/settings.dart';
import 'package:voicex_movil/epub/models.dart';
import 'package:voicex_movil/ui/providers/reader_provider.dart';

/// The cache key decides whether hours of downloaded audio are found again.
/// It has caused more regressions than anything else in this project: keys
/// with ':' and '@' that made every file write fail, and a fallback to Edge
/// filed under the name of the engine that was unreachable.
void main() {
  final book = Book(
    title: 'El Instituto',
    author: 'Stephen King',
    language: 'es',
    filePath: '/tmp/instituto.epub',
    chapters: const [],
  );
  final english = book.copyWith(language: 'en');

  String keyFor(String engine, {AppSettings? settings, Book? forBook}) =>
      ReaderNotifier.cacheKeyFor(
          engine, settings ?? AppSettings(), forBook ?? book);

  group('cacheKeyFor', () {
    test('names the engine, not just the voice', () {
      expect(keyFor('edge'), startsWith('edge-'));
      expect(keyFor('kokoro'), startsWith('kokoro-'));
      expect(keyFor('piper'), startsWith('piper-'));
    });

    test('gives each engine a distinct key for the same paragraph', () {
      final keys = {for (final e in ttsEngines) keyFor(e)};
      expect(keys.length, ttsEngines.length);
    });

    test('separates languages where the voice does not already do it', () {
      // Edge and Piper voice ids carry their language, so the keys differ on
      // their own. Kokoro's do not — see the collision test below.
      expect(keyFor('edge'), isNot(keyFor('edge', forBook: english)));
      expect(keyFor('piper'), isNot(keyFor('piper', forBook: english)));
    });

    test('no colisiona aunque la misma voz sirva a los dos idiomas', () {
      // Este test documentaba lo contrario, y era un fallo: Kokoro usa
      // af_bella para español e inglés, y el idioma solo llegaba al servidor
      // como `lang_code`. Misma clave, audio distinto, y sonaba el que se
      // hubiera descargado primero.
      expect(keyFor('kokoro'), isNot(keyFor('kokoro', forBook: english)));
      expect(keyFor('kokoro'), 'kokoro-es-af_bella');
      expect(keyFor('kokoro', forBook: english), 'kokoro-en-af_bella');
    });

    test('folds the Piper pace in: it is baked into the samples', () {
      final slow = AppSettings(piperLengthScale: 1.25);
      expect(keyFor('piper'), endsWith('-1_00'));
      expect(keyFor('piper', settings: slow), endsWith('-1_25'));
    });

    test('leaves the Kokoro and Edge keys free of any pace', () {
      final slow = AppSettings(piperLengthScale: 1.25);
      expect(keyFor('kokoro', settings: slow), keyFor('kokoro'));
      expect(keyFor('edge', settings: slow), keyFor('edge'));
    });

    test('yields something usable as a filename', () {
      // The key is embedded in the cache filename. ':' and '@' once made every
      // write fail while the download bar still reached 100 %.
      for (final engine in ttsEngines) {
        for (final b in [book, english]) {
          expect(keyFor(engine, forBook: b),
              matches(RegExp(r'^[A-Za-z0-9_-]+$')),
              reason: '$engine key must survive as a path segment');
        }
      }
    });
  });

  group('sanitizeCacheKey', () {
    test('replaces every character a path segment cannot carry', () {
      expect(ReaderNotifier.sanitizeCacheKey('kokoro:af_bella'),
          'kokoro_af_bella');
      expect(ReaderNotifier.sanitizeCacheKey('piper@1.25'), 'piper_1_25');
      expect(ReaderNotifier.sanitizeCacheKey('a/b\\c d'), 'a_b_c_d');
    });

    test('leaves an already-safe key untouched', () {
      expect(ReaderNotifier.sanitizeCacheKey('edge-es-MX-DaliaNeural'),
          'edge-es-MX-DaliaNeural');
    });
  });

  group('piperPaceSuffix', () {
    test('is the two-decimal pace, dot included as an underscore', () {
      expect(ReaderNotifier.piperPaceSuffix(1.0), '-1_00');
      expect(ReaderNotifier.piperPaceSuffix(1.25), '-1_25');
      expect(ReaderNotifier.piperPaceSuffix(0.9), '-0_90');
    });

    test('closes the key that cacheKeyFor builds', () {
      // The pace warning in settings looks for this as a suffix. Searching for
      // it as a prefix never matched, so the warning fired at every nudge of
      // the slider — including one back to the downloaded pace.
      for (final pace in [0.9, 1.0, 1.25]) {
        final settings = AppSettings(piperLengthScale: pace);
        expect(keyFor('piper', settings: settings),
            endsWith(ReaderNotifier.piperPaceSuffix(pace)));
      }
    });
  });
}
