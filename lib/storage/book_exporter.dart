import 'dart:convert';
import 'dart:io';

import 'repositories.dart';

/// Leaves a readable copy of every book in the library in [outDir], so the Mac
/// can generate audio from the *same file* the phone has.
///
/// The app keeps each EPUB under a random name (`<uuid>.epub`), and audio made
/// on the Mac is only found again when the book matches by the hash of its
/// bytes: a copy with another name, or another edition of the same title, would
/// not. Taking the file from here removes the guessing.
///
/// With [formatTag] it also writes `inventario.json`: which paragraphs of each
/// book the phone already has, per voice, so `tools/audios/bajar.dart` skips
/// them instead of generating audio the phone would only report as "ya
/// estaban". And where the person is in each book, so `bajar.dart` starts
/// there instead of at paragraph 0 of the chapter: generating half an hour of a
/// chapter already read is what happened without it.
///
/// Returns how many books are in the folder afterwards.
Future<int> exportLibraryBooks(Directory outDir,
    {LibraryRepo? library,
    AudioCacheRepo? cache,
    ProgressRepo? progress,
    String? formatTag}) async {
  final rows = await (library ?? LibraryRepo()).all();
  await outDir.create(recursive: true);

  final keep = <String>{};
  final usedNames = <String>{};
  for (final row in rows) {
    final source = File(row['file_path'] as String);
    if (!await source.exists()) continue;

    var name = _fileName(row['title'] as String? ?? 'libro');
    // Two books may share a title (two editions): the hash tells them apart.
    if (!usedNames.add(name)) {
      final hash = (row['content_hash'] as String? ?? '');
      name = '$name (${hash.isEmpty ? row['id'] : hash.substring(0, 8)})';
      usedNames.add(name);
    }
    final dest = File('${outDir.path}/$name.epub');
    keep.add(dest.path);

    // Same size means the same copy from a previous run: books are tens of MB.
    if (!(await dest.exists() && await dest.length() == await source.length())) {
      await source.copy(dest.path);
    }
    await _shareWithAdb(dest);
  }

  if (formatTag != null) {
    await _writeInventory(outDir, rows, cache ?? AudioCacheRepo(),
        progress ?? ProgressRepo(), formatTag);
  }

  // A book removed from the library should not linger on the cable.
  await for (final e in outDir.list(followLinks: false)) {
    if (e is File && e.path.endsWith('.epub') && !keep.contains(e.path)) {
      await e.delete();
    }
  }
  return keep.length;
}

String _fileName(String title) {
  final clean = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return clean.isEmpty ? 'libro' : (clean.length > 80 ? clean.substring(0, 80) : clean);
}

/// An app creates its files readable by itself only (mode 600), and `adb pull`
/// runs as the `shell` user: "Permission denied" on every book. Best effort:
/// where `chmod` is not there, the export still worked for the phone itself.
Future<void> _shareWithAdb(File f) async {
  try {
    await Process.run('chmod', ['644', f.path]);
  } catch (_) {}
}

Future<void> _writeInventory(Directory outDir, List<Map<String, dynamic>> rows,
    AudioCacheRepo cache, ProgressRepo progress, String formatTag) async {
  final hashOf = {
    for (final r in rows)
      if ((r['content_hash'] as String?)?.isNotEmpty ?? false)
        r['id'] as int: r['content_hash'] as String
  };
  final titleOf = {for (final r in rows) r['id'] as int: r['title'] as String? ?? ''};

  final books = <String, Map<String, dynamic>>{};
  Map<String, dynamic> entry(String hash, int bookId) => books.putIfAbsent(
      hash, () => {'title': titleOf[bookId], 'voices': <String, dynamic>{}});

  // A book that was opened but has nothing downloaded still gets an entry:
  // its position is what tells the Mac where to start.
  for (final e in (await progress.allPositions()).entries) {
    final hash = hashOf[e.key];
    if (hash == null) continue;
    entry(hash, e.key)['position'] = {
      'chapter': e.value.chapter,
      'paragraph': e.value.paragraph,
      'updated': e.value.updatedAt,
    };
  }

  for (final p in await cache.downloadedParagraphs(formatTag)) {
    final hash = hashOf[p.bookId];
    if (hash == null) continue; // audio of a book no longer in the library
    final book = entry(hash, p.bookId);
    final voices = book['voices'] as Map<String, dynamic>;
    final chapters = voices.putIfAbsent(p.voiceId, () => <String, dynamic>{})
        as Map<String, dynamic>;
    (chapters.putIfAbsent('${p.chapter}', () => <int>[]) as List<int>)
        .add(p.paragraph);
  }
  for (final b in books.values) {
    for (final voice in (b['voices'] as Map<String, dynamic>).values) {
      for (final list in (voice as Map<String, dynamic>).values) {
        (list as List<int>).sort();
      }
    }
  }

  final file = File('${outDir.path}/inventario.json');
  await file.writeAsString(jsonEncode({
    'version': 1,
    'generated': DateTime.now().toIso8601String(),
    'format': formatTag,
    'books': books,
  }));
  await _shareWithAdb(file);
}
