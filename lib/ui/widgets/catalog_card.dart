import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'classic_card_parts.dart';
import 'library_skin.dart';

/// A card out of a library's card catalogue: the "Fichas" skin.
///
/// Everything that makes one recognisable, and nothing else: typed text
/// sitting on the ruling, the heading above the red rule, the call number in
/// the corner, the hole for the drawer's rod, a rubber stamp for the reading
/// status, paper that has yellowed at the edges, and cards filed by hand —
/// none of them quite straight. The book's own cover is clipped on like a
/// photograph.
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

  /// Distance between ruled lines. Every typed line is this tall, which is
  /// what keeps the text on the ruling.
  static const pitch = 22.0;

  static const _topMargin = 10.0;

  @override
  Widget build(BuildContext context) {
    const skin = LibrarySkin.catalog;
    final title = book['title'] as String? ?? 'Sin título';
    final author = book['author'] as String? ?? 'Desconocido';
    final language = book['language'] as String? ?? 'es';
    // The imprint line exists for the publisher. The year alone is already in
    // the call number, and some EPUBs carry a year *as* the publisher: both
    // cases typed "2011." or "2021, 2021." on the card.
    final publisher = (book['publisher'] as String?)?.trim() ?? '';
    final imprint = publisher.isEmpty || RegExp(r'^\d+$').hasMatch(publisher)
        ? ''
        : [publisher, ?yearOf(book['published_date'] as String?)].join(', ');

    // Filed by hand: each card a hair off level, always the same hair.
    final seed = (book['id'] as int?) ?? title.hashCode;
    final tilt = ((seed * 37) % 9 - 4) * 0.0016;

    final ink = skin.ink!;
    final muted = skin.inkMuted!;
    const strut = StrutStyle(
        fontFamily: 'SpecialElite',
        fontSize: 15,
        height: pitch / 15,
        forceStrutHeight: true);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Transform.rotate(
        angle: tilt,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // The next card in the drawer, showing behind this one.
            Positioned.fill(
              child: Transform.translate(
                offset: const Offset(3, 3),
                child: Transform.rotate(
                  angle: -tilt * 3 + 0.004,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFE4D5B3),
                      borderRadius: BorderRadius.all(Radius.circular(3)),
                      boxShadow: [
                        BoxShadow(
                            color: Color(0x73000000),
                            blurRadius: 5,
                            offset: Offset(0, 3)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: skin.paper,
                borderRadius: BorderRadius.circular(3),
                image: const DecorationImage(
                  image: AssetImage('assets/skins/parchment.png'),
                  repeat: ImageRepeat.repeat,
                  opacity: 0.45,
                ),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x59000000),
                      blurRadius: 3,
                      offset: Offset(0, 1)),
                ],
              ),
              child: CustomPaint(
                painter: _CardStock(seed: seed),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: onRead,
                    child: Padding(
                      padding:
                          const EdgeInsets.fromLTRB(12, _topMargin, 10, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Call number, in its corner.
                              SizedBox(
                                width: 46,
                                child: Text(
                                  callNumber(book).join('\n'),
                                  strutStyle: strut,
                                  style: typewriterStyle(12.5, muted,
                                      pitch: pitch),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    // The heading, above the red rule.
                                    Text(
                                      author,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      strutStyle: strut,
                                      style: typewriterStyle(14, ink,
                                          pitch: pitch),
                                    ),
                                    // Second indention, struck twice: how a
                                    // typist made a title stand out.
                                    Padding(
                                      padding: const EdgeInsets.only(left: 14),
                                      child: Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        strutStyle: strut,
                                        style: typewriterStyle(16, ink,
                                                pitch: pitch)
                                            .copyWith(shadows: [
                                          Shadow(
                                              color: ink,
                                              offset: const Offset(0.45, 0)),
                                        ]),
                                      ),
                                    ),
                                    if (imprint.isNotEmpty)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(left: 14),
                                        child: Text(
                                          '$imprint.',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          strutStyle: strut,
                                          style: typewriterStyle(12.5, muted,
                                              pitch: pitch),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Padding(
                                padding: const EdgeInsets.only(top: 5),
                                child: _ClippedCover(
                                  coverPath: book['cover_path'] as String?,
                                  title: title,
                                  tilt: -tilt * 6 + 0.02,
                                ),
                              ),
                            ],
                          ),
                          // Below the text: menu, the rod hole (painted), stamp.
                          SizedBox(
                            height: 30,
                            child: Row(
                              children: [
                                SkinActionsMenu(
                                  language: language,
                                  onInfo: onInfo,
                                  onLanguageToggle: onLanguageToggle,
                                  onDelete: onDelete,
                                ),
                                const Spacer(),
                                _Stamp.of(book, progress),
                                const SizedBox(width: 4),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The status, rubber-stamped a little crooked.
///
/// It replaces the small grey "Sin empezar" of the first version of this
/// card, which nobody could find: a stamp is the loudest thing on a catalogue
/// card, and the only colour.
class _Stamp extends StatelessWidget {
  final String text;
  final Color ink;
  const _Stamp(this.text, this.ink);

  /// Inks dark enough to be read as text on the card (WCAG AA, measured in
  /// test/library_skin_test.dart).
  static const red = Color(0xFF9C2A1F);
  static const blue = Color(0xFF27407A);
  static const green = Color(0xFF2B5A36);

  static String labelFor(Map<String, dynamic> book, double progress) {
    if (book['finished_at'] != null || progress >= 0.995) return 'LEÍDO';
    if (progress > 0.001) {
      return 'EN LECTURA · ${(progress * 100).toStringAsFixed(0)} %';
    }
    return 'SIN EMPEZAR';
  }

  factory _Stamp.of(Map<String, dynamic> book, double progress) {
    final label = labelFor(book, progress);
    return _Stamp(
      label,
      switch (label) {
        'LEÍDO' => green,
        'SIN EMPEZAR' => red,
        _ => blue,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.045,
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          border: Border.all(color: ink, width: 1.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: ink.withValues(alpha: 0.7), width: 0.6),
            borderRadius: BorderRadius.circular(2.5),
          ),
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontFamily: 'Roboto',
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              height: 1.2,
              color: ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Visible for the contrast test.
@visibleForTesting
const catalogStampInks = [_Stamp.red, _Stamp.blue, _Stamp.green];

/// What the stamp on [book]'s card says.
@visibleForTesting
String catalogStampLabel(Map<String, dynamic> book, double progress) =>
    _Stamp.labelFor(book, progress);

/// The book's own cover as a small photographic print, held to the card with
/// a paper clip. Without a cover, a blank print with the title typed on it.
class _ClippedCover extends StatelessWidget {
  final String? coverPath;
  final String title;
  final double tilt;

  const _ClippedCover({
    required this.coverPath,
    required this.title,
    required this.tilt,
  });

  static const _width = 56.0;
  static const _height = 80.0;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: _width,
            height: _height,
            padding: const EdgeInsets.all(2.5),
            decoration: const BoxDecoration(
              color: Color(0xFFFBF6E9),
              boxShadow: [
                BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 3,
                    offset: Offset(1, 2)),
              ],
            ),
            // No existsSync(): this runs while the list scrolls, and
            // errorBuilder already covers a file that went missing.
            child: coverPath == null
                ? _blank()
                : Image.file(
                    File(coverPath!),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    errorBuilder: (_, _, _) => _blank(),
                  ),
          ),
          // Over the top edge of both the print and the card.
          const Positioned(
            top: -13,
            left: 10,
            child: CustomPaint(size: Size(11, 32), painter: _PaperClip()),
          ),
        ],
      ),
    );
  }

  Widget _blank() => ColoredBox(
        color: const Color(0xFFEDE3CB),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: typewriterStyle(8, LibrarySkin.catalog.ink!),
            ),
          ),
        ),
      );
}

class _PaperClip extends CustomPainter {
  const _PaperClip();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // One wire, bent three times: down the outside, up the middle.
    final wire = Path()
      ..moveTo(w * 0.78, h * 0.30)
      ..lineTo(w * 0.78, h * 0.86)
      ..arcToPoint(Offset(w * 0.22, h * 0.86),
          radius: Radius.circular(w * 0.28))
      ..lineTo(w * 0.22, h * 0.12)
      ..arcToPoint(Offset(w, h * 0.12), radius: Radius.circular(w * 0.39))
      ..lineTo(w, h * 0.90)
      ..arcToPoint(Offset(0, h * 0.90), radius: Radius.circular(w * 0.5))
      ..lineTo(0, h * 0.22);

    canvas.drawPath(
      wire.shift(const Offset(0.6, 0.9)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0x55000000),
    );
    canvas.drawPath(
      wire,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [Color(0xFFDADDE2), Color(0xFF7F848C), Color(0xFFC4C8CE)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_PaperClip old) => false;
}

/// The card itself: ruling, the hole for the rod, and sixty years in a
/// drawer. Everything is drawn from [seed], so a card ages the same way every
/// time it scrolls back into view.
class _CardStock extends CustomPainter {
  final int seed;
  _CardStock({required this.seed});

  static const _red = Color(0x8CB03A2E);
  static const _blue = Color(0x4D5B7FA6);
  static const _age = Color(0xFF8A5A2B);

  @override
  void paint(Canvas canvas, Size size) {
    // A foxing spot on the edge must not spill onto the wood.
    canvas.clipRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)));

    // Yellowed at the edges, where hands and air got to it.
    void edge(Alignment from, Alignment to, Rect r) => canvas.drawRect(
          r,
          Paint()
            ..shader = LinearGradient(
              begin: from,
              end: to,
              colors: [_age.withValues(alpha: 0.16), _age.withValues(alpha: 0)],
            ).createShader(r),
        );
    const d = 16.0;
    edge(Alignment.topCenter, Alignment.bottomCenter,
        Rect.fromLTWH(0, 0, size.width, d));
    edge(Alignment.bottomCenter, Alignment.topCenter,
        Rect.fromLTWH(0, size.height - d, size.width, d));
    edge(Alignment.centerLeft, Alignment.centerRight,
        Rect.fromLTWH(0, 0, d, size.height));
    edge(Alignment.centerRight, Alignment.centerLeft,
        Rect.fromLTWH(size.width - d, 0, d, size.height));

    // Foxing.
    final random = math.Random(seed);
    for (var i = 0; i < 6; i++) {
      final at = Offset(random.nextDouble() * size.width,
          random.nextDouble() * size.height);
      final r = 1.5 + random.nextDouble() * 4;
      final spot = Paint()..color = _age.withValues(alpha: 0.07);
      canvas.drawCircle(at, r, spot);
      canvas.drawCircle(at, r * 0.5, spot);
    }

    // Ruling: the heading line in red, the rest in blue, one pitch apart.
    // The offset puts each rule just under the baseline of its typed line.
    const first = CatalogCard._topMargin + CatalogCard.pitch - 3;
    canvas.drawLine(
      const Offset(0, first),
      Offset(size.width, first),
      Paint()
        ..color = _red
        ..strokeWidth = 1.1,
    );
    final blue = Paint()
      ..color = _blue
      ..strokeWidth = 0.8;
    for (var y = first + CatalogCard.pitch;
        y < size.height - 26;
        y += CatalogCard.pitch) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), blue);
    }

    // The hole the drawer's rod goes through, and the wood behind it.
    final hole = Offset(size.width / 2, size.height - 14);
    canvas.drawCircle(hole, 7, Paint()..color = const Color(0xFF24150B));
    canvas.drawCircle(
      hole.translate(0, 0.8),
      7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0x40000000),
    );
    canvas.drawArc(
      Rect.fromCircle(center: hole, radius: 6.4),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0x33FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_CardStock old) => old.seed != seed;
}
