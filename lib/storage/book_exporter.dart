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
/// Returns how many books are in the folder afterwards.
Future<int> exportLibraryBooks(Directory outDir, {LibraryRepo? library}) async {
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
