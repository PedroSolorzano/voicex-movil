import 'dart:io';

/// Bitrate of every mp3 the app stores: the voice server encodes at 96k
/// (`tools/mlx/server.py`, `_a_mp3`) and Edge is asked for
/// `audio-24khz-96kbitrate-mono-mp3`. It is what the `f96` cache tag names.
const _mp3BitsPerSecond = 96000;

/// How long one stored paragraph plays at normal speed, in seconds.
///
/// From the file itself, not from the text: a character-based estimate is off
/// by voice and by engine, and this number is what someone plans a drive on.
/// A constant-bitrate mp3 is size over bitrate; a WAV (the phone's own engine)
/// says its rate in the header. Null when the file is gone or unreadable.
Future<double?> storedAudioSeconds(String path) async {
  final file = File(path);
  try {
    final bytes = await file.length();
    if (bytes == 0) return null;
    if (!path.toLowerCase().endsWith('.wav')) {
      return bytes * 8 / _mp3BitsPerSecond;
    }
    final raf = await file.open();
    try {
      final h = await raf.read(44);
      if (h.length < 44) return null;
      final byteRate = h[28] | h[29] << 8 | h[30] << 16 | h[31] << 24;
      return byteRate > 0 ? (bytes - 44) / byteRate : null;
    } finally {
      await raf.close();
    }
  } catch (_) {
    return null;
  }
}

/// Downloaded listening time from the reading position onward, without a gap.
class OfflineAhead {
  /// Seconds at normal speed.
  final double seconds;

  /// Last paragraph covered: where the next download should start.
  final int endChapter, endParagraph;

  const OfflineAhead(this.seconds, this.endChapter, this.endParagraph);
}

/// Walks forward from ([chapter], [paragraph]) while every paragraph has
/// downloaded audio, adding up its duration, and stops at the first one that
/// does not: past that point the reader would need the network.
///
/// Only the *continuous* run counts. Audio downloaded further ahead, after a
/// hole, does not help the person who is about to drive through the hole.
/// Chapters without paragraphs are stepped over. Null when the current
/// paragraph itself is not downloaded.
OfflineAhead? offlineAheadFrom({
  required List<int> chapterLengths,
  required int chapter,
  required int paragraph,
  required Map<(int, int), double> secondsByParagraph,
}) {
  var total = 0.0;
  (int, int)? last;
  var c = chapter, p = paragraph;
  while (c < chapterLengths.length) {
    if (p >= chapterLengths[c]) {
      c++;
      p = 0;
      continue;
    }
    final s = secondsByParagraph[(c, p)];
    if (s == null) break;
    total += s;
    last = (c, p);
    p++;
  }
  return last == null ? null : OfflineAhead(total, last.$1, last.$2);
}

/// "2 h 10 min", "45 min", "menos de 1 min".
String formatListening(double seconds) {
  final minutes = (seconds / 60).round();
  if (minutes < 1) return 'menos de 1 min';
  final h = minutes ~/ 60, m = minutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}
