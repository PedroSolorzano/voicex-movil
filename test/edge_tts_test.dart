import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/tts/edge_tts_provider.dart';

void main() {
  group('voiceLocale', () {
    test('derives the locale from a neural voice name', () {
      expect(voiceLocale('es-MX-DaliaNeural'), 'es-MX');
      expect(voiceLocale('en-US-AvaMultilingualNeural'), 'en-US');
      expect(voiceLocale('pt-BR-ThalitaMultilingualNeural'), 'pt-BR');
    });

    test('falls back for malformed names', () {
      expect(voiceLocale('garbage'), 'es-MX');
      expect(voiceLocale(''), 'es-MX');
    });
  });

  group('splitForSynthesis', () {
    test('leaves short text untouched', () {
      expect(splitForSynthesis('Una frase corta.'), ['Una frase corta.']);
    });

    test('splits long text below the limit', () {
      final sentence = 'Esta es una oración de relleno bastante larga. ';
      final text = sentence * 80; // ~3,700 chars
      final chunks = splitForSynthesis(text, maxChars: 500);

      expect(chunks.length, greaterThan(1));
      for (final c in chunks) {
        expect(c.length, lessThanOrEqualTo(500));
      }
    });

    test('preserves the full text across chunks', () {
      final text = List.generate(60, (i) => 'Frase número $i.').join(' ');
      final chunks = splitForSynthesis(text, maxChars: 200);
      expect(chunks.join(' '), text);
    });

    test('emits an over-long sentence on its own rather than cutting a word', () {
      final huge = 'palabra ' * 100; // one sentence, no terminal punctuation
      final chunks = splitForSynthesis(huge.trim(), maxChars: 100);
      expect(chunks.length, 1);
      expect(chunks.first, huge.trim());
    });
  });
}
