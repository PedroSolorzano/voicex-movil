import 'dart:io';
import 'package:flutter/material.dart';
import 'library_skin.dart';

/// EPUB descriptions are HTML more often than not; the cards and the details
/// sheet show them as plain prose.
String? plainDescription(String? raw) {
  final text = raw
      ?.replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// The year out of whatever an EPUB put in `dc:date` — "1925", "2015-03-01",
/// "March 1851". Null when there is no four-digit run in it.
String? yearOf(String? publishedDate) =>
    publishedDate == null ? null : RegExp(r'\d{4}').firstMatch(publishedDate)?[0];

/// What the classic skins show under the title: language, year and progress,
/// in the place a real catalogue card carries its call number.
String catalogLine(Map<String, dynamic> book, double progress) {
  final parts = <String>[
    (book['language'] as String? ?? 'es').toUpperCase(),
    ?yearOf(book['published_date'] as String?),
    progress > 0.001
        ? '${(progress * 100).toStringAsFixed(0)} % leído'
        : 'Sin empezar',
  ];
  return parts.join('  ·  ');
}

/// The real cover, bound: dark leather edge, a gold fillet, a short shadow.
///
/// The mockups draw a generic leather tome; the requirement is that the book's
/// own cover is always visible, so it goes inside the binding instead of being
/// replaced by it. Without a cover, the binding carries the title the way a
/// spine would.
class FramedCover extends StatelessWidget {
  final String? coverPath;
  final String title;
  final double width;
  final double height;

  const FramedCover({
    super.key,
    required this.coverPath,
    required this.title,
    required this.width,
    required this.height,
  });

  static const _leather = Color(0xFF4A2A18);
  static const _gold = Color(0xFFC9A45C);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _leather,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 4, offset: Offset(1, 2)),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: _gold, width: 1),
        ),
        // No existsSync(): this runs while the list scrolls, and errorBuilder
        // already covers a file that went missing.
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
