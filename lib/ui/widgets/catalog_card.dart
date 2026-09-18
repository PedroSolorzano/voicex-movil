import 'package:flutter/material.dart';
import 'classic_card_parts.dart';
import 'library_skin.dart';

/// A library index card: the "Fichas" skin.
///
/// Cream stock with faint ruled lines and the red rule across the top, title
/// in Cinzel, author in italic, and — where a real card carries its call
/// number — the language, year and reading progress. The book's own cover is
/// pinned to the right edge like a photograph.
class CatalogCard extends StatelessWidget {
  final Map<String, dynamic> book;
  final double progress;
  final VoidCallback onRead;
  final VoidCallback onDelete;
  final VoidCallback onInfo;
  final ValueChanged<String> onLanguageToggle;

  const CatalogCard({
    super.key,
    required this.book,
    required this.progress,
    required this.onRead,
    required this.onDelete,
    required this.onInfo,
    required this.onLanguageToggle,
  });

  @override
  Widget build(BuildContext context) {
    const skin = LibrarySkin.catalog;
    final title = book['title'] as String? ?? 'Sin título';
    final author = book['author'] as String? ?? 'Desconocido';
    final language = book['language'] as String? ?? 'es';
    final started = progress > 0.001;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: skin.paper,
          borderRadius: BorderRadius.circular(2),
          boxShadow: const [
            BoxShadow(
                color: Color(0x80000000), blurRadius: 6, offset: Offset(0, 3)),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onRead,
            child: CustomPaint(
              painter: _RuledCard(
                  lines: skin.inkMuted!.withValues(alpha: 0.16)),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: skinTitleStyle(17, skin.ink!),
                          ),
                          const SizedBox(height: 6),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: 'Autor: ',
                                style: TextStyle(
                                    fontSize: 13, color: skin.inkMuted),
                              ),
                              TextSpan(
                                text: author,
                                style: const TextStyle(
                                    fontSize: 17, fontStyle: FontStyle.italic),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontFamily: 'EBGaramond', color: skin.ink),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  catalogLine(book, progress),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Cinzel',
                                    fontSize: 11.5,
                                    fontVariations: wght(500),
                                    letterSpacing: 0.6,
                                    color: skin.inkMuted,
                                  ),
                                ),
                              ),
                              SkinActionsMenu(
                                language: language,
                                onInfo: onInfo,
                                onLanguageToggle: onLanguageToggle,
                                onDelete: onDelete,
                              ),
                            ],
                          ),
                          if (started)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(1),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 2,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FramedCover(
                      coverPath: book['cover_path'] as String?,
                      title: title,
                      width: 60,
                      height: 88,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ruled lines and the red top rule of a library card. Faint on purpose: the
/// text is what has to be read.
class _RuledCard extends CustomPainter {
  final Color lines;
  _RuledCard({required this.lines});

  static const _red = Color(0x59B03A2E);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lines
      ..strokeWidth = 1;
    for (var y = 64.0; y < size.height - 4; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    canvas.drawLine(
      const Offset(0, 8),
      Offset(size.width, 8),
      Paint()
        ..color = _red
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_RuledCard old) => old.lines != lines;
}
