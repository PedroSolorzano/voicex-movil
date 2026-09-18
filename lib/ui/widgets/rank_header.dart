import 'package:flutter/material.dart';

import '../providers/reading_stats_provider.dart';
import 'library_skin.dart';

/// The reader's rank, above the book list. Tapping it opens the progress
/// screen.
///
/// On the modern skin a plain card. On the classic one a bookplate — paper,
/// a gold rule, the title in Cinzel — because a Material card on parchment
/// breaks the look the same way the three icons did. On the catalogue skin,
/// the typed label in the brass holder of a drawer front: the list below is
/// what is inside that drawer.
class RankHeader extends StatelessWidget {
  final ReadingStats stats;
  final LibrarySkin skin;
  final VoidCallback onTap;

  const RankHeader({
    super.key,
    required this.stats,
    required this.skin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = stats.finished.length;
    final details = [
      '${formatPages(stats.pages)} páginas',
      if (books > 0) '$books ${books == 1 ? 'libro' : 'libros'}',
    ].join('  ·  ');
    final next = 'Faltan ${formatPages(stats.pagesToNext)} para '
        '${stats.nextTitle}';

    final body = Column(
      crossAxisAlignment: skin.isModern
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          '${stats.title}  ·  Nivel ${stats.level}',
          style: skin.isModern
              ? theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)
              : skinTitleStyle(17, skin.ink!),
          textAlign: skin.isModern ? TextAlign.start : TextAlign.center,
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: stats.progressToNext,
            minHeight: skin.isModern ? 6 : 3,
          ),
        ),
        const SizedBox(height: 6),
        Text(details, style: theme.textTheme.bodySmall),
        Text(next, style: theme.textTheme.bodySmall),
      ],
    );

    final semantics = '${stats.title}, nivel ${stats.level}. $details. $next.';

    if (skin.name == 'catalog') {
      return Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: _DrawerLabel(
          skin: skin,
          onTap: onTap,
          child: Column(
            children: [
              Text(
                '${stats.title}  ·  Nivel ${stats.level}',
                textAlign: TextAlign.center,
                style: typewriterStyle(16, skin.ink!).copyWith(
                  shadows: [
                    Shadow(color: skin.ink!, offset: const Offset(0.45, 0)),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                  value: stats.progressToNext, minHeight: 2.5),
              const SizedBox(height: 6),
              Text(details, style: typewriterStyle(12.5, skin.inkMuted!)),
              Text(next, style: typewriterStyle(12.5, skin.inkMuted!)),
            ],
          ),
        ),
      );
    }

    if (skin.isModern) {
      return Semantics(
        button: true,
        label: semantics,
        excludeSemantics: true,
        child: Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  Icon(Icons.workspace_premium_outlined,
                      size: 32, color: theme.colorScheme.primary),
                  const SizedBox(width: 14),
                  Expanded(child: body),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: skin.paper,
            border: Border.all(color: const Color(0xFFB08A45), width: 1.5),
            borderRadius: BorderRadius.circular(2),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              child: Container(
                // The inner rule of a bookplate.
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: const Color(0xFFB08A45).withValues(alpha: 0.5)),
                ),
                child: body,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The label holder on the front of a catalogue drawer: a brass frame held by
/// two screws, and a typed slip of card inside it.
class _DrawerLabel extends StatelessWidget {
  final LibrarySkin skin;
  final VoidCallback onTap;
  final Widget child;

  const _DrawerLabel({
    required this.skin,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFD9BC6E),
              Color(0xFF9A7530),
              Color(0xFFE6CE8A),
              Color(0xFF7E5E22),
            ],
            stops: [0, 0.4, 0.62, 1],
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x8C000000), blurRadius: 5, offset: Offset(0, 3)),
          ],
        ),
        child: Row(
          children: [
            const _Screw(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: skin.paper,
                    borderRadius: BorderRadius.circular(1),
                    // The slip sits behind the frame, in its shadow.
                    border: Border.all(
                        color: const Color(0x66000000), width: 0.8),
                    image: const DecorationImage(
                      image: AssetImage('assets/skins/parchment.png'),
                      repeat: ImageRepeat.repeat,
                      opacity: 0.45,
                    ),
                  ),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: onTap,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const _Screw(),
          ],
        ),
      ),
    );
  }
}

class _Screw extends StatelessWidget {
  const _Screw();

  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 24,
        child: Center(
          child: CustomPaint(size: Size(10, 10), painter: _ScrewHead()),
        ),
      );
}

class _ScrewHead extends CustomPainter {
  const _ScrewHead();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    canvas.drawCircle(
        c.translate(0, 0.8), r, Paint()..color = const Color(0x66000000));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.5),
          colors: [Color(0xFFF1DFA3), Color(0xFF8A6A28)],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );
    // The slot, never quite horizontal.
    canvas.drawLine(
      c + Offset(-r * 0.72, -r * 0.3),
      c + Offset(r * 0.72, r * 0.3),
      Paint()
        ..color = const Color(0xCC3A2810)
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_ScrewHead old) => false;
}
