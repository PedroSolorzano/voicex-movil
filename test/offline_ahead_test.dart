import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/storage/offline_ahead.dart';

/// How much can be heard before the network is needed again.
void main() {
  group('offlineAheadFrom', () {
    test('adds up the run from the reading position to the first gap', () {
      final got = offlineAheadFrom(
        chapterLengths: [10],
        chapter: 0,
        paragraph: 2,
        secondsByParagraph: {(0, 1): 99, (0, 2): 10, (0, 3): 20, (0, 5): 40},
      )!;
      // Paragraph 1 is behind; 4 is missing, so 5 does not count.
      expect(got.seconds, 30);
      expect((got.endChapter, got.endParagraph), (0, 3));
    });

    test('keeps going into the next chapter, over an empty one', () {
      final got = offlineAheadFrom(
        chapterLengths: [2, 0, 2],
        chapter: 0,
        paragraph: 1,
        secondsByParagraph: {(0, 1): 5, (2, 0): 5, (2, 1): 5},
      )!;
      expect(got.seconds, 15);
      expect((got.endChapter, got.endParagraph), (2, 1));
    });

    test('nothing when the current paragraph is not downloaded', () {
      expect(
          offlineAheadFrom(
              chapterLengths: [3],
              chapter: 0,
              paragraph: 0,
              secondsByParagraph: {(0, 1): 5}),
          isNull);
    });

    test('the end of the book ends the run', () {
      final got = offlineAheadFrom(
        chapterLengths: [2],
        chapter: 0,
        paragraph: 0,
        secondsByParagraph: {(0, 0): 1, (0, 1): 1},
      )!;
      expect(got.seconds, 2);
    });
  });

  group('storedAudioSeconds', () {
    late Directory tmp;
    setUp(() async => tmp = await Directory.systemTemp.createTemp('voicex_dur'));
    tearDown(() async => tmp.delete(recursive: true));

    test('an mp3 at 96 kbps: 12 000 bytes are one second', () async {
      final f = File('${tmp.path}/a.mp3')..writeAsBytesSync(List.filled(24000, 0));
      expect(await storedAudioSeconds(f.path), 2);
    });

    test('a WAV reads its byte rate from the header', () async {
      final header = ByteData(44)..setUint32(28, 48000, Endian.little);
      final f = File('${tmp.path}/a.wav')
        ..writeAsBytesSync([...header.buffer.asUint8List(), ...List.filled(96000, 0)]);
      expect(await storedAudioSeconds(f.path), 2);
    });

    test('a missing or empty file is not counted', () async {
      expect(await storedAudioSeconds('${tmp.path}/no.mp3'), isNull);
      final f = File('${tmp.path}/e.mp3')..writeAsBytesSync([]);
      expect(await storedAudioSeconds(f.path), isNull);
    });
  });

  test('formatListening', () {
    expect(formatListening(20), 'menos de 1 min');
    expect(formatListening(45 * 60), '45 min');
    expect(formatListening(2 * 3600), '2 h');
    expect(formatListening(2 * 3600 + 10 * 60), '2 h 10 min');
  });
}
