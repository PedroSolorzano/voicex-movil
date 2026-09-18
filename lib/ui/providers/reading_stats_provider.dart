import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../stats/reader_rank.dart';
import '../../storage/repositories.dart';

/// Something worth telling the reader right now: a new rank, a finished book.
///
/// Separate from `ReaderState.statusMessage`, which is the small status line
/// under the controls. A new rank deserves a SnackBar, once, and then to go
/// away; the screen shows it and sets this back to null.
final readingMilestoneProvider = StateProvider<String?>((ref) => null);

typedef DayTotal = ({String day, int chars});

/// Everything the rank header and the progress screen show, read in one go.
class ReadingStats {
  final int readChars;
  final int listenedChars;

  /// The last fourteen days, oldest first: the latter seven are "this week",
  /// the former seven the week the weekly summary compares it with.
  final List<DayTotal> lastFourteen;
  final DayTotal? bestDay;

  /// Finished books, most recent first: `title`, `author`,
  /// `total_paragraphs`, `finished_at`.
  final List<Map<String, dynamic>> finished;
  final ({String title, int totalParagraphs, int at})? current;

  const ReadingStats({
    required this.readChars,
    required this.listenedChars,
    required this.lastFourteen,
    required this.bestDay,
    required this.finished,
    required this.current,
  });

  static const empty = ReadingStats(
    readChars: 0,
    listenedChars: 0,
    lastFourteen: [],
    bestDay: null,
    finished: [],
    current: null,
  );

  int get totalChars => readChars + listenedChars;
  double get pages => ReaderRank.pagesOf(totalChars);
  int get level => ReaderRank.levelFor(pages);
  String get title => ReaderRank.titleFor(level);
  double get progressToNext => ReaderRank.progressToNext(pages);
  String get nextTitle => ReaderRank.titleFor(level + 1);
  double get pagesToNext => ReaderRank.threshold(level + 1) - pages;

  List<DayTotal> get thisWeek =>
      lastFourteen.length < 7 ? lastFourteen : lastFourteen.sublist(7);

  double get todayPages => ReaderRank.pagesOf(
      lastFourteen.isEmpty ? 0 : lastFourteen.last.chars);

  double get weekPages => ReaderRank.pagesOf(
      thisWeek.fold<int>(0, (sum, d) => sum + d.chars));

  double get previousWeekPages => ReaderRank.pagesOf(lastFourteen.length < 14
      ? 0
      : lastFourteen
          .sublist(0, 7)
          .fold<int>(0, (sum, d) => sum + d.chars));
}

final readingStatsProvider = FutureProvider<ReadingStats>((ref) async {
  final repo = ReadingLogRepo();
  final totals = await repo.totals();
  return ReadingStats(
    readChars: totals.readChars,
    listenedChars: totals.listenedChars,
    lastFourteen: await repo.lastDays(14),
    bestDay: await repo.bestDay(),
    finished: await repo.finishedBooks(),
    current: await repo.currentBook(),
  );
});

/// "1.240", "12", "0,4": pages the way the screens show them.
String formatPages(double pages) {
  if (pages > 0 && pages < 10 && pages != pages.roundToDouble()) {
    return pages.toStringAsFixed(1).replaceAll('.', ',');
  }
  final whole = pages.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) out.write('.');
    out.write(whole[i]);
  }
  return out.toString();
}
