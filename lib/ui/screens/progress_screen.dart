import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../errors.dart';
import '../../stats/quotes.dart';
import '../../stats/reader_rank.dart';
import '../../stats/tangible.dart';
import '../providers/reading_stats_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/book_tower.dart';
import '../widgets/library_skin.dart';

/// Where the reader sees how far they have come.
///
/// Numbers, but always next to something to picture: a pile of books, a
/// multiple of a book everyone knows, a week of bars. Every comparison is
/// against a book, against a reference with its source, or against the
/// reader's own best — never against other people.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skin = LibrarySkin.of(
        ref.watch(settingsProvider).valueOrNull?.librarySkin ?? 'modern');
    final themed = libraryThemeData(skin, Theme.of(context));

    // Paper, not wood, under the page on every classic skin: the catalogue
    // skin's wooden background is for cards to sit on, and this screen is
    // text. The Builder hands the sheets the themed context, as in the
    // library.
    return Theme(
      data: skin.isModern
          ? themed
          : themed.copyWith(scaffoldBackgroundColor: skin.paper),
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Tu progreso')),
          body: DecoratedBox(
            decoration: BoxDecoration(
              image: skin.isModern
                  ? null
                  : const DecorationImage(
                      image: AssetImage('assets/skins/parchment.png'),
                      repeat: ImageRepeat.repeat,
                    ),
            ),
            child: ref.watch(readingStatsProvider).when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text(friendlyError(e))),
                  data: (stats) => _Body(stats: stats, skin: skin),
                ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final ReadingStats stats;
  final LibrarySkin skin;
  const _Body({required this.stats, required this.skin});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final quote = quoteForDay(now);
    final dayOfYear = now.difference(DateTime(now.year)).inDays;
    final equivalent = equivalence(stats.pages, dayOfYear);
    final heading = skin.isModern
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
        : skinTitleStyle(15, skin.ink!);

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: heading),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        // The quote of the day.
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
          child: Column(
            children: [
              Text(
                '«${quote.text}»',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic, height: 1.35),
              ),
              const SizedBox(height: 6),
              Text('— ${quote.author}',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),

        // Rank.
        section('Tu rango', [
          Text(
            '${stats.title} · Nivel ${stats.level}',
            style: skin.isModern
                ? theme.textTheme.headlineSmall
                : skinTitleStyle(22, skin.ink!),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
                value: stats.progressToNext, minHeight: 8),
          ),
          const SizedBox(height: 6),
          Text('Faltan ${formatPages(stats.pagesToNext)} páginas para '
              '${stats.nextTitle}'),
        ]),

        // Numbers, each with something to picture beside it.
        section('Páginas', [
          Row(
            children: [
              _Figure(label: 'Hoy', pages: stats.todayPages),
              _Figure(label: 'Esta semana', pages: stats.weekPages),
              _Figure(label: 'En total', pages: stats.pages),
            ],
          ),
          if (equivalent != null) ...[
            const SizedBox(height: 12),
            Text(equivalent, style: theme.textTheme.bodyLarge),
          ],
          if (stats.pages >= 20)
            Text(
              'En papel, una pila de '
              '${stackHeightCm(stats.pages).toStringAsFixed(1).replaceAll('.', ',')} cm.',
              style: theme.textTheme.bodySmall,
            ),
        ]),

        // Read vs listened.
        if (stats.totalChars > 0)
          section('Leído y escuchado', [
            _SplitBar(
              read: stats.readChars,
              listened: stats.listenedChars,
            ),
          ]),

        // The tower.
        section(
            stats.finished.isEmpty
                ? 'Tu pila de libros'
                : 'Tu pila de libros · ${stats.finished.length} '
                    '${stats.finished.length == 1 ? 'terminado' : 'terminados'}',
            [
              BookTower(
                finished: stats.finished,
                current: stats.current,
                skin: skin,
              ),
            ]),

        // The week.
        section('Los últimos siete días', [
          _WeekBars(days: stats.thisWeek),
          if (stats.bestDay case final best?) ...[
            const SizedBox(height: 10),
            Text(
              'Tu mejor día: ${formatPages(ReaderRank.pagesOf(best.chars))} '
              'páginas, el ${_longDate(best.day)}.',
            ),
          ],
        ]),

        // The only figure about anyone else, and where it comes from.
        section('Como referencia', [
          Text(nationalReference.text),
          if (stats.finished.isNotEmpty)
            Text(
              'Tú ya terminaste ${stats.finished.length} '
              '${stats.finished.length == 1 ? 'libro' : 'libros'} aquí.',
            ),
          const SizedBox(height: 4),
          Text('Fuente: ${nationalReference.source}.',
              style: theme.textTheme.bodySmall),
        ]),

        // The ladder.
        section('Los rangos', [
          for (var level = 1; level <= ReaderRank.titles.length; level++)
            _RankRow(level: level, current: stats.level),
          if (stats.level >= ReaderRank.titles.length)
            _RankRow(level: stats.level + 1, current: stats.level),
        ]),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  final String label;
  final double pages;
  const _Figure({required this.label, required this.pages});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(formatPages(pages), style: theme.textTheme.headlineMedium),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SplitBar extends StatelessWidget {
  final int read;
  final int listened;
  const _SplitBar({required this.read, required this.listened});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = read + listened;
    final readPages = formatPages(ReaderRank.pagesOf(read));
    final heardPages = formatPages(ReaderRank.pagesOf(listened));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                if (read > 0)
                  Expanded(
                      flex: read * 1000 ~/ total + 1,
                      child: ColoredBox(color: scheme.primary)),
                if (listened > 0)
                  Expanded(
                      flex: listened * 1000 ~/ total + 1,
                      child: ColoredBox(color: scheme.tertiary)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _Swatch(color: scheme.primary),
            Text(' Leído: $readPages   '),
            _Swatch(color: scheme.tertiary),
            Text(' Escuchado: $heardPages'),
          ],
        ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  final Color color;
  const _Swatch({required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: 10, height: 10, color: color);
}

class _WeekBars extends StatelessWidget {
  final List<DayTotal> days;
  const _WeekBars({required this.days});

  static const _initials = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final most = days.fold<int>(0, (m, d) => d.chars > m ? d.chars : m);
    return SizedBox(
      height: 120,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, d) in days.indexed)
            Expanded(
              child: Semantics(
                label: '${_longDate(d.day)}: '
                    '${formatPages(ReaderRank.pagesOf(d.chars))} páginas',
                excludeSemantics: true,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 22,
                      // A day with some reading always shows a sliver, so it
                      // does not look the same as a day with none.
                      height: most == 0
                          ? 2
                          : (d.chars == 0 ? 2 : 6 + 80 * d.chars / most),
                      decoration: BoxDecoration(
                        color: i == days.length - 1
                            ? theme.colorScheme.primary
                            : theme.colorScheme.primary.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _initials[DateTime.parse(d.day).weekday - 1],
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: i == days.length - 1
                              ? FontWeight.bold
                              : null),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  final int level;
  final int current;
  const _RankRow({required this.level, required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reached = level <= current;
    final isCurrent = level == current;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            isCurrent
                ? Icons.star
                : (reached ? Icons.check : Icons.radio_button_unchecked),
            size: 18,
            color: reached
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$level. ${ReaderRank.titleFor(level)}',
              style: TextStyle(
                fontWeight: isCurrent ? FontWeight.bold : null,
                color: reached ? null : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text('${formatPages(ReaderRank.threshold(level).toDouble())} págs.',
              style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto',
  'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// "2026-09-03" → "3 de septiembre".
String _longDate(String day) {
  final d = DateTime.parse(day);
  return '${d.day} de ${_months[d.month - 1]}';
}
