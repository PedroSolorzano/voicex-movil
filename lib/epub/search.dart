import 'models.dart';

/// One match, carrying what the results list needs to draw it and what the
/// reader needs to jump there.
///
/// [matchStart] and [matchEnd] index into [snippet], not into the paragraph:
/// the list highlights the match inside the fragment it shows, and nothing
/// else needs the position in the full text.
typedef SearchHit = ({
  int chapterIndex,
  int paragraphIndex,
  String snippet,
  int matchStart,
  int matchEnd,
});

/// Shorter than this matches half the book and costs more to render than it
/// helps.
const _minQuery = 2;

/// Characters of context kept on each side of a match.
const _context = 40;

/// Accents folded away so "arbol" finds "árbol", which is how people type on a
/// phone.
///
/// `ñ` is deliberately absent: in Spanish it is its own letter, not an `n`
/// with an ornament, and folding it would surface "año" when somebody searches
/// "ano".
const _accents = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
};

/// Lowercases and strips accents **one character at a time**.
///
/// The length has to survive the fold: the offsets found in the folded text
/// are used to cut the original, so a transformation that changed the length
/// would misplace every match after it. That rules out the usual
/// normalise-and-strip-combining-marks pass.
String _fold(String text) {
  final buffer = StringBuffer();
  for (final ch in text.toLowerCase().split('')) {
    buffer.write(_accents[ch] ?? ch);
  }
  return buffer.toString();
}

/// Finds [query] across [book], ignoring case and accents.
///
/// Cheap enough to run on every keystroke of a debounced field: the book is
/// already parsed into paragraphs in memory, so this is a scan over strings
/// that are already there. [limit] stops a one-letter-too-common query from
/// building thousands of rows nobody will scroll through.
List<SearchHit> searchBook(Book book, String query, {int limit = 200}) {
  final needle = _fold(query.trim());
  if (needle.length < _minQuery) return const [];

  final hits = <SearchHit>[];
  for (var c = 0; c < book.chapters.length; c++) {
    final paragraphs = book.chapters[c].paragraphs;
    for (var p = 0; p < paragraphs.length; p++) {
      final raw = paragraphs[p].rawText;
      final haystack = _fold(raw);
      var from = 0;
      while (true) {
        final at = haystack.indexOf(needle, from);
        if (at < 0) break;
        final (snippet, start, end) = _snippet(raw, at, at + needle.length);
        hits.add((
          chapterIndex: c,
          paragraphIndex: p,
          snippet: snippet,
          matchStart: start,
          matchEnd: end,
        ));
        if (hits.length >= limit) return hits;
        from = at + needle.length;
      }
    }
  }
  return hits;
}

/// A fragment around the match, plus where the match sits inside it.
(String, int, int) _snippet(String raw, int start, int end) {
  final from = (start - _context).clamp(0, raw.length);
  final to = (end + _context).clamp(0, raw.length);
  final prefix = from > 0 ? '…' : '';
  final suffix = to < raw.length ? '…' : '';
  return (
    '$prefix${raw.substring(from, to)}$suffix',
    prefix.length + (start - from),
    prefix.length + (end - from),
  );
}
