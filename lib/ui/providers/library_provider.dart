import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../epub/parser.dart';
import '../../storage/repositories.dart';

final _libraryRepo = LibraryRepo();
const _uuid = Uuid();

/// Copies the picked EPUB into app storage.
///
/// Android's scoped storage hands out paths that go stale — the picker returns
/// a cache entry the OS may clear, and a file the user later moves breaks the
/// stored path. Owning a copy means the library keeps working without the
/// "Archivo no encontrado / Localizar" dance.
Future<String> _importToAppStorage(String sourcePath) async {
  final docs = await getApplicationDocumentsDirectory();
  final booksDir = Directory('${docs.path}/voicex_books');
  if (!await booksDir.exists()) await booksDir.create(recursive: true);

  final dest = '${booksDir.path}/${_uuid.v4()}.epub';
  await File(sourcePath).copy(dest);
  return dest;
}

class LibraryNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() => _libraryRepo.all();

  Future<void> addBook(String filePath) async {
    // Parse first: a malformed EPUB should fail before anything is copied.
    // Off the UI isolate, since unzipping a novel janks the list otherwise.
    final book = await parseEpubInBackground(filePath);
    final storedPath = await _importToAppStorage(filePath);

    final int id;
    try {
      id = await _libraryRepo.add(
        title: book.title,
        author: book.author,
        language: book.language,
        filePath: storedPath,
      );
    } catch (e) {
      // Duplicate file_path or any insert failure: do not leave the copy behind.
      try {
        await File(storedPath).delete();
      } catch (_) {}
      rethrow;
    }

    await _libraryRepo.updateTotalParagraphs(
        id, book.chapters.fold<int>(0, (sum, c) => sum + c.paragraphs.length));

    // Extract cover image and extra metadata asynchronously after insert.
    try {
      final extras = await extractEpubExtras(storedPath);
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
    // Remove our own copy of the EPUB; files picked before this behaviour
    // existed live outside app storage and are left untouched.
    final row = await _libraryRepo.get(id);
    final path = row?['file_path'] as String?;
    final cover = row?['cover_path'] as String?;

    await _libraryRepo.delete(id);

    for (final p in [path, cover]) {
      if (p == null) continue;
      if (p.contains('/voicex_books/') || p.contains('/voicex_covers/')) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
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

/// How the library list is ordered.
enum LibrarySort { recent, title, author, progress }

final librarySortProvider =
    StateProvider<LibrarySort>((ref) => LibrarySort.recent);
final librarySearchProvider = StateProvider<String>((ref) => '');

/// A book row plus how far through it the reader is.
typedef LibraryEntry = ({Map<String, dynamic> book, double progress});

/// Books joined with their reading position, then filtered and sorted.
/// Progress comes from the stored absolute paragraph index, so no EPUB is
/// re-parsed just to draw the list.
final libraryEntriesProvider = FutureProvider<List<LibraryEntry>>((ref) async {
  final books = await ref.watch(libraryProvider.future);
  final positions = await ProgressRepo().allGlobalIndices();
  final query = ref.watch(librarySearchProvider).trim().toLowerCase();
  final sort = ref.watch(librarySortProvider);

  var entries = books.map((b) {
    final total = (b['total_paragraphs'] as int?) ?? 0;
    final at = positions[b['id'] as int] ?? 0;
    final progress = total > 0 ? (at / total).clamp(0.0, 1.0) : 0.0;
    return (book: b, progress: progress);
  }).toList();

  if (query.isNotEmpty) {
    entries = entries.where((e) {
      final title = (e.book['title'] as String? ?? '').toLowerCase();
      final author = (e.book['author'] as String? ?? '').toLowerCase();
      return title.contains(query) || author.contains(query);
    }).toList();
  }

  int byText(String? a, String? b) =>
      (a ?? '').toLowerCase().compareTo((b ?? '').toLowerCase());

  switch (sort) {
    case LibrarySort.title:
      entries.sort((a, b) =>
          byText(a.book['title'] as String?, b.book['title'] as String?));
    case LibrarySort.author:
      entries.sort((a, b) =>
          byText(a.book['author'] as String?, b.book['author'] as String?));
    case LibrarySort.progress:
      entries.sort((a, b) => b.progress.compareTo(a.progress));
    case LibrarySort.recent:
      entries.sort((a, b) => byText(
          b.book['added_at'] as String?, a.book['added_at'] as String?));
  }

  return entries;
});
