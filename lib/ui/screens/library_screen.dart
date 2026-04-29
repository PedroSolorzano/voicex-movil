import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/library_provider.dart';
import '../widgets/book_card.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(libraryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('VoiceX')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Agregar EPUB'),
        onPressed: () => _pickEpub(context, ref),
      ),
      body: booksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (books) => books.isEmpty
            ? _EmptyState(onAdd: () => _pickEpub(context, ref))
            : ListView.builder(
                itemCount: books.length,
                itemBuilder: (context, i) {
                  final book = books[i];
                  final id = book['id'] as int;
                  return BookCard(
                    book: book,
                    onRead: () => _openBook(context, ref, book),
                    onDelete: () => _confirmDelete(context, ref, id),
                    onLanguageToggle: (lang) =>
                        ref.read(libraryProvider.notifier).updateLanguage(id, lang),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _pickEpub(BuildContext context, WidgetRef ref) async {
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
      BuildContext context, WidgetRef ref, Map<String, dynamic> book) async {
    final filePath = book['file_path'] as String;
    if (!File(filePath).existsSync()) {
      if (context.mounted) _showRelocateDialog(context, ref, book);
      return;
    }
    if (context.mounted) {
      context.push('/reader/${book['id']}', extra: filePath);
    }
  }

  Future<void> _showRelocateDialog(
      BuildContext context, WidgetRef ref, Map<String, dynamic> book) async {
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

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, int id) async {
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.menu_book_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Tu biblioteca está vacía',
              style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          const Text('Toca el botón para agregar un EPUB',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Agregar EPUB'),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
