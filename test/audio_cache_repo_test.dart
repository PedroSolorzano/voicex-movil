import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicex_movil/storage/database.dart';
import 'package:voicex_movil/storage/repositories.dart';

/// Exercises the cache against the real schema. Every bug this file guards
/// against shipped at some point: downloads deleted by the five-day prune,
/// downloads shadowed by a stale temporary row, and a `LIKE` that treated the
/// underscores in a cache key as wildcards.
void main() {
  late Directory tmp;
  late AudioCacheRepo repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await useDatabaseAt(inMemoryDatabasePath);
    tmp = await Directory.systemTemp.createTemp('voicex_cache_test');
    repo = AudioCacheRepo();
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  /// A file large enough to pass the 512-byte "is this playable" check.
  Future<String> audioFile(String name, {int bytes = 2048}) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(List.filled(bytes, 7));
    return f.path;
  }

  /// Writes a row straight into the table, bypassing the de-duplication in
  /// [AudioCacheRepo.save]. This is how older builds left the cache: a
  /// temporary copy and a download side by side for the same paragraph.
  Future<void> insertRow(String filePath,
      {required bool pinned, String voiceId = 'kokoro-af_bella'}) async {
    final db = await getDatabase();
    await db.insert('audio_cache', {
      'book_id': 1,
      'chapter_idx': 0,
      'para_idx': 0,
      'voice_id': voiceId,
      'speed_hash': 'f96',
      'file_path': filePath,
      'file_size_kb': 2,
      'pinned': pinned ? 1 : 0,
    });
  }

  Future<void> ageEntry(String filePath, {required int days}) async {
    final db = await getDatabase();
    final when =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    await db.update('audio_cache', {'last_accessed': when},
        where: 'file_path = ?', whereArgs: [filePath]);
  }

  group('pruneExpired', () {
    test('keeps downloads no matter how long they sit untouched', () async {
      final download = await audioFile('pinned.mp3');
      await repo.savePin(1, 0, 0, 'kokoro-af_bella', 'f96', download, 2);
      await ageEntry(download, days: 40);

      await repo.pruneExpired();

      expect(File(download).existsSync(), isTrue);
      expect(await repo.get(1, 0, 0, 'kokoro-af_bella', 'f96'), download);
    });

    test('still drops temporary audio past five days', () async {
      final temp = await audioFile('temp.mp3');
      await repo.save(1, 0, 0, 'edge-es-MX-DaliaNeural', 'f96', temp, 2);
      await ageEntry(temp, days: 6);

      await repo.pruneExpired();

      expect(File(temp).existsSync(), isFalse);
      expect(await repo.get(1, 0, 0, 'edge-es-MX-DaliaNeural', 'f96'), isNull);
    });

    test('leaves recent temporary audio alone', () async {
      final temp = await audioFile('fresh.mp3');
      await repo.save(1, 0, 0, 'edge-es-MX-DaliaNeural', 'f96', temp, 2);

      await repo.pruneExpired();

      expect(await repo.get(1, 0, 0, 'edge-es-MX-DaliaNeural', 'f96'), temp);
    });
  });

  group('get', () {
    test('prefers the download over an older temporary copy', () async {
      // Order of insertion matters: the temporary row is the oldest, and it is
      // the one a plain query returns first.
      final temp = await audioFile('temp.mp3');
      final download = await audioFile('pinned.mp3');
      await insertRow(temp, pinned: false);
      await insertRow(download, pinned: true);

      expect(await repo.get(1, 0, 0, 'kokoro-af_bella', 'f96'), download);
    });

    test('falls through to the next row when the first file is gone', () async {
      final temp = await audioFile('temp.mp3');
      final download = await audioFile('pinned.mp3');
      await insertRow(temp, pinned: false);
      await insertRow(download, pinned: true);
      await File(download).delete();

      expect(await repo.get(1, 0, 0, 'kokoro-af_bella', 'f96'), temp);
    });

    test('re-synthesizes nothing while a download is on disk', () async {
      // The failure this guards: the temp row won, its file had been swept by
      // the OS, and the reader concluded the paragraph was not cached at all.
      final temp = await audioFile('temp.mp3');
      final download = await audioFile('pinned.mp3');
      await insertRow(temp, pinned: false);
      await insertRow(download, pinned: true);
      await File(temp).delete();

      expect(await repo.get(1, 0, 0, 'kokoro-af_bella', 'f96'), download);
    });

    test('treats an empty file as absent and forgets the row', () async {
      final truncated = await audioFile('truncated.mp3', bytes: 10);
      await repo.save(1, 0, 0, 'edge-es-MX-DaliaNeural', 'f96', truncated, 1);

      expect(await repo.get(1, 0, 0, 'edge-es-MX-DaliaNeural', 'f96'), isNull);
      expect(File(truncated).existsSync(), isFalse);

      final db = await getDatabase();
      expect(await db.query('audio_cache'), isEmpty);
    });
  });

  group('save', () {
    test('replaces the previous temporary copy instead of piling up rows',
        () async {
      final first = await audioFile('first.mp3');
      final second = await audioFile('second.mp3');
      await repo.save(1, 0, 0, 'edge-es-MX-DaliaNeural', 'f96', first, 2);
      await repo.save(1, 0, 0, 'edge-es-MX-DaliaNeural', 'f96', second, 2);

      final db = await getDatabase();
      expect((await db.query('audio_cache')).length, 1);
      expect(File(first).existsSync(), isFalse);
      expect(await repo.get(1, 0, 0, 'edge-es-MX-DaliaNeural', 'f96'), second);
    });

    test('never removes a download while caching the same paragraph', () async {
      final download = await audioFile('pinned.mp3');
      final temp = await audioFile('temp.mp3');
      await repo.savePin(1, 0, 0, 'kokoro-af_bella', 'f96', download, 2);
      await repo.save(1, 0, 0, 'kokoro-af_bella', 'f96', temp, 2);

      expect(File(download).existsSync(), isTrue);
      expect(await repo.get(1, 0, 0, 'kokoro-af_bella', 'f96'), download);
    });

    test('savePin retires the temporary copy it supersedes', () async {
      final temp = await audioFile('temp.mp3');
      final download = await audioFile('pinned.mp3');
      await repo.save(1, 0, 0, 'kokoro-af_bella', 'f96', temp, 2);
      await repo.savePin(1, 0, 0, 'kokoro-af_bella', 'f96', download, 2);

      final db = await getDatabase();
      expect((await db.query('audio_cache')).length, 1);
      expect(File(temp).existsSync(), isFalse);
    });
  });

  group('migrateCacheKeys', () {
    test('renames old keys and keeps the download when two rows collide',
        () async {
      final db = await getDatabase();
      final temp = await audioFile('temp.mp3');
      final download = await audioFile('pinned.mp3');
      // 'kokoro:af_bella' is the pre-0.5.0 spelling; the migration rewrites it
      // to 'kokoro-af_bella', which collides with the row already stored that
      // way. Only one may survive, and it has to be the download.
      await db.insert('audio_cache', {
        'book_id': 1,
        'chapter_idx': 0,
        'para_idx': 0,
        'voice_id': 'kokoro:af_bella',
        'speed_hash': 'f96',
        'file_path': temp,
        'file_size_kb': 2,
        'pinned': 0,
      });
      await db.insert('audio_cache', {
        'book_id': 1,
        'chapter_idx': 0,
        'para_idx': 0,
        'voice_id': 'kokoro-af_bella',
        'speed_hash': 'f96',
        'file_path': download,
        'file_size_kb': 2,
        'pinned': 1,
      });

      await repo.migrateCacheKeys();

      expect((await db.query('audio_cache')).length, 1);
      expect(await repo.get(1, 0, 0, 'kokoro-af_bella', 'f96'), download);
      expect(File(temp).existsSync(), isFalse);
    });

    test('retires the audio of an engine the app no longer has', () async {
      final db = await getDatabase();
      // Both spellings the Android key ever had: 'android:' before 0.5.0,
      // 'android-' after it. Pinned, to prove even a download goes.
      final oldSpelling = await audioFile('old.wav');
      final newSpelling = await audioFile('new.wav');
      await insertRow(oldSpelling, pinned: true, voiceId: 'android:es-ES');
      await insertRow(newSpelling, pinned: true, voiceId: 'android-es');
      final kept = await audioFile('kokoro.mp3');
      await repo.savePin(1, 0, 1, 'kokoro-af_bella', 'f96', kept, 2);

      await repo.migrateCacheKeys();

      expect(File(oldSpelling).existsSync(), isFalse);
      expect(File(newSpelling).existsSync(), isFalse);
      // A deletion, not a relabelling: the catch-all rule at the end of the
      // migration would otherwise have turned them into 'edge-android-es'.
      expect(await db.query('audio_cache', where: "voice_id LIKE '%android%'"),
          isEmpty);
      expect(await repo.get(1, 0, 1, 'kokoro-af_bella', 'f96'), kept);
    });

    test('mete el idioma del libro en las claves de Kokoro y Piper', () async {
      // Sin esto, un libro en inglés y otro en español compartían audio cuando
      // la misma voz servía para ambos. Migrar en vez de cambiar la clave a
      // secas es lo que evita huerfanizar las descargas ya hechas: horas de
      // síntesis que la app no puede permitirse perder.
      final db = await getDatabase();
      await db.insert('books', {
        'id': 7,
        'title': 'The Gunslinger',
        'author': 'Stephen King',
        'file_path': '/x.epub',
        'language': 'en',
      });
      final ingles = await audioFile('ing.aac');
      await db.insert('audio_cache', {
        'book_id': 7,
        'chapter_idx': 0,
        'para_idx': 0,
        'voice_id': 'kokoro-af_bella',
        'speed_hash': 'f96',
        'file_path': ingles,
        'file_size_kb': 2,
        'pinned': 1,
      });

      await repo.migrateCacheKeys();

      expect(await repo.get(7, 0, 0, 'kokoro-en-af_bella', 'f96'), ingles);
    });

    test('la migración del idioma es idempotente', () async {
      final db = await getDatabase();
      await db.insert('books', {
        'id': 8,
        'title': 'El talismán',
        'author': 'Stephen King',
        'file_path': '/y.epub',
        'language': 'es',
      });
      final es = await audioFile('esp.aac');
      await db.insert('audio_cache', {
        'book_id': 8,
        'chapter_idx': 0,
        'para_idx': 0,
        'voice_id': 'kokoro-af_bella',
        'speed_hash': 'f96',
        'file_path': es,
        'file_size_kb': 2,
        'pinned': 1,
      });

      await repo.migrateCacheKeys();
      await repo.migrateCacheKeys();
      await repo.migrateCacheKeys();

      // Correrla tres veces no puede dar kokoro-es-es-es-af_bella.
      expect(await repo.get(8, 0, 0, 'kokoro-es-af_bella', 'f96'), es);
    });

    test('is idempotent on a clean table', () async {
      final download = await audioFile('pinned.mp3');
      await repo.savePin(1, 0, 0, 'kokoro-af_bella', 'f96', download, 2);

      await repo.migrateCacheKeys();
      await repo.migrateCacheKeys();

      expect(await repo.get(1, 0, 0, 'kokoro-af_bella', 'f96'), download);
    });
  });

  group('countPinnedByKey', () {
    test('reads the underscores in a key literally, not as wildcards',
        () async {
      await repo.savePin(1, 0, 0, 'piper-es_AR-daniela-high-1_00', 'f96',
          await audioFile('a.wav'), 2);
      await repo.savePin(1, 0, 1, 'piper-es_AR-daniela-high-1_25', 'f96',
          await audioFile('b.wav'), 2);
      // Differs from the first key only where the underscores are — the two
      // are indistinguishable to an unescaped LIKE.
      await repo.savePin(1, 0, 2, 'piper-esXAR-daniela-high-1x00', 'f96',
          await audioFile('c.wav'), 2);

      expect(await repo.countPinnedByKey(prefix: 'piper-'), 3);
      expect(await repo.countPinnedByKey(prefix: 'piper-es_AR-'), 2);
      expect(
          await repo.countPinnedByKey(prefix: 'piper-', suffix: '-1_00'), 1);
    });

    test('ignores temporary audio', () async {
      await repo.save(1, 0, 0, 'piper-es_AR-daniela-high-1_00', 'f96',
          await audioFile('a.wav'), 2);

      expect(await repo.countPinnedByKey(prefix: 'piper-'), 0);
    });
  });

  group('eviction and clearing', () {
    test('evictLruUntilFit never touches a download', () async {
      final download = await audioFile('pinned.mp3');
      final temp = await audioFile('temp.mp3');
      await repo.savePin(1, 0, 0, 'kokoro-af_bella', 'f96', download, 4096);
      await repo.save(1, 0, 1, 'kokoro-af_bella', 'f96', temp, 4096);

      await repo.evictLruUntilFit(1024, 1);

      expect(File(download).existsSync(), isTrue);
      expect(File(temp).existsSync(), isFalse);
    });

    test('clearAll keeps downloads, deleteDownloads removes them', () async {
      final download = await audioFile('pinned.mp3');
      final temp = await audioFile('temp.mp3');
      await repo.savePin(1, 0, 0, 'kokoro-af_bella', 'f96', download, 2);
      await repo.save(1, 0, 1, 'kokoro-af_bella', 'f96', temp, 2);

      await repo.clearAll();
      expect(File(temp).existsSync(), isFalse);
      expect(File(download).existsSync(), isTrue);

      await repo.deleteDownloads();
      expect(File(download).existsSync(), isFalse);
    });
  });
}
