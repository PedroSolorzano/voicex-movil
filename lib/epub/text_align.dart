import 'models.dart';
import '../tts/models.dart';

/// A spoken word anchored to its character range in the paragraph text.
typedef WordMark = ({int startMs, int endMs, int start, int end});

/// A sentence's character range within the paragraph text.
typedef SentenceRange = ({int start, int end, int index});

/// Anchors each word timestamp to where that word actually sits in [rawText].
///
/// The previous approach distributed timestamps across sentences by counting
/// whitespace-separated words, which assumed the engine emits exactly one
/// boundary per token. Any mismatch — numbers, hyphenation, punctuation-only
/// tokens — shifted every following sentence for the rest of the paragraph
/// with no way to recover.
///
/// Searching forward from a cursor instead means an unmatched token is simply
/// skipped and the next one re-anchors, so a glitch stays local.
List<WordMark> buildWordMarks(List<WordTimestamp> timestamps, String rawText) {
  final marks = <WordMark>[];
  var cursor = 0;

  for (final t in timestamps) {
    final word = t.word.trim();
    if (word.isEmpty) continue;

    var index = rawText.indexOf(word, cursor);
    if (index < 0) {
      // Look from the start in case the engine reordered something; if it is
      // still missing, drop this token rather than desynchronising.
      index = rawText.indexOf(word);
      if (index < 0 || index < cursor) continue;
    }

    marks.add((
      startMs: t.offsetMs,
      endMs: t.offsetMs + t.durationMs,
      start: index,
      end: index + word.length,
    ));
    cursor = index + word.length;
  }

  return marks;
}

/// Character ranges of each sentence inside the paragraph text.
List<SentenceRange> buildSentenceRanges(Paragraph paragraph) {
  final ranges = <SentenceRange>[];
  var cursor = 0;

  for (final sentence in paragraph.sentences) {
    final index = paragraph.rawText.indexOf(sentence.text, cursor);
    if (index < 0) continue;
    ranges.add((
      start: index,
      end: index + sentence.text.length,
      index: sentence.index,
    ));
    cursor = index + sentence.text.length;
  }

  return ranges;
}

/// Index of the word being spoken at [elapsedMs], or -1 before the first word.
/// Marks are ordered by time, so a binary search keeps the 50 ms tick cheap
/// even for long paragraphs.
int activeWordIndex(List<WordMark> marks, int elapsedMs) {
  if (marks.isEmpty || elapsedMs < marks.first.startMs) return -1;

  var low = 0, high = marks.length - 1, found = -1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    if (marks[mid].startMs <= elapsedMs) {
      found = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return found;
}

/// Sentence index containing [charOffset], or -1 when outside every range.
int sentenceAtOffset(List<SentenceRange> ranges, int charOffset) {
  for (final r in ranges) {
    if (charOffset >= r.start && charOffset < r.end) return r.index;
  }
  // Past the last matched range: attribute to the final sentence.
  return ranges.isEmpty ? -1 : ranges.last.index;
}


/// Characters that count as part of a word when expanding a tap outwards.
/// Includes the apostrophe so "don't" and "l'agent" stay whole, and the hyphen
/// so "twenty-one" does too.
final _wordChar = RegExp(r"[\p{L}\p{N}'’\-]", unicode: true);

/// Character range of the word containing [offset], or null when the tap landed
/// on whitespace or punctuation.
///
/// Used to turn a tap anywhere in a paragraph into a word, without having to
/// build a tappable span per word — which would make rendering a whole chapter
/// far more expensive.
(int, int)? wordBoundaryAt(String text, int offset) {
  if (text.isEmpty || offset < 0 || offset >= text.length) return null;
  if (!_wordChar.hasMatch(text[offset])) return null;

  var start = offset;
  var end = offset;
  while (start > 0 && _wordChar.hasMatch(text[start - 1])) {
    start--;
  }
  while (end < text.length - 1 && _wordChar.hasMatch(text[end + 1])) {
    end++;
  }
  return (start, end + 1);
}
