import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../epub/parser.dart';
import '../../storage/repositories.dart';

final _libraryRepo = LibraryRepo();

class LibraryNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() => _libraryRepo.all();

  Future<void> addBook(String filePath) async {
    final book = await parseEpub(filePath);
    await _libraryRepo.add(
      title: book.title,
      author: book.author,
      language: book.language,
      filePath: filePath,
    );
    ref.invalidateSelf();
  }

  Future<void> deleteBook(int id) async {
    await _libraryRepo.delete(id);
    ref.invalidateSelf();
  }

  Future<void> updateLanguage(int id, String language) async {
    await _libraryRepo.updateLanguage(id, language);
    ref.invalidateSelf();
  }

  Future<void> relocateBook(int id, String newPath) async {
    await _libraryRepo.updateFilePath(id, newPath);
    ref.invalidateSelf();
  }
}

final libraryProvider =
    AsyncNotifierProvider<LibraryNotifier, List<Map<String, dynamic>>>(
        LibraryNotifier.new);
