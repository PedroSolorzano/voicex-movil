import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/epub/text_align.dart';
import 'package:voicex_movil/tts/kokoro_tts_provider.dart';

void main() {
  group('kokoroLangCode', () {
    test('maps the book language to a Kokoro language pack', () {
      // Getting this wrong makes Spanish come out with English pronunciation.
      expect(kokoroLangCode('es'), 'e');
      expect(kokoroLangCode('es-MX'), 'e');
      expect(kokoroLangCode('en'), 'a');
      expect(kokoroLangCode('en-US'), 'a');
    });

    test('defaults to English for anything unexpected', () {
      expect(kokoroLangCode(''), 'a');
      expect(kokoroLangCode('fr'), 'a');
    });
  });

  group('parseKokoroTimestamps', () {
    test('converts seconds to milliseconds', () {
      final ts = parseKokoroTimestamps([
        {'word': 'Hola', 'start_time': 0.5, 'end_time': 0.75},
      ]);
      expect(ts.single.word, 'Hola');
      expect(ts.single.offsetMs, 500);
      expect(ts.single.durationMs, 250);
    });

    test('keeps punctuation attached to the word', () {
      // Kokoro returns "—No" and "aquello." with punctuation included; the text
      // aligner looks those up literally in the paragraph.
      final ts = parseKokoroTimestamps([
        {'word': '—No', 'start_time': 0.0, 'end_time': 0.2},
        {'word': 'aquello.', 'start_time': 0.2, 'end_time': 0.6},
      ]);
      expect(ts.map((t) => t.word).toList(), ['—No', 'aquello.']);
    });

    test('drops empty words', () {
      final ts = parseKokoroTimestamps([
        {'word': '  ', 'start_time': 0.0, 'end_time': 0.1},
        {'word': 'sí', 'start_time': 0.1, 'end_time': 0.3},
      ]);
      expect(ts.length, 1);
    });

    test('never yields a negative duration', () {
      final ts = parseKokoroTimestamps([
        {'word': 'x', 'start_time': 1.0, 'end_time': 0.5},
      ]);
      expect(ts.single.durationMs, 0);
    });

    test('returns empty for anything unparseable', () {
      expect(parseKokoroTimestamps(null), isEmpty);
      expect(parseKokoroTimestamps('no soy una lista'), isEmpty);
      expect(parseKokoroTimestamps(const []), isEmpty);
    });

    test('survives the duplicate words older servers emit', () {
      // v0.2 repeated every word; buildWordMarks must still land them once.
      final ts = parseKokoroTimestamps([
        {'word': 'uno', 'start_time': 0.0, 'end_time': 0.2},
        {'word': 'uno', 'start_time': 0.0, 'end_time': 0.2},
        {'word': 'dos', 'start_time': 0.2, 'end_time': 0.4},
        {'word': 'dos', 'start_time': 0.2, 'end_time': 0.4},
      ]);
      expect(ts.length, 4);

      final marks = buildWordMarks(ts, 'uno dos');
      expect(marks.length, 2, reason: 'el duplicado debe descartarse solo');
      expect(marks.map((m) => m.start).toList(), [0, 4]);
    });
  });
}
