import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicex_movil/storage/audio_usage.dart';
import 'package:voicex_movil/storage/database.dart';
import 'package:voicex_movil/storage/repositories.dart';

/// The numbers in Ajustes ("Descargas: 107 MB") add up every book, while the
/// detail only showed the open one, so the two never reconciled. These tests
/// pin the global view that makes them add up, and the deletes that act on it.
void main() {
  late Directory tmp;
  late AudioCacheRepo repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await useDatabaseAt(inMemoryDatabasePath);
    tmp = await Directory.systemTemp.createTemp('voicex_usage_test');
    repo = AudioCacheRepo();
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<String> audioFile(String name, {int bytes = 2048}) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(List.filled(bytes, 7));
    return f.path;
  }

  Future<void> addBook(int id, String title) async {
    final db = await getDatabase();
    await db.insert('books', {
      'id': id,
      'title': title,
      'author': 'x',
      'file_path': '/$id.epub',
      'language': 'es',
    });
  }

  /// A row in the cache: [kb] is what the table records, whatever the file is.
  Future<String> addAudio(int book, int chapter, int para, String voice,
      {bool pinned = true, int kb = 100}) async {
    final path = await audioFile('${book}_${chapter}_${para}_$voice.mp3');
    final db = await getDatabase();
    await db.insert('audio_cache', {
      'book_id': book,
      'chapter_idx': chapter,
      'para_idx': para,
      'voice_id': voice,
      'speed_hash': 'f96',
      'file_path': path,
      'file_size_kb': kb,
      'pinned': pinned ? 1 : 0,
    });
    return path;
  }

  group('describeCacheKey', () {
    test('splits the engine from the voice', () {
      final k = describeCacheKey('qwen3-esposa');

      expect(k.engine, 'qwen3');
      expect(k.detail, 'esposa');
      expect(k.retired, isFalse);
    });

    test('keeps the dashes inside an Edge voice name', () {
      final k = describeCacheKey('edge-es-MX-DaliaNeural');

      expect(k.engine, 'edge');
      expect(k.detail, 'es-MX-DaliaNeural');
    });

    test('a key with no prefix is old Edge, not a retired engine', () {
      final k = describeCacheKey('es-MX-DaliaNeural'.replaceAll('-', '_'));

      expect(k.engine, 'edge');
      expect(k.retired, isFalse);
    });

    test('flags an engine this build no longer has', () {
      for (final key in ['kokoro-af_bella', 'piper-es_AR-x', 'f5-esposa']) {
        expect(describeCacheKey(key).retired, isTrue, reason: key);
      }
      for (final key in [
        'edge-es-MX-DaliaNeural',
        'qwen3-esposa',
        'chatterbox2-colombiana',
        'android-es-es-ES'
      ]) {
        expect(describeCacheKey(key).retired, isFalse, reason: key);
      }
    });
  });

  group('usageByBook', () {
    test('adds up to exactly what sizeBreakdown reports', () async {
      // The whole point: the per-book view and the total in Ajustes agree.
      await addBook(1, 'El talismán');
      await addBook(2, 'Visión ciega');
      await addAudio(1, 0, 0, 'qwen3-esposa', kb: 500);
      await addAudio(1, 0, 1, 'qwen3-esposa', pinned: false, kb: 70);
      await addAudio(2, 3, 5, 'chatterbox2-colombiana', kb: 900);
      await addAudio(99, 0, 0, 'qwen3-esposa', kb: 4000); // a deleted book

      final books = await repo.usageByBook();
      final total = await repo.sizeBreakdown();

      expect(books.fold<int>(0, (n, b) => n + b.totalKb),
          total.cacheKb + total.downloadsKb);
      expect(books.fold<int>(0, (n, b) => n + b.downloadsKb), total.downloadsKb);
    });

    test('lists the audio of a deleted book as orphaned, with its size',
        () async {
      await addBook(1, 'Visión ciega');
      await addAudio(1, 0, 0, 'qwen3-esposa', kb: 100);
      await addAudio(7, 2, 0, 'qwen3-esposa', kb: 8000);

      final books = await repo.usageByBook();

      final orphan = books.singleWhere((b) => b.orphaned);
      expect(orphan.bookId, 7);
      expect(orphan.title, isNull);
      expect(orphan.totalKb, 8000);
      // Biggest first, so what is eating the space is at the top.
      expect(books.first.bookId, 7);
    });

    test('splits one book by engine and voice, downloads from cache', () async {
      await addBook(1, 'Visión ciega');
      await addAudio(1, 0, 0, 'qwen3-esposa', kb: 300);
      await addAudio(1, 0, 1, 'qwen3-esposa', pinned: false, kb: 20);
      await addAudio(1, 0, 2, 'chatterbox2-colombiana', kb: 150);

      final b = (await repo.usageByBook()).single;

      expect(b.keys.map((k) => k.voiceId),
          ['qwen3-esposa', 'chatterbox2-colombiana']);
      final q = b.keys.first;
      expect(q.downloadsKb, 300);
      expect(q.cacheKb, 20);
      expect(q.items, 2);
    });

    test('reports how much is audio no engine can play', () async {
      await addBook(1, 'Visión ciega');
      await addAudio(1, 0, 0, 'qwen3-esposa', kb: 100);
      await addAudio(1, 0, 1, 'kokoro-af_bella', kb: 400);

      expect((await repo.usageByBook()).single.retiredKb, 400);
    });

    test('is empty when nothing is stored', () async {
      expect(await repo.usageByBook(), isEmpty);
    });
  });

  group('usageByChapter', () {
    test('counts paragraphs once even when two engines made them', () async {
      await addBook(1, 'Visión ciega');
      await addAudio(1, 3, 0, 'qwen3-esposa', kb: 100);
      await addAudio(1, 3, 0, 'chatterbox2-colombiana', kb: 100);
      await addAudio(1, 3, 1, 'qwen3-esposa', pinned: false, kb: 50);

      final c = (await repo.usageByChapter(1)).single;

      expect(c.chapter, 3);
      expect(c.paragraphs, 2);
      expect(c.downloadedParagraphs, 1);
      expect(c.kb, 250);
    });

    test('lists chapters in order and only for the book asked', () async {
      await addBook(1, 'a');
      await addBook(2, 'b');
      await addAudio(1, 5, 0, 'qwen3-esposa');
      await addAudio(1, 2, 0, 'qwen3-esposa');
      await addAudio(2, 9, 0, 'qwen3-esposa');

      expect((await repo.usageByChapter(1)).map((c) => c.chapter), [2, 5]);
    });
  });

  group('deleteBefore', () {
    test('removes what comes before a position and keeps the position',
        () async {
      await addBook(1, 'Visión ciega');
      // Chapter 2 whole, chapter 3 paragraphs 0..4, chapter 4 whole.
      for (var p = 0; p < 3; p++) {
        await addAudio(1, 2, p, 'qwen3-esposa');
      }
      for (var p = 0; p < 5; p++) {
        await addAudio(1, 3, p, 'qwen3-esposa');
      }
      await addAudio(1, 4, 0, 'qwen3-esposa');

      final freed = await repo.deleteBefore(1, 3, 2);

      expect(freed, 500, reason: '3 + 2 rows of 100 KB');
      final left = await repo.usageByChapter(1);
      expect(left.map((c) => (c.chapter, c.paragraphs)), [(3, 3), (4, 1)]);
    });

    test('also deletes the files, not just the rows', () async {
      await addBook(1, 'Visión ciega');
      final early = await addAudio(1, 0, 0, 'qwen3-esposa');
      final keep = await addAudio(1, 0, 9, 'qwen3-esposa');

      await repo.deleteBefore(1, 0, 5);

      expect(File(early).existsSync(), isFalse);
      expect(File(keep).existsSync(), isTrue);
    });

    test('never touches another book', () async {
      await addBook(1, 'a');
      await addBook(2, 'b');
      await addAudio(1, 0, 0, 'qwen3-esposa');
      final other = await addAudio(2, 0, 0, 'qwen3-esposa');

      await repo.deleteBefore(1, 9, 9);

      expect(File(other).existsSync(), isTrue);
      expect((await repo.usageByBook()).single.bookId, 2);
    });
  });

  group('usageBefore', () {
    test('says what deleteBefore would free, without freeing it', () async {
      await addBook(1, 'a');
      for (var p = 0; p < 4; p++) {
        await addAudio(1, 2, p, 'qwen3-esposa', kb: 100);
      }
      await addAudio(1, 3, 0, 'qwen3-esposa', kb: 100);

      final before = await repo.usageBefore(1, 2, 3);

      expect(before.kb, 300);
      expect(before.paragraphs, 3);
      expect((await repo.usageByChapter(1)).first.paragraphs, 4,
          reason: 'only asked, nothing deleted');
    });

    test('is zero at the start of the book', () async {
      await addBook(1, 'a');
      await addAudio(1, 0, 0, 'qwen3-esposa');

      expect((await repo.usageBefore(1, 0, 0)).kb, 0);
    });
  });

  group('deleteChapter', () {
    test('removes that chapter and reports what it freed', () async {
      await addBook(1, 'a');
      await addAudio(1, 3, 0, 'qwen3-esposa', kb: 120);
      await addAudio(1, 3, 1, 'qwen3-esposa', kb: 80);
      await addAudio(1, 4, 0, 'qwen3-esposa', kb: 999);

      expect(await repo.deleteChapter(1, 3), 200);
      expect((await repo.usageByChapter(1)).single.chapter, 4);
    });
  });

  group('deleteOrphans and deleteRetiredEngines', () {
    test('deleteOrphans frees only the audio of books that are gone', () async {
      await addBook(1, 'Visión ciega');
      final mine = await addAudio(1, 0, 0, 'qwen3-esposa', kb: 100);
      final gone = await addAudio(7, 0, 0, 'qwen3-esposa', kb: 8000);

      expect(await repo.deleteOrphans(), 8000);

      expect(File(gone).existsSync(), isFalse);
      expect(File(mine).existsSync(), isTrue);
      expect((await repo.usageByBook()).single.bookId, 1);
    });

    test('deleteRetiredEngines keeps every current engine and legacy Edge',
        () async {
      await addBook(1, 'a');
      for (final key in [
        'edge-es-MX-DaliaNeural',
        'qwen3-esposa',
        'chatterbox2-colombiana',
        'android-es-es-ES',
        'es_MX_DaliaNeural', // no prefix: legacy Edge
      ]) {
        await addAudio(1, 0, key.hashCode & 0xFFFF, key, kb: 10);
      }
      for (final key in ['kokoro-af_bella', 'piper-es_AR-x', 'f5-esposa']) {
        await addAudio(1, 1, key.hashCode & 0xFFFF, key, kb: 1000);
      }

      expect(await repo.deleteRetiredEngines(), 3000);

      final left = (await repo.usageByBook()).single;
      expect(left.keys, hasLength(5));
      expect(left.retiredKb, 0);
    });
  });

  group('stray audio files', () {
    test('only the names the cache writes count as audio the cache owns', () {
      expect(looksLikeCachedAudio('12_3_45_qwen3-esposa_f96.mp3'), isTrue);
      expect(looksLikeCachedAudio('dl_12_3_45_qwen3-esposa_f96.mp3'), isTrue);
      expect(looksLikeCachedAudio('dl_12_3_45_x_f96.mp3.ts.json'), isTrue);
      // What playback is using right now must never look like cache.
      expect(looksLikeCachedAudio('qwen3_3f2a-uuid.mp3'), isFalse);
      expect(looksLikeCachedAudio('edge_3f2a-uuid.mp3'), isFalse);
      // And nothing that is not audio.
      expect(looksLikeCachedAudio('voicex.db'), isFalse);
      expect(looksLikeCachedAudio('cover_12.jpg'), isFalse);
      expect(looksLikeCachedAudio('12_3_45_x.epub'), isFalse);
    });

    test('finds audio on disk that no row refers to, and leaves the rest',
        () async {
      await addBook(1, 'a');
      final tracked = await addAudio(1, 0, 0, 'qwen3-esposa');
      final stray = await audioFile('9_0_0_qwen3-esposa_f96.mp3', bytes: 4096);
      final playing = await audioFile('qwen3_8c1d.mp3', bytes: 4096);
      final notAudio = await audioFile('voicex.db', bytes: 4096);

      final found = await findStrayAudio([tmp], await repo.knownPaths());

      expect(found.files.map((f) => f.path), [stray]);
      expect(found.bytes, 4096);
      expect(File(tracked).existsSync(), isTrue);
      expect(File(playing).existsSync(), isTrue);
      expect(File(notAudio).existsSync(), isTrue);
    });

    test('a timing sidecar follows its audio: tracked audio, tracked sidecar',
        () async {
      await addBook(1, 'a');
      final audio = await addAudio(1, 0, 0, 'qwen3-esposa');
      await File('$audio.ts.json').writeAsString('[]');
      final orphanSidecar = await audioFile('9_0_0_x_f96.mp3.ts.json');

      final found = await findStrayAudio([tmp], await repo.knownPaths());

      expect(found.files.map((f) => f.path), [orphanSidecar]);
    });

    test('deleteStrayAudio removes exactly those files', () async {
      final stray = await audioFile('9_0_0_x_f96.mp3');
      final keep = await audioFile('qwen3_8c1d.mp3');

      final found = await findStrayAudio([tmp], <String>{});
      expect(await deleteStrayAudio(found), 1);

      expect(File(stray).existsSync(), isFalse);
      expect(File(keep).existsSync(), isTrue);
    });

    test('a folder that does not exist is not an error', () async {
      final found =
          await findStrayAudio([Directory('${tmp.path}/nope')], <String>{});

      expect(found.files, isEmpty);
      expect(found.kb, 0);
    });
  });
}
