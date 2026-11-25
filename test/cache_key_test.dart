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
      expect(keyFor('qwen3'), startsWith('qwen3-'));
      expect(keyFor('chatterbox2'), startsWith('chatterbox2-'));
      expect(keyFor('android'), startsWith('android-'));
    });

    test('gives each engine a distinct key for the same paragraph', () {
      final keys = {for (final e in ttsEngines) keyFor(e)};
      expect(keys.length, ttsEngines.length);
    });

    test('the voice is part of the server engines key', () {
      // A server voice is a recording: another one is other audio, and what was
      // downloaded with the old one must not be served for the new one.
      expect(keyFor('qwen3'), 'qwen3-esposa');
      expect(keyFor('chatterbox2'), 'chatterbox2-colombiana');
      expect(keyFor('qwen3', settings: AppSettings(qwen3Voice: 'otra')),
          'qwen3-otra');
    });

    test('changing one engine voice leaves the other key alone', () {
      final changed = AppSettings(qwen3Voice: 'otra');
      expect(keyFor('chatterbox2', settings: changed), keyFor('chatterbox2'));
    });

    test('Chatterbox never gets the retired prefix', () {
      // `_dropRetiredEngineRows` deletes every row LIKE 'chatterbox-%' on each
      // start, because the first Chatterbox left in 0.8.0. A new engine called
      // `chatterbox` would have its downloads wiped the next time the app
      // opened. This is why the id is `chatterbox2`.
      expect(keyFor('chatterbox2'), isNot(startsWith('chatterbox-')));
    });

    test('separates languages where the voice does not already do it', () {
      // Edge voice ids carry their language, so the keys differ on their own;
      // the phone engine puts the language in the key itself.
      expect(keyFor('edge'), isNot(keyFor('edge', forBook: english)));
      expect(keyFor('android'), isNot(keyFor('android', forBook: english)));
    });

    test('the server engines only serve Spanish, so no language in the key',
        () {
      // The reader never selects them for a book in another language, so there
      // is no collision to resolve.
      expect(keyFor('qwen3'), keyFor('qwen3', forBook: english));
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
      expect(ReaderNotifier.sanitizeCacheKey('qwen3:mi voz'), 'qwen3_mi_voz');
      expect(ReaderNotifier.sanitizeCacheKey('x@1.25'), 'x_1_25');
      expect(ReaderNotifier.sanitizeCacheKey('a/b\\c d'), 'a_b_c_d');
    });

    test('leaves an already-safe key untouched', () {
      expect(ReaderNotifier.sanitizeCacheKey('edge-es-MX-DaliaNeural'),
          'edge-es-MX-DaliaNeural');
    });
  });
}
