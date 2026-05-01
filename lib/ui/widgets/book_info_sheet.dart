import 'dart:io';
import 'package:flutter/material.dart';

class BookInfoSheet extends StatelessWidget {
  final Map<String, dynamic> book;

  const BookInfoSheet({super.key, required this.book});

  @override
  Widget build(BuildContext context) {
    final coverPath = book['cover_path'] as String?;
    final title = book['title'] as String? ?? '';
    final author = book['author'] as String? ?? '';
    final language = book['language'] as String? ?? '';
    final rawDesc = book['description'] as String?;
    final description = rawDesc != null
        ? rawDesc.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll(RegExp(r'\s+'), ' ').trim()
        : null;
    final publisher = book['publisher'] as String?;
    final publishedDate = book['published_date'] as String?;
    final subject = book['subject'] as String?;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurfaceVariant
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    // Cover + title/author block
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LargeCover(coverPath: coverPath),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                author,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              _LangChip(language: language),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    // Metadata fields
                    if (publisher != null && publisher.isNotEmpty)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.business_outlined),
                        title: const Text('Editorial'),
                        subtitle: Text(publisher),
                      ),
                    if (publishedDate != null && publishedDate.isNotEmpty)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: const Text('Fecha de publicación'),
                        subtitle: Text(publishedDate),
                      ),
                    if (subject != null && subject.isNotEmpty)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.label_outline),
                        title: const Text('Tema'),
                        subtitle: Text(subject),
                      ),
                    if (description != null && description.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Descripción',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LargeCover extends StatelessWidget {
  final String? coverPath;
  const _LargeCover({this.coverPath});

  @override
  Widget build(BuildContext context) {
    const width = 120.0;
    const height = 180.0;

    if (coverPath != null && File(coverPath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
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
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.menu_book,
        size: 56,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String language;
  const _LangChip({required this.language});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: language == 'es'
            ? Theme.of(context).colorScheme.primaryContainer
            : Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        language.toUpperCase(),
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
