import 'dart:developer' as dev;
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../errors.dart';
import '../providers/app_info_provider.dart';
import '../providers/library_provider.dart';
import '../providers/reading_stats_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/share_import_provider.dart';
import '../widgets/book_card.dart';
import '../widgets/book_info_sheet.dart';
import '../widgets/catalog_card.dart';
import '../widgets/classic_shelf_card.dart';
import '../widgets/library_skin.dart';
import '../widgets/rank_header.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _searching = false;

  /// Descomprimir una novela lleva segundos, y hasta ahora no se veía nada
  /// mientras tanto: la reacción natural era volver a pulsar "Agregar".
  bool _importing = false;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Picks up an EPUB opened from a file manager or shared into the app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(shareImportProvider.notifier).start();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    setState(() => _searching = false);
    _searchController.clear();
    ref.read(librarySearchProvider.notifier).state = '';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(shareImportProvider, (_, message) {
      if (message == null) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      ref.read(shareImportProvider.notifier).clearMessage();
    });

    final skin = LibrarySkin.of(
        ref.watch(settingsProvider).valueOrNull?.librarySkin ?? 'modern');

    // The Builder shadows `context` on purpose. Dialogs and sheets take their
    // theme from the context they are handed, and the one `build` receives is
    // above this Theme: without the shadowing, "Eliminar libro" and the book
    // details would open dark over parchment when the phone is in dark mode —
    // the same bug `_themed` in reader_screen.dart had.
    return Theme(
      data: libraryThemeData(skin, Theme.of(context)),
      child: Builder(builder: (context) => _buildScaffold(context, skin)),
    );
  }

  Widget _buildScaffold(BuildContext context, LibrarySkin skin) {
    final entriesAsync = ref.watch(libraryEntriesProvider);
    final version = ref.watch(appInfoProvider).valueOrNull?.version;
    final sort = ref.watch(librarySortProvider);
    // Null on the modern skin, which keeps the app's own colours.
    final barInk = Theme.of(context).appBarTheme.foregroundColor;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: skin.barTexture == null ? null : _WoodBar(skin: skin),
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                // On wood the default text colour is the page's dark ink.
                style: barInk == null ? null : TextStyle(color: barInk),
                cursorColor: barInk,
                decoration: InputDecoration(
                  hintText: 'Buscar por título o autor…',
                  hintStyle: barInk == null
                      ? null
                      : TextStyle(color: barInk.withValues(alpha: 0.7)),
                  border: InputBorder.none,
                ),
                onChanged: (v) =>
                    ref.read(librarySearchProvider.notifier).state = v,
              )
            : const Text('VoiceX'),
        actions: [
          if (_searching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cerrar búsqueda',
              onPressed: _closeSearch,
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Buscar',
              onPressed: () => setState(() => _searching = true),
            ),
            PopupMenuButton<LibrarySort>(
              icon: const Icon(Icons.sort),
              tooltip: 'Ordenar',
              initialValue: sort,
              onSelected: (v) =>
                  ref.read(librarySortProvider.notifier).state = v,
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: LibrarySort.recent, child: Text('Añadidos recientes')),
                PopupMenuItem(
                    value: LibrarySort.progress, child: Text('En curso primero')),
                PopupMenuItem(value: LibrarySort.title, child: Text('Título')),
                PopupMenuItem(value: LibrarySort.author, child: Text('Autor')),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Ajustes',
              onPressed: () => context.push('/settings'),
            ),
          ],
        ],
        bottom: version == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(18),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'v$version',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: (barInk ??
                                  Theme.of(context).colorScheme.onSurface)
                              .withValues(alpha: 0.5),
                        ),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: _importing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add),
        label: Text(_importing ? 'Agregando…' : 'Agregar EPUB'),
        onPressed: _importing ? null : () => _pickEpub(context),
      ),
      body: _SkinBackground(
        skin: skin,
        child: entriesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _OnPaper(
              skin: skin, child: Center(child: Text(friendlyError(e)))),
          data: (entries) {
            if (entries.isEmpty) {
              final searching =
                  ref.read(librarySearchProvider).trim().isNotEmpty;
              return _OnPaper(
                skin: skin,
                child: searching
                    ? const Center(child: Text('Ningún libro coincide'))
                    : _EmptyState(onAdd: () => _pickEpub(context)),
              );
            }
            // The rank sits above the list, but not over search results:
            // there it would push the matches down for nothing.
            final stats = ref.watch(readingStatsProvider).valueOrNull;
            final header = stats != null &&
                ref.watch(librarySearchProvider).trim().isEmpty;
            final offset = header ? 1 : 0;

            return ListView.builder(
              // Room for the FAB over the last entry.
              padding: skin.isModern
                  ? null
                  : const EdgeInsets.only(top: 6, bottom: 88),
              itemCount: entries.length + offset,
              itemBuilder: (context, index) {
                if (header && index == 0) {
                  return RankHeader(
                    stats: stats,
                    skin: skin,
                    onTap: () => context.push('/progress'),
                  );
                }
                final i = index - offset;
                final entry = entries[i];
                final book = entry.book;
                final id = book['id'] as int;
                void onRead() => _openBook(context, book);
                void onDelete() => _confirmDelete(context, id);
                void onInfo() => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => BookInfoSheet(book: book),
                    );
                void onLanguageToggle(String lang) =>
                    ref.read(libraryProvider.notifier).updateLanguage(id, lang);

                return switch (skin.name) {
                  'catalog' => CatalogCard(
                      book: book,
                      progress: entry.progress,
                      onRead: onRead,
                      onDelete: onDelete,
                      onInfo: onInfo,
                      onLanguageToggle: onLanguageToggle,
                    ),
                  'classic' => ClassicShelfCard(
                      book: book,
                      progress: entry.progress,
                      isLast: i == entries.length - 1,
                      onRead: onRead,
                      onDelete: onDelete,
                      onInfo: onInfo,
                      onLanguageToggle: onLanguageToggle,
                    ),
                  _ => BookCard(
                      book: book,
                      progress: entry.progress,
                      onRead: onRead,
                      onDelete: onDelete,
                      onInfo: onInfo,
                      onLanguageToggle: onLanguageToggle,
                    ),
                };
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickEpub(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() => _importing = true);
    try {
      await ref
          .read(libraryProvider.notifier)
          .addBook(result.files.single.path!);
    } catch (e) {
      dev.log('[Library] import failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openBook(
      BuildContext context, Map<String, dynamic> book) async {
    final filePath = book['file_path'] as String;
    if (!File(filePath).existsSync()) {
      if (context.mounted) _showRelocateDialog(context, book);
      return;
    }
    if (context.mounted) {
      await context.push('/reader/${book['id']}', extra: filePath);
      // Back from the book: the rank has to show what was just read.
      ref.invalidate(readingStatsProvider);
    }
  }

  Future<void> _showRelocateDialog(
      BuildContext context, Map<String, dynamic> book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archivo no encontrado'),
        content: const Text(
            'El archivo EPUB fue movido o eliminado. ¿Deseas localizarlo?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Localizar')),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );
    if (result?.files.single.path == null) return;
    await ref
        .read(libraryProvider.notifier)
        .relocateBook(book['id'] as int, result!.files.single.path!);
  }

  Future<void> _confirmDelete(BuildContext context, int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar libro'),
        content: const Text('¿Seguro? Se borrará el progreso y marcadores.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(libraryProvider.notifier).deleteBook(id);
    }
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined, size: 64, color: muted),
          const SizedBox(height: 16),
          const Text('Tu biblioteca está vacía',
              style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          Text('Toca el botón para agregar un EPUB',
              style: TextStyle(color: muted)),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Agregar EPUB'),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

/// Paints the skin's background under the list. A repeated tile and no blur:
/// it costs nothing per frame while scrolling.
class _SkinBackground extends StatelessWidget {
  final LibrarySkin skin;
  final Widget child;
  const _SkinBackground({required this.skin, required this.child});

  @override
  Widget build(BuildContext context) {
    final texture = skin.backgroundTexture;
    if (texture == null) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: skin.background,
        image: DecorationImage(
          image: AssetImage(texture),
          repeat: ImageRepeat.repeat,
        ),
      ),
      child: child,
    );
  }
}

/// On the catalog skin the background is wood, and the empty-state and error
/// texts are the page's dark ink: they get a sheet of paper to sit on.
class _OnPaper extends StatelessWidget {
  final LibrarySkin skin;
  final Widget child;
  const _OnPaper({required this.skin, required this.child});

  @override
  Widget build(BuildContext context) {
    if (skin.name != 'catalog') return child;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        decoration: BoxDecoration(
          color: skin.paper,
          borderRadius: BorderRadius.circular(2),
        ),
        child: child,
      ),
    );
  }
}

/// Wood behind the app bar, with a gold rule along its lower edge.
class _WoodBar extends StatelessWidget {
  final LibrarySkin skin;
  const _WoodBar({required this.skin});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: skin.frame,
        image: DecorationImage(
          image: AssetImage(skin.barTexture!),
          repeat: ImageRepeat.repeat,
        ),
        border: const Border(
          bottom: BorderSide(color: Color(0xFFB08A45), width: 2),
        ),
      ),
    );
  }
}
