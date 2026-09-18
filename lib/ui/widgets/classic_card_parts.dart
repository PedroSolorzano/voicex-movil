import 'dart:io';
import 'package:flutter/material.dart';
import 'library_skin.dart';

/// EPUB descriptions are HTML more often than not; the cards and the details
/// sheet show them as plain prose.
String? plainDescription(String? raw) {
  final text = raw
      // A space, not nothing: `</p><p>` is a paragraph break, and dropping
      // it glued "deshabitado.Encuentran" into one word.
      ?.replaceAll(RegExp(r'<[^>]*>'), ' ')
      // …but not before punctuation: "Fin<b>.</b>" is "Fin.", not "Fin .".
      .replaceAllMapped(RegExp(r'\s+([.,;:!?])'), (m) => m[1]!)
      .replaceAll(RegExp(r'\s+'), ' ')
      // Books imported before the parser put a space between paragraphs have
      // them glued in the database ("deshabitado.Encuentran", "harías?El").
      // A lowercase letter before the stop keeps "J.R.R. Tolkien" and
      // "EE.UU." out of it.
      .replaceAllMapped(
          RegExp(r'(\p{Ll}[.!?…»”"]+)([\p{Lu}¿¡«“])', unicode: true),
          (m) => '${m[1]} ${m[2]}')
      .trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// The year out of whatever an EPUB put in `dc:date` — "1925", "2015-03-01",
/// "March 1851". Null when there is no four-digit run in it.
String? yearOf(String? publishedDate) =>
    publishedDate == null ? null : RegExp(r'\d{4}').firstMatch(publishedDate)?[0];

/// Language and year, under a lot of the classic skin: `ES  ·  1984`.
String classicImprint(Map<String, dynamic> book) => [
      (book['language'] as String? ?? 'es').toUpperCase(),
      ?yearOf(book['published_date'] as String?),
    ].join('  ·  ');

/// Where the reader is with [book], as the classic skin prints it in red.
String classicStatus(Map<String, dynamic> book, double progress) {
  if (book['finished_at'] != null || progress >= 0.995) return 'Leído';
  if (progress > 0.001) {
    return 'En lectura · ${(progress * 100).toStringAsFixed(0)} %';
  }
  return 'Sin empezar';
}

/// The call number typed in the corner of a catalogue card: language, title
/// mark and year, one per line.
///
/// The mark comes from the title and not the author, as in the last part of a
/// Spanish signature ("N GAR cie"): the first surname cannot be told apart
/// from a middle name without knowing the person ("Gabriel García Márquez"
/// files under GAR, "Stephen King" under KIN), and a wrong mark is worse than
/// a plain one.
List<String> callNumber(Map<String, dynamic> book) {
  final title = (book['title'] as String? ?? '').toLowerCase();
  final words = title
      .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
      .where((w) => w.isNotEmpty)
      .toList();
  // A leading article does not file: "El talismán" goes under TAL.
  const articles = {
    'el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'the', 'a', 'an',
  };
  if (words.length > 1 && articles.contains(words.first)) words.removeAt(0);
  final joined = words.join();
  final mark = joined.substring(0, joined.length < 3 ? joined.length : 3);
  return [
    (book['language'] as String? ?? 'es').toUpperCase(),
    if (mark.isNotEmpty) mark.toUpperCase(),
    ?yearOf(book['published_date'] as String?),
  ];
}

/// The real cover, bound: a leather spine with raised bands, a gold fillet
/// round the board, and the page block showing along the fore-edge and foot.
///
/// The mockups draw a generic leather tome; the requirement is that the book's
/// own cover is always visible, so it goes on the board instead of being
/// replaced by it. Without a cover, the board carries the title the way a
/// spine would.
///
/// [ribbon] hangs a silk bookmark out of the foot of the volume: the book
/// that is being read. It overflows [height] by [ribbonDrop].
class FramedCover extends StatelessWidget {
  final String? coverPath;
  final String title;
  final double width;
  final double height;
  final bool ribbon;

  const FramedCover({
    super.key,
    required this.coverPath,
    required this.title,
    required this.width,
    required this.height,
    this.ribbon = false,
  });

  static const _leather = Color(0xFF4A2A18);
  static const _gold = Color(0xFFC9A45C);
  static const _spineWidth = 10.0;

  /// How far the ribbon hangs below the volume.
  static const ribbonDrop = 20.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (ribbon)
            Positioned(
              left: width * 0.55,
              bottom: -ribbonDrop,
              child: const CustomPaint(
                  size: Size(9, ribbonDrop + 8), painter: _Ribbon()),
            ),
          // The page block, a little smaller than the boards all round.
          const Positioned(
            left: _spineWidth,
            top: 3,
            right: 0,
            bottom: 0,
            child: CustomPaint(painter: _PageBlock()),
          ),
          // The front board and the spine.
          Positioned(
            left: 0,
            top: 0,
            right: 3,
            bottom: 4,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: _leather,
                borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(4), right: Radius.circular(2)),
                boxShadow: [
                  BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 4,
                      offset: Offset(1, 2)),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(
                    width: _spineWidth,
                    child: CustomPaint(painter: _Spine()),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(1, 3, 3, 3),
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          border: Border.all(color: _gold, width: 1),
                        ),
                        // No existsSync(): this runs while the list scrolls,
                        // and errorBuilder already covers a missing file.
                        child: coverPath == null
                            ? _spine()
                            : Image.file(
                                File(coverPath!),
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                                errorBuilder: (_, _, _) => _spine(),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _spine() => ColoredBox(
        color: _leather,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: skinTitleStyle(width < 70 ? 8 : 10, _gold),
            ),
          ),
        ),
      );
}

/// The spine: darker leather, rounded by a highlight, five raised bands.
class _Spine extends CustomPainter {
  const _Spine();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRRect(
      RRect.fromRectAndCorners(rect,
          topLeft: const Radius.circular(4),
          bottomLeft: const Radius.circular(4)),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF24120A), Color(0xFF5A3620), Color(0xFF2E180D)],
          stops: [0, 0.45, 1],
        ).createShader(rect),
    );
    final band = Paint()
      ..color = FramedCover._gold.withValues(alpha: 0.85)
      ..strokeWidth = 1.2;
    final shade = Paint()
      ..color = const Color(0x73000000)
      ..strokeWidth = 1;
    for (final f in const [0.12, 0.3, 0.5, 0.7, 0.88]) {
      final y = size.height * f;
      canvas.drawLine(Offset(1, y + 1.2), Offset(size.width, y + 1.2), shade);
      canvas.drawLine(Offset(1, y), Offset(size.width, y), band);
    }
  }

  @override
  bool shouldRepaint(_Spine old) => false;
}

/// The edges of the leaves, seen past the boards.
class _PageBlock extends CustomPainter {
  const _PageBlock();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFE9DCBB));
    final leaf = Paint()
      ..color = const Color(0x59795C36)
      ..strokeWidth = 0.6;
    // Fore-edge, then foot.
    for (var x = size.width - 2.4; x < size.width; x += 1.2) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), leaf);
    }
    for (var y = size.height - 3.2; y < size.height; y += 1.2) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), leaf);
    }
  }

  @override
  bool shouldRepaint(_PageBlock old) => false;
}

/// A silk bookmark, swallow-tailed.
class _Ribbon extends CustomPainter {
  const _Ribbon();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final silk = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w / 2, h - 5)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(silk.shift(const Offset(1, 1)),
        Paint()..color = const Color(0x40000000));
    canvas.drawPath(
      silk,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF7A1F16), Color(0xFFB23A2C), Color(0xFF8A261B)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_Ribbon old) => false;
}

/// Details, language and delete, behind one quiet button.
///
/// The modern card shows three Material icons; on paper they break the look,
/// and tapping the card already opens the book. Same actions, less noise.
class SkinActionsMenu extends StatelessWidget {
  final String language;
  final VoidCallback onInfo;
  final ValueChanged<String> onLanguageToggle;
  final VoidCallback onDelete;

  const SkinActionsMenu({
    super.key,
    required this.language,
    required this.onInfo,
    required this.onLanguageToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final other = language == 'es' ? 'en' : 'es';
    return PopupMenuButton<String>(
      tooltip: 'Más',
      icon: Icon(Icons.more_horiz,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      onSelected: (v) => switch (v) {
        'info' => onInfo(),
        'lang' => onLanguageToggle(other),
        _ => onDelete(),
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'info', child: Text('Detalles')),
        PopupMenuItem(
            value: 'lang',
            child: Text('Cambiar idioma a ${other.toUpperCase()}')),
        const PopupMenuItem(value: 'delete', child: Text('Eliminar')),
      ],
    );
  }
}
