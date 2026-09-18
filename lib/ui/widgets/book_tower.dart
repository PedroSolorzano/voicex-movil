import 'package:flutter/material.dart';

import 'library_skin.dart';

/// Finished books as a pile of spines, newest on top, with the book in
/// progress resting on the pile.
///
/// A number of pages is abstract; a pile of books that grows is not. Each
/// spine is as thick as its book is long (from its paragraph count, which the
/// library already stores), so a finished *Quijote* looks like one.
class BookTower extends StatelessWidget {
  /// Most recent first, each with `title` and `total_paragraphs`.
  final List<Map<String, dynamic>> finished;
  final ({String title, int totalParagraphs, int at})? current;
  final LibrarySkin skin;

  const BookTower({
    super.key,
    required this.finished,
    required this.current,
    required this.skin,
  });

  /// Past this many the pile stops growing on screen and says how many more.
  static const maxSpines = 12;

  static const _leather = [
    Color(0xFF5B2C1E),
    Color(0xFF2E3B2A),
    Color(0xFF1F2F46),
    Color(0xFF6B4A1C),
    Color(0xFF4A2A3A),
    Color(0xFF3A2415),
  ];
  static const _gilt = Color(0xFFE8D29A);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (finished.isEmpty && current == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'Aquí se irán apilando los libros que termines.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }

    final shown = finished.take(maxSpines).toList();
    final hidden = finished.length - shown.length;

    return Column(
      children: [
        if (current case final c?)
          // Full width, with the progress as a gilt band along the bottom. An
          // earlier version drew the width itself as the progress: at 22 % the
          // spine was too narrow for its title, and nobody read the width as
          // progress anyway.
          _Spine(
            title: 'En curso · ${_percent(c)} % · ${c.title}',
            paragraphs: c.totalParagraphs,
            color: _leather.first,
            widthFactor: 0.9,
            progress: c.totalParagraphs <= 0
                ? 0
                : (c.at / c.totalParagraphs).clamp(0.0, 1.0),
            skin: skin,
          ),
        for (final (i, book) in shown.indexed)
          _Spine(
            title: book['title'] as String? ?? '',
            paragraphs: (book['total_paragraphs'] as int?) ?? 0,
            // By title rather than position, so a book keeps its colour as
            // newer ones land on top of it.
            color: _leather[(book['title'] as String? ?? '').hashCode.abs() %
                _leather.length],
            widthFactor: 0.78 + ((i * 7 + 3) % 5) * 0.045,
            skin: skin,
          ),
        if (hidden > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('y $hidden más debajo',
                style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }

  static int _percent(({String title, int totalParagraphs, int at}) c) =>
      c.totalParagraphs <= 0
          ? 0
          : (100 * c.at / c.totalParagraphs).floor().clamp(0, 100);
}

class _Spine extends StatelessWidget {
  final String title;
  final int paragraphs;
  final Color color;
  final double widthFactor;
  final LibrarySkin skin;

  /// Fraction read, for the book in progress; null on a finished one.
  final double? progress;

  const _Spine({
    required this.title,
    required this.paragraphs,
    required this.color,
    required this.widthFactor,
    required this.skin,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    // A novel of ~2,000 paragraphs comes out around 30 px; the clamp keeps a
    // short story legible and a doorstop from swallowing the screen.
    final thickness = (14 + paragraphs / 90).clamp(18.0, 38.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: thickness,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.symmetric(
              vertical: BorderSide(
                  color: BookTower._gilt.withValues(alpha: 0.6), width: 2),
            ),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000), blurRadius: 2, offset: Offset(0, 1)),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (progress case final p?)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 2,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: p,
                      child: Container(height: 3, color: BookTower._gilt),
                    ),
                  ),
                ),
              Center(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: skin.isModern
                      ? const TextStyle(
                          color: BookTower._gilt,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        )
                      : skinTitleStyle(10.5, BookTower._gilt),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
