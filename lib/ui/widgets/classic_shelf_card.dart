import 'package:flutter/material.dart';
import '../../stats/reader_rank.dart';
import 'classic_card_parts.dart';
import 'library_skin.dart';

/// One entry of the "Clásica" skin: a lot in an antiquarian bookseller's
/// catalogue, printed in two inks.
///
/// No card surface — the parchment behind the list is the page. What makes it
/// read as an old printed page rather than a list in a nice font: the lot
/// number in Roman numerals, the description justified and opened by a
/// rubricated initial, the reading status in the same red with a manicule,
/// the volume bound with its spine showing, and a silk ribbon hanging out of
/// the one being read. Red is used the way the old printers used it: only
/// where the eye has to land.
class ClassicShelfCard extends StatelessWidget {
  final Map<String, dynamic> book;
  final double progress;

  /// Position in the catalogue, from 1. Null leaves the lot unnumbered.
  final int? number;

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
    this.number,
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
    final status = classicStatus(book, progress);
    final reading = status.startsWith('En lectura');

    final garamond = TextStyle(fontFamily: 'EBGaramond', color: skin.ink);
    final small = TextStyle(
      fontFamily: 'Cinzel',
      fontSize: 11.5,
      fontVariations: wght(500),
      letterSpacing: 0.8,
      color: skin.accent,
    );

    return Column(
      children: [
        InkWell(
          onTap: onRead,
          child: Stack(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                    16, 14, 16, reading ? FramedCover.ribbonDrop : 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FramedCover(
                      coverPath: book['cover_path'] as String?,
                      title: title,
                      width: 92,
                      height: 130,
                      ribbon: reading,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (number case final n?)
                            Text('N.º ${ReaderRank.roman(n)}', style: small),
                          // Room on the right for the menu, which floats over the
                          // corner: in the row it made every title 48 dp tall.
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: 32),
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
                            _DropCapText(
                              text: description,
                              style:
                                  garamond.copyWith(fontSize: 14.5, height: 1.3),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                  text: classicImprint(book), style: small),
                              const TextSpan(text: '    '),
                              TextSpan(
                                text: switch (status) {
                                  'Sin empezar' => '☞ $status',
                                  'Leído' => '❧ $status',
                                  _ => status,
                                },
                                style: garamond.copyWith(
                                  fontSize: 15.5,
                                  fontStyle: FontStyle.italic,
                                  color: LibrarySkin.rubric,
                                ),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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

/// A paragraph opened by a two-line initial in red, and justified: the two
/// things every page printed before 1800 has and no phone screen does.
///
/// Flutter has no drop caps, so the text is measured once to find where its
/// second line ends: up to there it runs beside the initial, the rest runs
/// under it at full width. Four lines in all.
class _DropCapText extends StatelessWidget {
  final String text;
  final TextStyle style;

  const _DropCapText({required this.text, required this.style});

  static final _letter = RegExp(r'^\p{L}', unicode: true);

  @override
  Widget build(BuildContext context) {
    final initial = _letter.firstMatch(text)?[0];
    // "—Buenos días", "¿Quién…", "1984 fue…": an initial that is not a letter
    // is not an initial.
    if (initial == null) {
      return Text(text,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.justify,
          style: style);
    }
    final rest = text.substring(initial.length);

    return Semantics(
      label: text,
      excludeSemantics: true,
      child: LayoutBuilder(builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        // Measured with exactly what Text will draw with. The theme's default
        // style carries letter spacing; measuring without it put the line
        // break one word later than on screen, and that word was lost.
        final style = DefaultTextStyle.of(context).style.merge(this.style);
        final capStyle =
            skinTitleStyle(41, LibrarySkin.rubric).copyWith(height: 1.0);

        final cap = TextPainter(
          text: TextSpan(text: initial.toUpperCase(), style: capStyle),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        final capWidth = cap.width + 5;
        cap.dispose();

        final beside = constraints.maxWidth - capWidth;
        final probe = TextPainter(
          text: TextSpan(text: rest, style: style),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.justify,
          textScaler: scaler,
          maxLines: 2,
        )..layout(maxWidth: beside);
        final lineHeight = probe.preferredLineHeight;
        var under = '';
        if (probe.didExceedMaxLines) {
          final end = probe
              .getPositionForOffset(Offset(beside, lineHeight * 1.5))
              .offset;
          under = rest.substring(end).trimLeft();
        }
        probe.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: capWidth,
                  height: lineHeight * 2,
                  // The initial's own box is taller than two lines of text;
                  // what has to fit is the letter, not its leading.
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    maxHeight: double.infinity,
                    child: Transform.translate(
                      offset: const Offset(0, -3),
                      child: Text(initial.toUpperCase(), style: capStyle),
                    ),
                  ),
                ),
                Expanded(
                  // The whole text and a clip, not just the two lines: the
                  // last line of a paragraph is never justified, and this
                  // way the second line is not the last.
                  child: Text(rest,
                      maxLines: 2,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.justify,
                      style: style),
                ),
              ],
            ),
            if (under.isNotEmpty)
              Text(under,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.justify,
                  style: style),
          ],
        );
      }),
    );
  }
}

/// `──◆ ❦ ◆──`, the rule between lots, thinning out towards the margins.
class _Ornament extends StatelessWidget {
  final Color color;
  const _Ornament({required this.color});

  @override
  Widget build(BuildContext context) {
    Widget line(bool leftSide) => Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: leftSide ? Alignment.centerLeft : Alignment.centerRight,
                end: leftSide ? Alignment.centerRight : Alignment.centerLeft,
                colors: [color.withValues(alpha: 0), color],
              ),
            ),
          ),
        );
    final glyph = TextStyle(fontFamily: 'EBGaramond', color: color);
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Row(
          children: [
            line(true),
            Text(' ◆ ', style: glyph.copyWith(fontSize: 8)),
            Text('❦', style: glyph.copyWith(fontSize: 19)),
            Text(' ◆ ', style: glyph.copyWith(fontSize: 8)),
            line(false),
          ],
        ),
      ),
    );
  }
}
