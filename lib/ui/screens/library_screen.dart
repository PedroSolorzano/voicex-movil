import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/app_info_provider.dart';
import '../providers/library_provider.dart';
import '../widgets/book_card.dart';
import '../widgets/book_info_sheet.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _searching = false;
  final _searchController = TextEditingController();

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
    final entriesAsync = ref.watch(libraryEntriesProvider);
    final version = ref.watch(appInfoProvider).valueOrNull?.version;
    final sort = ref.watch(librarySortProvider);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar por título o autor…',
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
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.5),
                        ),
                  ),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Agregar EPUB'),
        onPressed: () => _pickEpub(context),
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            final searching =
                ref.read(librarySearchProvider).trim().isNotEmpty;
            return searching
                ? const Center(child: Text('Ningún libro coincide'))
                : _EmptyState(onAdd: () => _pickEpub(context));
          }
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final entry = entries[i];
              final book = entry.book;
              final id = book['id'] as int;
              return BookCard(
                book: book,
                progress: entry.progress,
                onRead: () => _openBook(context, book),
                onDelete: () => _confirmDelete(context, id),
                onInfo: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => BookInfoSheet(book: book),
                ),
                onLanguageToggle: (lang) =>
                    ref.read(libraryProvider.notifier).updateLanguage(id, lang),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _pickEpub(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'],
    );
    if (result == null || result.files.single.path == null) return;
    try {
      await ref
          .read(libraryProvider.notifier)
          .addBook(result.files.single.path!);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al agregar: $e')));
      }
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
      context.push('/reader/${book['id']}', extra: filePath);
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
