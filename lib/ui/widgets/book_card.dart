import 'dart:io';
import 'package:flutter/material.dart';

class BookCard extends StatelessWidget {
  final Map<String, dynamic> book;

  /// 0.0–1.0 through the book, from the stored absolute paragraph position.
  final double progress;
  final VoidCallback onRead;
  final VoidCallback onDelete;
  final VoidCallback onInfo;
  final ValueChanged<String> onLanguageToggle;

  const BookCard({
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
    final title = book['title'] as String? ?? 'Sin título';
    final author = book['author'] as String? ?? 'Desconocido';
    final language = book['language'] as String? ?? 'es';
    final started = progress > 0.001;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onRead,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CoverThumbnail(coverPath: book['cover_path'] as String?),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      author,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    if (started) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(progress * 100).toStringAsFixed(0)}% leído',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ] else
                      Text(
                        'Sin empezar',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _LangBadge(
                          language: language,
                          onToggle: () =>
                              onLanguageToggle(language == 'es' ? 'en' : 'es'),
                        ),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.info_outline),
                          tooltip: 'Detalles del libro',
                          onPressed: onInfo,
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Eliminar libro',
                          onPressed: onDelete,
                        ),
                        IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          icon: Icon(started
                              ? Icons.play_arrow
                              : Icons.play_circle_outline),
                          tooltip: started ? 'Continuar' : 'Empezar a leer',
                          onPressed: onRead,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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

    // No existsSync() here: this runs on every frame of a scrolling list, and
    // errorBuilder already covers a missing file.
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
      child: Icon(Icons.menu_book_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

class _LangBadge extends StatelessWidget {
  final String language;
  final VoidCallback onToggle;
  const _LangBadge({required this.language, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final label = language.toUpperCase();
    return Semantics(
      button: true,
      label: 'Idioma del libro: $label. Tocar para cambiar.',
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          // 48dp minimum touch target.
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
