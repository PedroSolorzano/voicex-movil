import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/epub/models.dart';
import 'package:voicex_movil/epub/text_align.dart';
import 'package:voicex_movil/tts/models.dart';

WordTimestamp ts(String word, int offset, [int duration = 100]) =>
    WordTimestamp(word: word, offsetMs: offset, durationMs: duration);

void main() {
  group('buildWordMarks', () {
    test('anchors each word to its position in the text', () {
      const text = 'Hola mundo cruel';
      final marks = buildWordMarks(
          [ts('Hola', 0), ts('mundo', 100), ts('cruel', 200)], text);

      expect(marks.length, 3);
      expect(text.substring(marks[0].start, marks[0].end), 'Hola');
      expect(text.substring(marks[1].start, marks[1].end), 'mundo');
      expect(text.substring(marks[2].start, marks[2].end), 'cruel');
    });

    test('distinguishes repeated words by position', () {
      const text = 'no no no';
      final marks =
          buildWordMarks([ts('no', 0), ts('no', 100), ts('no', 200)], text);

      expect(marks.map((m) => m.start).toList(), [0, 3, 6]);
    });

    test('recovers after a token the engine reports but the text lacks', () {
      // The middle token does not exist in the text; the ones after it must
      // still land correctly instead of shifting.
      const text = 'uno dos tres';
      final marks = buildWordMarks(
          [ts('uno', 0), ts('XXX', 100), ts('tres', 200)], text);

      expect(marks.length, 2);
      expect(text.substring(marks.last.start, marks.last.end), 'tres');
    });

    test('carries the timing through to the mark', () {
      final marks = buildWordMarks([ts('Hola', 500, 250)], 'Hola');
      expect(marks.single.startMs, 500);
      expect(marks.single.endMs, 750);
    });

    test('returns empty for empty input', () {
      expect(buildWordMarks([], 'texto'), isEmpty);
    });
  });

  group('buildSentenceRanges', () {
    test('locates every sentence in the raw text', () {
      final para = Paragraph(
        rawText: 'Uno. Dos. Tres.',
        sentences: [
          Sentence(text: 'Uno.', index: 0),
          Sentence(text: 'Dos.', index: 1),
          Sentence(text: 'Tres.', index: 2),
        ],
        index: 0,
      );

      final ranges = buildSentenceRanges(para);
      expect(ranges.length, 3);
      expect(para.rawText.substring(ranges[1].start, ranges[1].end), 'Dos.');
    });
  });

  group('activeWordIndex', () {
    final marks = buildWordMarks(
        [ts('uno', 0, 100), ts('dos', 100, 100), ts('tres', 200, 100)],
        'uno dos tres');

    test('returns -1 before the first word starts', () {
      expect(activeWordIndex(marks, -5), -1);
    });

    test('finds the word playing at a given time', () {
      expect(activeWordIndex(marks, 0), 0);
      expect(activeWordIndex(marks, 150), 1);
      expect(activeWordIndex(marks, 250), 2);
    });

    test('holds on the last word past the end', () {
      expect(activeWordIndex(marks, 99999), 2);
    });

    test('handles an empty mark list', () {
      expect(activeWordIndex([], 100), -1);
    });
  });

  group('sentenceAtOffset', () {
    final para = Paragraph(
      rawText: 'Uno dos. Tres cuatro.',
      sentences: [
        Sentence(text: 'Uno dos.', index: 0),
        Sentence(text: 'Tres cuatro.', index: 1),
      ],
      index: 0,
    );
    final ranges = buildSentenceRanges(para);

    test('maps a character offset to its sentence', () {
      expect(sentenceAtOffset(ranges, 0), 0);
      expect(sentenceAtOffset(ranges, 4), 0);
      expect(sentenceAtOffset(ranges, 9), 1);
    });

    test('attributes an offset past the end to the last sentence', () {
      expect(sentenceAtOffset(ranges, 999), 1);
    });

    test('returns -1 with no ranges', () {
      expect(sentenceAtOffset([], 5), -1);
    });
  });
}
