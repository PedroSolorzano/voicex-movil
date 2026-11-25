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
      {required bool pinned, String voiceId = 'qwen3-esposa'}) async {
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
      await repo.savePin(1, 0, 0, 'qwen3-esposa', 'f96', download, 2);
      await ageEntry(download, days: 40);

      await repo.pruneExpired();

      expect(File(download).existsSync(), isTrue);
      expect(await repo.get(1, 0, 0, 'qwen3-esposa', 'f96'), download);
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

      expect(await repo.get(1, 0, 0, 'qwen3-esposa', 'f96'), download);
    });

    test('falls through to the next row when the first file is gone', () async {
      final temp = await audioFile('temp.mp3');
      final download = await audioFile('pinned.mp3');
      await insertRow(temp, pinned: false);
      await insertRow(download, pinned: true);
      await File(download).delete();

      expect(await repo.get(1, 0, 0, 'qwen3-esposa', 'f96'), temp);
    });

    test('re-synthesizes nothing while a download is on disk', () async {
      // The failure this guards: the temp row won, its file had been swept by
      // the OS, and the reader concluded the paragraph was not cached at all.
      final temp = await audioFile('temp.mp3');
      final download = await audioFile('pinned.mp3');
      await insertRow(temp, pinned: false);
      await insertRow(download, pinned: true);
      await File(temp).delete();

      expect(await repo.get(1, 0, 0, 'qwen3-esposa', 'f96'), download);
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
      await repo.savePin(1, 0, 0, 'qwen3-esposa', 'f96', download, 2);
      await repo.save(1, 0, 0, 'qwen3-esposa', 'f96', temp, 2);

      expect(File(download).existsSync(), isTrue);
      expect(await repo.get(1, 0, 0, 'qwen3-esposa', 'f96'), download);
    });

    test('savePin retires the temporary copy it supersedes', () async {
      final temp = await audioFile('temp.mp3');
      final download = await audioFile('pinned.mp3');
      await repo.save(1, 0, 0, 'qwen3-esposa', 'f96', temp, 2);
      await repo.savePin(1, 0, 0, 'qwen3-esposa', 'f96', download, 2);

      final db = await getDatabase();
      expect((await db.query('audio_cache')).length, 1);
      expect(File(temp).existsSync(), isFalse);
    });
  });

  group('migrateCacheKeys', () {
    test('keeps the download when an unprefixed row collides with it',
        () async {
      // Whatever has no engine prefix predates the split and is relabelled
      // 'edge-…', which can land on a key that already exists: a temporary copy
      // from an old build next to the download of the same paragraph.
      final db = await getDatabase();
      final temp = await audioFile('temp.mp3');
      final download = await audioFile('pinned.mp3');
      await insertRow(temp, pinned: false, voiceId: 'es-MX-DaliaNeural');
      await insertRow(download,
          pinned: true, voiceId: 'edge-es-MX-DaliaNeural');

      await repo.migrateCacheKeys();

      expect((await db.query('audio_cache')).length, 1);
      expect(await repo.get(1, 0, 0, 'edge-es-MX-DaliaNeural', 'f96'),
          download);
      expect(File(temp).existsSync(), isFalse);
    });

    test('relabels what has no engine prefix as Edge', () async {
      final f = await audioFile('old.mp3');
      await insertRow(f, pinned: true, voiceId: 'es-MX-DaliaNeural');

      await repo.migrateCacheKeys();

      expect(await repo.get(1, 0, 0, 'edge-es-MX-DaliaNeural', 'f96'), f);
    });

    test('leaves the download of every current engine alone', () async {
      // La trampa que se comió a Chatterbox: la regla comodín "sin prefijo
      // conocido -> Edge" convertía 'chatterbox-voz' en 'edge-chatterbox-voz'
      // en cada arranque, una clave que la reproducción nunca consulta, así
      // que la descarga quedaba inalcanzable con el archivo intacto. Este test
      // existe para que no vuelva a pasar con ningún motor que se sume.
      final keys = [
        'edge-es-MX-DaliaNeural',
        'qwen3-esposa',
        'chatterbox2-colombiana',
        'android-es-es-ES',
      ];
      for (var i = 0; i < keys.length; i++) {
        await repo.savePin(
            1, 0, i, keys[i], 'f96', await audioFile('m$i.mp3'), 2);
      }

      await repo.migrateCacheKeys();
      await repo.migrateCacheKeys();

      for (var i = 0; i < keys.length; i++) {
        expect(await repo.get(1, 0, i, keys[i], 'f96'), isNotNull,
            reason: '${keys[i]} se volvió inalcanzable');
      }
    });

    test('a phone-engine download survives the start-up migration', () async {
      // El motor del teléfono volvió en 0.7.0 con el mismo prefijo `android-`
      // que tuvo el viejo, y la migración seguía borrándolo en cada arranque:
      // lo descargado con "Teléfono" desaparecía al abrir la app de nuevo.
      final f = await audioFile('phone.wav');
      await repo.savePin(1, 0, 0, 'android-es-es-ES', 'f96', f, 2);

      await repo.migrateCacheKeys();

      expect(await repo.get(1, 0, 0, 'android-es-es-ES', 'f96'), f);
      expect(File(f).existsSync(), isTrue);
    });

    test('retires the audio of every engine the app no longer has', () async {
      // One row per spelling each retired engine ever had. Pinned, to prove
      // that even a download goes: nothing that remains can play it.
      final retired = <String, String>{
        'android:es-ES': 'android viejo (antes de 0.5.0)',
        'chatterbox-voz_propia': 'chatterbox',
        'edge-chatterbox-voz_propia': 'chatterbox corrompido por la regla comodín',
        'kokoro-af_bella': 'kokoro',
        'kokoro-es-ef_dora': 'kokoro con idioma',
        'kokoro:af_bella': 'kokoro, forma de antes de 0.5.0',
        'edge-kokoro-af_bella': 'kokoro relabelado como Edge',
        'ef_dora': 'kokoro sin prefijo',
        'edge-ef_dora': 'kokoro sin prefijo, relabelado como Edge',
        'piper-es_AR-daniela-high-1_00': 'piper',
        'piper@es_AR-daniela-high': 'piper, forma de antes de 0.5.0',
        'edge-piper-es_AR-daniela-high': 'piper relabelado como Edge',
        'f5-esposa': 'f5',
        'edge-f5-esposa': 'f5 relabelado como Edge',
      };
      final files = <String>[];
      var i = 0;
      final db = await getDatabase();
      for (final id in retired.keys) {
        final f = await audioFile('retirado_${i++}.mp3');
        files.add(f);
        await db.insert('audio_cache', {
          'book_id': 1,
          'chapter_idx': 0,
          'para_idx': i,
          'voice_id': id,
          'speed_hash': 'f96',
          'file_path': f,
          'file_size_kb': 2,
          'pinned': 1,
        });
      }
      final vivo = await audioFile('vivo.mp3');
      await repo.savePin(1, 0, 99, 'qwen3-esposa', 'f96', vivo, 2);

      await repo.migrateCacheKeys();

      // A deletion, not a relabelling: the catch-all rule at the end of the
      // migration would otherwise have turned them into Edge rows.
      final left = await db.query('audio_cache');
      expect(left.map((r) => r['voice_id']), ['qwen3-esposa'],
          reason: 'solo debería quedar el motor vigente');
      for (final f in files) {
        expect(File(f).existsSync(), isFalse, reason: f);
      }
      expect(await repo.get(1, 0, 99, 'qwen3-esposa', 'f96'), vivo);
    });

    test('does not mistake an Edge voice for a retired Kokoro id', () async {
      // Kokoro ids are a language letter, a gender letter and an underscore.
      // Edge names ('es-MX-…', 'en-US-…') must never fit that shape.
      final f = await audioFile('edge.mp3');
      await repo.savePin(1, 0, 0, 'edge-en-US-JennyNeural', 'f96', f, 2);

      await repo.migrateCacheKeys();

      expect(await repo.get(1, 0, 0, 'edge-en-US-JennyNeural', 'f96'), f);
    });

    test('is idempotent on a clean table', () async {
      final download = await audioFile('pinned.mp3');
      await repo.savePin(1, 0, 0, 'qwen3-esposa', 'f96', download, 2);

      await repo.migrateCacheKeys();
      await repo.migrateCacheKeys();
      await repo.migrateCacheKeys();

      expect(await repo.get(1, 0, 0, 'qwen3-esposa', 'f96'), download);
    });
  });

  group('countPinnedByKey', () {
    test('reads the underscores in a key literally, not as wildcards',
        () async {
      await repo.savePin(1, 0, 0, 'qwen3-mi_voz-1_00', 'f96',
          await audioFile('a.wav'), 2);
      await repo.savePin(1, 0, 1, 'qwen3-mi_voz-1_25', 'f96',
          await audioFile('b.wav'), 2);
      // Differs from the first key only where the underscores are — the two
      // are indistinguishable to an unescaped LIKE.
      await repo.savePin(1, 0, 2, 'qwen3-miXvoz-1x00', 'f96',
          await audioFile('c.wav'), 2);

      expect(await repo.countPinnedByKey(prefix: 'qwen3-'), 3);
      expect(await repo.countPinnedByKey(prefix: 'qwen3-mi_voz'), 2);
      expect(
          await repo.countPinnedByKey(prefix: 'qwen3-', suffix: '-1_00'), 1);
    });

    test('ignores temporary audio', () async {
      await repo.save(1, 0, 0, 'qwen3-mi_voz-1_00', 'f96',
          await audioFile('a.wav'), 2);

      expect(await repo.countPinnedByKey(prefix: 'qwen3-'), 0);
    });
  });

  group('eviction and clearing', () {
    test('evictLruUntilFit never touches a download', () async {
      final download = await audioFile('pinned.mp3');
      final temp = await audioFile('temp.mp3');
      await repo.savePin(1, 0, 0, 'qwen3-esposa', 'f96', download, 4096);
      await repo.save(1, 0, 1, 'qwen3-esposa', 'f96', temp, 4096);

      await repo.evictLruUntilFit(1024, 1);

      expect(File(download).existsSync(), isTrue);
      expect(File(temp).existsSync(), isFalse);
    });

    test('clearAll keeps downloads, deleteDownloads removes them', () async {
      final download = await audioFile('pinned.mp3');
      final temp = await audioFile('temp.mp3');
      await repo.savePin(1, 0, 0, 'qwen3-esposa', 'f96', download, 2);
      await repo.save(1, 0, 1, 'qwen3-esposa', 'f96', temp, 2);

      await repo.clearAll();
      expect(File(temp).existsSync(), isFalse);
      expect(File(download).existsSync(), isTrue);

      await repo.deleteDownloads();
      expect(File(download).existsSync(), isFalse);
    });
  });
}
