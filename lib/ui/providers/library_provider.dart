import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../epub/parser.dart';
import '../../storage/repositories.dart';

final _libraryRepo = LibraryRepo();

class LibraryNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() => _libraryRepo.all();

  Future<void> addBook(String filePath) async {
    final book = await parseEpub(filePath);
    final id = await _libraryRepo.add(
      title: book.title,
      author: book.author,
      language: book.language,
      filePath: filePath,
    );

    // Extract cover image and extra metadata asynchronously after insert.
    try {
      final extras = await extractEpubExtras(filePath);
      String? savedCoverPath;
      if (extras.coverBytes != null) {
        final appDocDir = await getApplicationDocumentsDirectory();
        final coversDir =
            Directory('${appDocDir.path}/voicex_covers');
        if (!await coversDir.exists()) {
          await coversDir.create(recursive: true);
        }
        final coverFile = File(
            '${coversDir.path}/book_${id}_cover.${extras.coverExt}');
        await coverFile.writeAsBytes(extras.coverBytes!);
        savedCoverPath = coverFile.path;
      }
      await _libraryRepo.updateMeta(
        id,
        coverPath: savedCoverPath,
        description: extras.description,
        publisher: extras.publisher,
        publishedDate: extras.publishedDate,
        subject: extras.subject,
      );
    } catch (_) {
      // Extras extraction is non-critical; ignore failures.
    }

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
