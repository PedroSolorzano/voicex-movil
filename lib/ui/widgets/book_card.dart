import 'dart:io';
import 'package:flutter/material.dart';

class BookCard extends StatelessWidget {
  final Map<String, dynamic> book;
  final VoidCallback onRead;
  final VoidCallback onDelete;
  final VoidCallback onInfo;
  final ValueChanged<String> onLanguageToggle;

  const BookCard({
    super.key,
    required this.book,
    required this.onRead,
    required this.onDelete,
    required this.onInfo,
    required this.onLanguageToggle,
  });

  @override
  Widget build(BuildContext context) {
    final lang = book['language'] as String? ?? 'es';
    final coverPath = book['cover_path'] as String?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Cover image or placeholder
            _CoverThumbnail(coverPath: coverPath),
            const SizedBox(width: 12),
            // Title, author, badges, action buttons
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book['title'] as String? ?? '',
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book['author'] as String? ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _LangBadge(lang: lang, onToggle: onLanguageToggle),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: 28,
                        width: 28,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.info_outline, size: 20),
                          tooltip: 'Información',
                          onPressed: onInfo,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.play_circle_filled),
                        tooltip: 'Leer',
                        onPressed: onRead,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Eliminar',
                        onPressed: onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CoverThumbnail extends StatelessWidget {
  final String? coverPath;
  const _CoverThumbnail({this.coverPath});

  @override
  Widget build(BuildContext context) {
    const width = 70.0;
    const height = 100.0;

    if (coverPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(coverPath!),
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => _placeholder(ctx, width, height),
        ),
      );
    }
    return _placeholder(context, width, height);
  }

  Widget _placeholder(BuildContext context, double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.menu_book,
        size: 36,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _LangBadge extends StatelessWidget {
  final String lang;
  final ValueChanged<String> onToggle;
  const _LangBadge({required this.lang, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onToggle(lang == 'es' ? 'en' : 'es'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: lang == 'es'
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          lang.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
    );
  }
}
