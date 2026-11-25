import 'dart:convert';
import 'dart:io';

import 'audio_usage.dart';
import 'repositories.dart';

/// What an import run did, in numbers the screen can say out loud.
class ImportResult {
  /// Paragraphs now available offline.
  final int imported;

  /// Paragraphs that were already downloaded, so there was nothing to add.
  final int alreadyThere;

  /// Folders that could not be imported, and why. They are left where they
  /// are so the person can fix the cause and try again.
  final List<String> problems;

  const ImportResult(this.imported, this.alreadyThere, this.problems);

  static const empty = ImportResult(0, 0, []);

  bool get nothingFound => imported == 0 && alreadyThere == 0 && problems.isEmpty;
}

final _itemFile = RegExp(r'^c\d+_p\d+\.(mp3|m4a|wav)$');
final _safeVoiceId = RegExp(r'^[A-Za-z0-9_-]+$');

/// Takes the audio that `tools/audios/bajar.dart` generated on the Mac and
/// pushed over the cable, and makes it look like any other download.
///
/// Each subfolder of [inbox] is one book, with a `manifest.json` that names the
/// book by the SHA-256 of its EPUB (the same one the library stores), the voice
/// and, per file, which chapter and paragraph it is. Files are *moved* into the
/// app's documents folder: leaving a copy in the inbox would double the space
/// they take on the phone.
Future<ImportResult> importMacAudio({
  required Directory inbox,
  required Directory docsDir,
  required String formatTag,
  LibraryRepo? library,
  AudioCacheRepo? cache,
}) async {
  if (!await inbox.exists()) return ImportResult.empty;
  final books = library ?? LibraryRepo();
  final repo = cache ?? AudioCacheRepo();

  var imported = 0, already = 0;
  final problems = <String>[];

  final folders = await inbox
      .list(followLinks: false)
      .where((e) => e is Directory)
      .cast<Directory>()
      .toList();
  folders.sort((a, b) => a.path.compareTo(b.path));

  for (final folder in folders) {
    final name = folder.path.split('/').last;
    final manifestFile = File('${folder.path}/manifest.json');
    if (!await manifestFile.exists()) continue;

    Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(await manifestFile.readAsString())
          as Map<String, dynamic>;
    } catch (_) {
      problems.add('$name: el manifest.json está dañado.');
      continue;
    }

    final voiceId = manifest['voiceId'];
    final hash = manifest['contentHash'];
    final items = manifest['items'];
    if (voiceId is! String ||
        !_safeVoiceId.hasMatch(voiceId) ||
        hash is! String ||
        items is! List) {
      problems.add('$name: el manifest.json no tiene el formato esperado.');
      continue;
    }
    if (describeCacheKey(voiceId).retired) {
      problems.add('$name: la voz "$voiceId" es de un motor que la app no '
          'tiene.');
      continue;
    }
    if (manifest['format'] != formatTag) {
      problems.add('$name: el audio es de otro formato (${manifest['format']}); '
          'vuelve a generarlo con esta versión de la app.');
      continue;
    }
    final book = await books.findByContentHash(hash);
    if (book == null) {
      problems.add('$name: ese libro no está en tu biblioteca. Impórtalo '
          '(el mismo EPUB con el que generaste el audio) y vuelve a '
          'intentarlo.');
      continue;
    }
    final bookId = book['id'] as int;

    var failedHere = 0;
    for (final raw in items) {
      if (raw is! Map) {
        failedHere++;
        continue;
      }
      final chapter = raw['chapter'];
      final paragraph = raw['paragraph'];
      final file = raw['file'];
      if (chapter is! int ||
          paragraph is! int ||
          file is! String ||
          !_itemFile.hasMatch(file)) {
        failedHere++;
        continue;
      }
      final source = File('${folder.path}/$file');
      if (await repo.isPinnedParagraph(
          bookId, chapter, paragraph, voiceId, formatTag)) {
        already++;
        if (await source.exists()) await source.delete();
        continue;
      }
      if (!await source.exists() || await source.length() == 0) {
        failedHere++;
        continue;
      }
      final ext = file.split('.').last;
      final dest = '${docsDir.path}/dl_${bookId}_${chapter}_${paragraph}_'
          '${voiceId}_$formatTag.$ext';
      try {
        await source.copy(dest);
        final kb = (await File(dest).length() / 1024).ceil();
        await repo.savePin(bookId, chapter, paragraph, voiceId, formatTag,
            dest, kb);
        await source.delete();
        imported++;
      } catch (_) {
        failedHere++;
      }
    }

    if (failedHere > 0) {
      problems.add('$name: $failedHere archivos no se pudieron importar.');
    } else {
      // Everything is in: the folder only held the manifest and what is left
      // of the files already moved.
      await folder.delete(recursive: true);
    }
  }
  return ImportResult(imported, already, problems);
}
