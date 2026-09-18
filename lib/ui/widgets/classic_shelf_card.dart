import 'package:flutter/material.dart';
import 'classic_card_parts.dart';
import 'library_skin.dart';

/// One entry of the "Clásica" skin: a page of an antiquarian catalogue.
///
/// No card surface — the parchment behind the list is the page. The book's
/// cover, bound, on the left; title, author, publisher and year, and the
/// opening of the description on the right; an ornamental rule between
/// entries.
class ClassicShelfCard extends StatelessWidget {
  final Map<String, dynamic> book;
  final double progress;

  /// The last entry does not draw the rule under itself.
  final bool isLast;
  final VoidCallback onRead;
  final VoidCallback onDelete;
  final VoidCallback onInfo;
  final ValueChanged<String> onLanguageToggle;

  const ClassicShelfCard({
    super.key,
    required this.book,
    required this.progress,
    required this.onRead,
    required this.onDelete,
    required this.onInfo,
    required this.onLanguageToggle,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    const skin = LibrarySkin.classic;
    final title = book['title'] as String? ?? 'Sin título';
    final author = book['author'] as String? ?? 'Desconocido';
    final language = book['language'] as String? ?? 'es';
    final description = plainDescription(book['description'] as String?);
    // The year is already on the catalogue line below; here only the house.
    final publisher = (book['publisher'] as String?)?.trim() ?? '';

    final garamond = TextStyle(fontFamily: 'EBGaramond', color: skin.ink);

    return Column(
      children: [
        InkWell(
          onTap: onRead,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FramedCover(
                      coverPath: book['cover_path'] as String?,
                      title: title,
                      width: 84,
                      height: 124,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Room on the right for the menu, which floats over the
                          // corner: in the row it made every title 48 dp tall.
                          Padding(
                            padding: const EdgeInsets.only(top: 4, right: 32),
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: skinTitleStyle(18, skin.ink!),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: garamond.copyWith(
                                fontSize: 17, fontStyle: FontStyle.italic),
                          ),
                          if (publisher.isNotEmpty)
                            Text(
                              publisher,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: garamond.copyWith(
                                  fontSize: 14, color: skin.inkMuted),
                            ),
                          if (description != null) ...[
                            const SizedBox(height: 6),
                            Text(
                              description,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  garamond.copyWith(fontSize: 14.5, height: 1.3),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text(
                            catalogLine(book, progress),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 11.5,
                              fontVariations: wght(500),
                              letterSpacing: 0.6,
                              color: skin.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 0,
                child: SkinActionsMenu(
                  language: language,
                  onInfo: onInfo,
                  onLanguageToggle: onLanguageToggle,
                  onDelete: onDelete,
                ),
              ),
            ],
          ),
        ),
        if (!isLast) _Ornament(color: skin.accent!),
      ],
    );
  }
}

/// `──── ❦ ────`, the rule between catalogue entries.
class _Ornament extends StatelessWidget {
  final Color color;
  const _Ornament({required this.color});

  @override
  Widget build(BuildContext context) {
    final line = Expanded(
      child: Container(height: 1, color: color.withValues(alpha: 0.55)),
    );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Row(
          children: [
            line,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text('❦', style: TextStyle(color: color, fontSize: 16)),
            ),
            line,
          ],
        ),
      ),
    );
  }
}
