import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicex_movil/storage/audio_importer.dart';
import 'package:voicex_movil/storage/database.dart';
import 'package:voicex_movil/storage/repositories.dart';

/// The audio generated on the Mac only helps if the reader finds it exactly as
/// it would find a download: same book id, chapter, paragraph, voice and tag.
void main() {
  late Directory tmp, inbox, docs;
  late int bookId;
  const hash = 'abc123';
  const tag = 'f96';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await useDatabaseAt(inMemoryDatabasePath);
    tmp = await Directory.systemTemp.createTemp('voicex_import_test');
    inbox = await Directory('${tmp.path}/importar').create();
    docs = await Directory('${tmp.path}/docs').create();
    bookId = await LibraryRepo().add(
        title: 'Visión ciega',
        author: 'Peter Watts',
        filePath: '/x.epub',
        language: 'es',
        contentHash: hash);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<Directory> pushed(
      {String voiceId = 'chatterbox2-colombiana',
      String contentHash = hash,
      String format = tag,
      List<List<int>> paras = const [
        [2, 45],
        [2, 46]
      ],
      bool writeFiles = true}) async {
    final dir = await Directory('${inbox.path}/vision-ciega').create();
    for (final p in paras) {
      if (writeFiles) {
        await File('${dir.path}/c${p[0]}_p${p[1]}.mp3')
            .writeAsBytes(List.filled(3000, 5));
      }
    }
    await File('${dir.path}/manifest.json').writeAsString(jsonEncode({
      'version': 1,
      'contentHash': contentHash,
      'voiceId': voiceId,
      'format': format,
      'items': [
        for (final p in paras)
          {'chapter': p[0], 'paragraph': p[1], 'file': 'c${p[0]}_p${p[1]}.mp3'}
      ],
    }));
    return dir;
  }

  Future<ImportResult> run() => importMacAudio(
      inbox: inbox, docsDir: docs, formatTag: tag);

  test('imports as pinned downloads the reader finds by its own key', () async {
    await pushed();

    final r = await run();

    expect(r.imported, 2);
    expect(r.problems, isEmpty);
    expect(
        await AudioCacheRepo().isPinnedParagraph(
            bookId, 2, 45, 'chatterbox2-colombiana', tag),
        isTrue);
    expect(
        File('${docs.path}/dl_${bookId}_2_45_chatterbox2-colombiana_f96.mp3')
            .existsSync(),
        isTrue);
  });

  test('moves the files: nothing is left taking space in the inbox', () async {
    final dir = await pushed();

    await run();

    expect(dir.existsSync(), isFalse);
  });

  test('importing twice adds nothing and says they were already there',
      () async {
    await pushed();
    await run();
    await pushed();

    final r = await run();

    expect(r.imported, 0);
    expect(r.alreadyThere, 2);
  });

  test('a book that is not in the library stays in the inbox', () async {
    final dir = await pushed(contentHash: 'otro');

    final r = await run();

    expect(r.imported, 0);
    expect(r.problems.single, contains('no está en tu biblioteca'));
    expect(dir.existsSync(), isTrue);
  });

  test('refuses a voice from an engine the app no longer has', () async {
    await pushed(voiceId: 'f5-default');

    final r = await run();

    expect(r.imported, 0);
    expect(r.problems.single, contains('motor que la app no tiene'));
  });

  test('refuses audio of another cache format instead of filing it unreachable',
      () async {
    await pushed(format: 'f80');

    final r = await run();

    expect(r.imported, 0);
    expect(r.problems.single, contains('otro formato'));
  });

  test('a voice id that is not a safe path segment is refused', () async {
    await pushed(voiceId: 'chatterbox2-../../x');

    final r = await run();

    expect(r.imported, 0);
    expect(r.problems, isNotEmpty);
  });

  test('a file name that tries to leave the folder is skipped', () async {
    final dir = await pushed(paras: const [], writeFiles: false);
    await File('${dir.path}/manifest.json').writeAsString(jsonEncode({
      'version': 1,
      'contentHash': hash,
      'voiceId': 'chatterbox2-colombiana',
      'format': tag,
      'items': [
        {'chapter': 0, 'paragraph': 0, 'file': '../../etc/passwd'}
      ],
    }));

    final r = await run();

    expect(r.imported, 0);
    expect(r.problems.single, contains('no se pudieron importar'));
  });

  test('a missing file is reported and the folder is kept to retry', () async {
    final dir = await pushed();
    await File('${dir.path}/c2_p46.mp3').delete();

    final r = await run();

    expect(r.imported, 1);
    expect(r.problems.single, contains('1 archivos'));
    expect(dir.existsSync(), isTrue);
  });

  test('no inbox, or an empty one, is not an error', () async {
    expect((await run()).nothingFound, isTrue);
    await inbox.delete(recursive: true);
    expect((await run()).nothingFound, isTrue);
  });

  test('a damaged manifest is reported, not thrown', () async {
    final dir = await Directory('${inbox.path}/roto').create();
    await File('${dir.path}/manifest.json').writeAsString('{no es json');

    final r = await run();

    expect(r.problems.single, contains('dañado'));
  });
}
