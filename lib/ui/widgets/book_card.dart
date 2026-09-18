import 'dart:io';
import 'package:flutter/material.dart';

/// A book on the modern skin: the card takes its colours from the book's own
/// cover.
///
/// Every card used to be the same grey whatever was on it. Now the tint
/// behind the cover, the glow under it, the progress bar and the play button
/// all come from a [ColorScheme] extracted from the cover image, the way music
/// apps tint a screen from the album art: a shelf of books looks like those
/// books. Until the colours arrive — and for a book with no cover — the card
/// wears the app's own scheme, so nothing jumps.
class BookCard extends StatefulWidget {
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

  /// What the chip on [book]'s card says.
  static String statusOf(Map<String, dynamic> book, double progress) {
    if (book['finished_at'] != null || progress >= 0.995) return 'LEÍDO';
    if (progress > 0.001) return '${(progress * 100).toStringAsFixed(0)} %';
    return 'NUEVO';
  }

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard> {
  /// Extracting a scheme decodes and quantizes the image: once per cover and
  /// brightness for the life of the process, not once per scroll.
  static final _schemes = <String, ColorScheme>{};

  ColorScheme? _ambient;
  String? _loadedKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAmbient();
  }

  @override
  void didUpdateWidget(BookCard old) {
    super.didUpdateWidget(old);
    _loadAmbient();
  }

  Future<void> _loadAmbient() async {
    final path = widget.book['cover_path'] as String?;
    final brightness = Theme.of(context).brightness;
    final key = path == null ? null : '$path|${brightness.name}';
    if (key == _loadedKey) return;
    _loadedKey = key;
    // No setState on these two: both callers are followed by a build.
    if (key == null) {
      _ambient = null;
      return;
    }
    final cached = _schemes[key];
    if (cached != null) {
      _ambient = cached;
      return;
    }
    try {
      final scheme = await ColorScheme.fromImageProvider(
        // The extractor works on a thumbnail anyway; no need to decode a
        // 1600 px cover to get there.
        provider: ResizeImage(FileImage(File(path!)), width: 96),
        brightness: brightness,
      );
      _schemes[key] = scheme;
      if (mounted && _loadedKey == key) setState(() => _ambient = scheme);
    } catch (_) {
      // A missing or undecodable cover: the app's colours, as before.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = widget.book;
    final title = book['title'] as String? ?? 'Sin título';
    final author = book['author'] as String? ?? 'Desconocido';
    final language = book['language'] as String? ?? 'es';
    final status = BookCard.statusOf(book, widget.progress);

    final ambient = _ambient ?? theme.colorScheme;
    final surface = theme.colorScheme.surfaceContainerLow;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              Color.alphaBlend(
                  ambient.primaryContainer.withValues(alpha: 0.85), surface),
              Color.alphaBlend(
                  ambient.primaryContainer.withValues(alpha: 0.18), surface),
            ],
            stops: const [0, 0.75],
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onRead,
            child: Stack(
              children: [
                _content(theme, ambient, title, author, language, status),
                Positioned(
                  top: 4,
                  right: 2,
                  child: _Menu(
                    onInfo: widget.onInfo,
                    onDelete: widget.onDelete,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(ThemeData theme, ColorScheme ambient, String title,
      String author, String language, String status) {
    final book = widget.book;
    final started = widget.progress > 0.001;
    final isNew = status == 'NUEVO';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Cover(
            coverPath: book['cover_path'] as String?,
            glow: ambient.primary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Room on the right for the menu, which floats
                // over the corner: in a row with the title, its 48 dp
                // pushed the author a line away.
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 40),
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.only(right: 40),
                  child: Text(
                    author,
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Chip(
                      label: status,
                      icon: status == 'LEÍDO' ? Icons.check : null,
                      // The unopened book is the one to notice: it
                      // used to say so in the smallest grey type on
                      // the card.
                      background: isNew
                          ? ambient.primary
                          : ambient.secondaryContainer,
                      foreground: isNew
                          ? ambient.onPrimary
                          : ambient.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                    _LangChip(
                      language: language,
                      scheme: ambient,
                      onToggle: () => widget.onLanguageToggle(
                          language == 'es' ? 'en' : 'es'),
                    ),
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: IconButton.filled(
                        style: IconButton.styleFrom(
                          backgroundColor: ambient.primary,
                          foregroundColor: ambient.onPrimary,
                          fixedSize: const Size(48, 48),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded,
                            size: 28),
                        tooltip:
                            started ? 'Continuar' : 'Empezar a leer',
                        onPressed: widget.onRead,
                      ),
                    ),
                  ],
                ),
                if (started && status != 'LEÍDO')
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: widget.progress,
                        minHeight: 6,
                        color: ambient.primary,
                        backgroundColor:
                            ambient.primary.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final String? coverPath;
  final Color glow;
  const _Cover({required this.coverPath, required this.glow});

  static const _width = 84.0;
  static const _height = 124.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      width: _width,
      height: _height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: glow.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        // No existsSync() here: this runs on every frame of a scrolling list,
        // and errorBuilder already covers a missing file.
        child: coverPath == null
            ? _placeholder(context)
            : Image.file(
                File(coverPath!),
                width: _width,
                height: _height,
                fit: BoxFit.cover,
                errorBuilder: (ctx, _, _) => _placeholder(ctx),
              ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.menu_book_outlined, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;

  const _Chip({
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: foreground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The book's language, and the switch for it: the voice is picked by it, so
/// it stays one tap away instead of going into the menu.
class _LangChip extends StatelessWidget {
  final String language;
  final ColorScheme scheme;
  final VoidCallback onToggle;

  const _LangChip({
    required this.language,
    required this.scheme,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final label = language.toUpperCase();
    return Semantics(
      button: true,
      label: 'Idioma del libro: $label. Tocar para cambiar.',
      excludeSemantics: true,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(20),
        child: ConstrainedBox(
          // 48dp minimum touch target.
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outline),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.translate, size: 12, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Details and delete, out of the way: on the card they were two of three
/// icons in a row, as loud as the one that opens the book.
class _Menu extends StatelessWidget {
  final VoidCallback onInfo;
  final VoidCallback onDelete;
  const _Menu({required this.onInfo, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Más',
      icon: Icon(Icons.more_vert,
          color: Theme.of(context).colorScheme.onSurfaceVariant),
      onSelected: (v) => v == 'info' ? onInfo() : onDelete(),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'info',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.info_outline),
            title: Text('Detalles'),
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.delete_outline),
            title: Text('Eliminar'),
          ),
        ),
      ],
    );
  }
}
