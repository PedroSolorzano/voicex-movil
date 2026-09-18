import 'package:flutter/material.dart';

import '../providers/reading_stats_provider.dart';
import 'library_skin.dart';

/// The reader's rank, above the book list. Tapping it opens the progress
/// screen.
///
/// On the modern skin a plain card; on the classic ones a bookplate — paper,
/// a gold rule, the title in Cinzel — because a Material card on parchment
/// breaks the look the same way the three icons did.
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
