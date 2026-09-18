/// Where a credited paragraph came from.
enum CreditSource { read, listened }

/// What one movement through the book earns.
typedef Credit = ({int chars, bool finished});

/// Decides how much of a movement through the book counts as reading.
///
/// The rules exist so the ranks mean something: they reward reading and
/// listening, and ignore everything else that moves the position.
///
/// - **Listening**: a paragraph that finished playing counts whole.
/// - **Silent reading**: moving forward 1 to [maxSilentStep] paragraphs counts
///   the ones passed. More than that in one settle is a fling of the thumb,
///   not reading; moving back counts nothing and takes nothing away.
/// - **Jumps** (table of contents, bookmarks, search) never reach this class.
/// - **Pace ceiling**: never more than [maxCharsPerMinute] in any sliding
///   minute. About 1,000 words a minute, well past any real reader, and well
///   past the fastest the audio goes (2x is ~1,700 characters a minute).
///
/// No Flutter, no database: it only does arithmetic on the book's character
/// prefix sums (`buildCharsPrefix`, where paragraph `i` is
/// `prefix[i + 1] - prefix[i]`).
class ReadingCredit {
  static const maxSilentStep = 3;
  static const maxCharsPerMinute = 6000;

  /// Close enough to the end to call the book finished while reading in
  /// silence. The list cannot scroll its last paragraph to the top of the
  /// screen, so "reached the last paragraph" would almost never happen; this
  /// is one page.
  static const finishSlackChars = 1800;

  final List<int> _prefix;
  final List<({DateTime at, int chars})> _window = [];

  ReadingCredit(List<int> charsPrefix) : _prefix = charsPrefix;

  int get _paragraphs => _prefix.length - 1;

  /// The paragraph at global index [global] finished playing.
  Credit listened(int global, DateTime now) {
    if (global < 0 || global >= _paragraphs) return (chars: 0, finished: false);
    final chars = _prefix[global + 1] - _prefix[global];
    return (
      chars: _cap(chars, now),
      finished: global == _paragraphs - 1,
    );
  }

  /// The topmost visible paragraph moved from [from] to [to] while reading
  /// without audio.
  Credit read(int from, int to, DateTime now) {
    final step = to - from;
    if (step < 1 || step > maxSilentStep) return (chars: 0, finished: false);
    if (from < 0 || to > _paragraphs) return (chars: 0, finished: false);

    final left = _prefix.last - _prefix[to];
    final finished = left <= finishSlackChars;
    // At the end, what is left is on screen: it counts, or the last page of
    // every book read in silence would be lost.
    final end = finished ? _prefix.last : _prefix[to];
    return (chars: _cap(end - _prefix[from], now), finished: finished);
  }

  int _cap(int chars, DateTime now) {
    if (chars <= 0) return 0;
    final since = now.subtract(const Duration(minutes: 1));
    _window.removeWhere((e) => !e.at.isAfter(since));
    final used = _window.fold<int>(0, (sum, e) => sum + e.chars);
    final granted = (maxCharsPerMinute - used).clamp(0, chars);
    if (granted > 0) _window.add((at: now, chars: granted));
    return granted;
  }
}
