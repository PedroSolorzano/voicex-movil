import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'database.dart';

// ─── Library ────────────────────────────────────────────────────────────────

class LibraryRepo {
  Future<Database> get _db => getDatabase();

  Future<int> add({
    required String title,
    required String author,
    required String language,
    required String filePath,
    String? coverPath,
    String? description,
    String? publisher,
    String? publishedDate,
    String? subject,
  }) async {
    final db = await _db;
    return db.insert('books', {
      'title': title,
      'author': author,
      'language': language,
      'file_path': filePath,
      'cover_path': coverPath,
      'description': description,
      'publisher': publisher,
      'published_date': publishedDate,
      'subject': subject,
    });
  }

  Future<void> updateMeta(
    int id, {
    String? coverPath,
    String? description,
    String? publisher,
    String? publishedDate,
    String? subject,
  }) async {
    final db = await _db;
    final data = <String, dynamic>{};
    if (coverPath != null) data['cover_path'] = coverPath;
    if (description != null) data['description'] = description;
    if (publisher != null) data['publisher'] = publisher;
    if (publishedDate != null) data['published_date'] = publishedDate;
    if (subject != null) data['subject'] = subject;
    if (data.isEmpty) return;
    await db.update('books', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> all() async {
    final db = await _db;
    return db.query('books', orderBy: 'added_at DESC');
  }

  Future<Map<String, dynamic>?> get(int id) async {
    final db = await _db;
    final rows = await db.query('books', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('books', where: 'id = ?', whereArgs: [id]);
  }

  /// Total paragraph count, used for the library progress bar.
  Future<void> updateTotalParagraphs(int id, int total) async {
    final db = await _db;
    await db.update('books', {'total_paragraphs': total},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateLanguage(int id, String language) async {
    final db = await _db;
    await db.update('books', {'language': language},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateFilePath(int id, String filePath) async {
    final db = await _db;
    await db.update('books', {'file_path': filePath},
        where: 'id = ?', whereArgs: [id]);
  }
}

// ─── Progress ───────────────────────────────────────────────────────────────

class ProgressRepo {
  Future<Database> get _db => getDatabase();

  /// One shared position for reading and listening (Kindle+Audible model).
  /// [sentenceIndex] and [offsetMs] let a resume land mid-paragraph instead of
  /// restarting it.
  Future<void> save(int bookId, int chapterIndex, int paragraphIndex,
      {int sentenceIndex = 0, int offsetMs = 0, int globalIndex = 0}) async {
    final db = await _db;
    await db.insert(
      'reading_progress',
      {
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'paragraph_index': paragraphIndex,
        'sentence_index': sentenceIndex,
        'offset_ms': offsetMs,
        'global_index': globalIndex,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<({int chapter, int paragraph, int sentence, int offsetMs})> get(
      int bookId) async {
    final db = await _db;
    final rows = await db.query('reading_progress',
        where: 'book_id = ?', whereArgs: [bookId]);
    if (rows.isEmpty) {
      return (chapter: 0, paragraph: 0, sentence: 0, offsetMs: 0);
    }
    final r = rows.first;
    return (
      chapter: r['chapter_index'] as int,
      paragraph: r['paragraph_index'] as int,
      sentence: (r['sentence_index'] as int?) ?? 0,
      offsetMs: (r['offset_ms'] as int?) ?? 0,
    );
  }

  /// Absolute position of every book, keyed by book id — lets the library show
  /// per-book progress with one query instead of parsing each EPUB.
  Future<Map<int, int>> allGlobalIndices() async {
    final db = await _db;
    final rows = await db.query('reading_progress');
    return {
      for (final r in rows)
        r['book_id'] as int: (r['global_index'] as int?) ?? 0
    };
  }
}

// ─── Bookmarks ───────────────────────────────────────────────────────────────

class BookmarkRepo {
  Future<Database> get _db => getDatabase();

  Future<int> add(int bookId, int chapterIndex, int paragraphIndex,
      {int sentenceIndex = 0, String? note}) async {
    final db = await _db;
    return db.insert('bookmarks', {
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'paragraph_index': paragraphIndex,
      'sentence_index': sentenceIndex,
      'note': note,
    });
  }

  Future<List<Map<String, dynamic>>> listForBook(int bookId) async {
    final db = await _db;
    return db.query('bookmarks',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'created_at DESC');
  }

  Future<void> delete(int id) async {
    final db = await _db;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }
}

// ─── Audio Cache ─────────────────────────────────────────────────────────────

/// What one engine occupies for one book.
class BookEngineUsage {
  final String engine;
  final int cacheKb;
  final int downloadsKb;
  final int items;

  const BookEngineUsage({
    required this.engine,
    required this.cacheKb,
    required this.downloadsKb,
    required this.items,
  });

  int get totalKb => cacheKb + downloadsKb;
}

class AudioCacheRepo {
  Future<Database> get _db => getDatabase();

  /// Path to the cached audio for one paragraph, or null if there is none.
  ///
  /// Downloads come first and the search walks every candidate: a paragraph
  /// played once and later downloaded used to hold two rows — the temporary
  /// copy and the pinned one — and the oldest won. Once the OS cleared the
  /// temp directory the reader re-synthesized a paragraph it had downloaded
  /// hours before, falling back to Edge with the home server out of reach.
  Future<String?> get(int bookId, int chapterIdx, int paraIdx, String voiceId,
      String speedHash) async {
    final db = await _db;
    final rows = await db.query(
      'audio_cache',
      where:
          'book_id=? AND chapter_idx=? AND para_idx=? AND voice_id=? AND speed_hash=?',
      whereArgs: [bookId, chapterIdx, paraIdx, voiceId, speedHash],
      orderBy: 'pinned DESC, id DESC',
    );
    for (final row in rows) {
      final filePath = row['file_path'] as String;
      final file = File(filePath);
      // Missing *or* empty: a truncated write would otherwise be served
      // forever, and the player only reports a generic "source error".
      if (!file.existsSync() || file.lengthSync() < 512) {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
        await db.delete('audio_cache',
            where: 'file_path = ?', whereArgs: [filePath]);
        continue;
      }
      await _touch(row['id'] as int);
      return filePath;
    }
    return null;
  }

  Future<void> save(int bookId, int chapterIdx, int paraIdx, String voiceId,
      String speedHash, String filePath, int fileSizeKb) async {
    await _replaceEntry(bookId, chapterIdx, paraIdx, voiceId, speedHash,
        filePath, fileSizeKb, pinned: false);
  }

  // Saves as pinned (permanent download — not subject to LRU eviction).
  Future<void> savePin(int bookId, int chapterIdx, int paraIdx, String voiceId,
      String speedHash, String filePath, int fileSizeKb) async {
    await _replaceEntry(bookId, chapterIdx, paraIdx, voiceId, speedHash,
        filePath, fileSizeKb, pinned: true);
  }

  /// Writes one row per (paragraph, voice, format), dropping the temporary copy
  /// it supersedes.
  ///
  /// `file_path` is the only UNIQUE column, so plain inserts piled up a second
  /// row every time the same paragraph was cached under a new path — the temp
  /// file and the download live in different directories. The stale rows then
  /// competed in [get]. A pinned row is never removed here: only
  /// [deleteDownloads] retires a download.
  Future<void> _replaceEntry(int bookId, int chapterIdx, int paraIdx,
      String voiceId, String speedHash, String filePath, int fileSizeKb,
      {required bool pinned}) async {
    final db = await _db;
    const where =
        'book_id=? AND chapter_idx=? AND para_idx=? AND voice_id=? AND speed_hash=? '
        'AND pinned=0 AND file_path<>?';
    final args = [bookId, chapterIdx, paraIdx, voiceId, speedHash, filePath];
    final stale = await db.query('audio_cache', where: where, whereArgs: args);
    for (final row in stale) {
      await _deleteCachedFile(row['file_path'] as String);
    }
    await db.delete('audio_cache', where: where, whereArgs: args);

    await db.insert(
      'audio_cache',
      {
        'book_id': bookId,
        'chapter_idx': chapterIdx,
        'para_idx': paraIdx,
        'voice_id': voiceId,
        'speed_hash': speedHash,
        'file_path': filePath,
        'file_size_kb': fileSizeKb,
        'pinned': pinned ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> isPinnedParagraph(int bookId, int chapterIdx, int paraIdx,
      String voiceId, String speedHash) async {
    final db = await _db;
    final rows = await db.query(
      'audio_cache',
      where:
          'book_id=? AND chapter_idx=? AND para_idx=? AND voice_id=? AND speed_hash=? AND pinned=1',
      whereArgs: [bookId, chapterIdx, paraIdx, voiceId, speedHash],
    );
    if (rows.isEmpty) return false;
    final filePath = rows.first['file_path'] as String;
    return File(filePath).existsSync();
  }

  Future<int> countPinned(
      int bookId, int chapterIdx, String voiceId, String speedHash) async {
    final db = await _db;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM audio_cache '
      'WHERE book_id=? AND chapter_idx=? AND voice_id=? AND speed_hash=? AND pinned=1',
      [bookId, chapterIdx, voiceId, speedHash],
    );
    return result.first['c'] as int;
  }

  /// Deletes a cached audio file together with its `.ts.json` word-timestamp
  /// sidecar. The sidecar is not tracked in the table, so without this it would
  /// linger on disk forever after eviction.
  Future<void> _deleteCachedFile(String path) async {
    try {
      final f = File(path);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
    try {
      final sidecar = File('$path.ts.json');
      if (sidecar.existsSync()) await sidecar.delete();
    } catch (_) {}
  }

  /// Rewrites cache keys to the filesystem-safe form.
  ///
  /// Earlier builds embedded the raw key in the filename, and those keys
  /// carried ':' and '@'. Renaming the rows keeps everything already
  /// downloaded reachable instead of forcing hours of re-synthesis; rows whose
  /// file never made it to disk clean themselves up on the next lookup, since
  /// [get] drops a row when its file is missing.
  ///
  /// Idempotent, so it can run on every start.
  Future<void> migrateCacheKeys() async {
    final db = await _db;
    // Before anything renames them: audio from an engine the app no longer
    // has. Nothing will ever ask for it again, and Android TTS wrote WAV, so
    // these are the bulkiest rows on disk. Runs first so the catch-all rule at
    // the end does not relabel them as Edge.
    await _dropRetiredEngineRows();
    await db.execute(
        "UPDATE audio_cache SET voice_id = 'kokoro-' || substr(voice_id, 8) "
        "WHERE voice_id LIKE 'kokoro:%'");
    await db.execute(
        "UPDATE audio_cache SET voice_id = 'piper-' || "
        "replace(substr(voice_id, 7), '.', '_') WHERE voice_id LIKE 'piper@%'");
    // Kokoro voice ids look like af_bella or ef_dora: a language letter, a
    // gender letter, an underscore. Without this they fall through to the Edge
    // rule below and downloads get labelled with an engine that never made
    // them — which is exactly what happened to a first batch.
    await db.execute(
        "UPDATE audio_cache SET voice_id = 'kokoro-' || voice_id "
        "WHERE voice_id GLOB '[abefhijpz][mf]_*' "
        "AND voice_id NOT LIKE 'kokoro-%'");
    // Repair rows already mislabelled by the earlier version of this migration.
    await db.execute(
        "UPDATE audio_cache SET voice_id = 'kokoro-' || substr(voice_id, 6) "
        "WHERE voice_id LIKE 'edge-%' "
        "AND substr(voice_id, 6) GLOB '[abefhijpz][mf]_*'");
    // Whatever is left with no engine prefix predates the split and came from Edge.
    await db.execute(
        "UPDATE audio_cache SET voice_id = 'edge-' || voice_id "
        "WHERE voice_id NOT LIKE 'edge-%' AND voice_id NOT LIKE 'kokoro-%' "
        "AND voice_id NOT LIKE 'piper-%'");

    await _dropDuplicateRows();
  }

  /// Deletes audio produced by an engine the app has since dropped.
  ///
  /// Android TTS went away in 0.6.0. Covers both spellings its key ever had:
  /// the 'android:' form used before 0.5.0 and the 'android-' one after it.
  Future<void> _dropRetiredEngineRows() async {
    final db = await _db;
    const where = "voice_id LIKE 'android-%' OR voice_id LIKE 'android:%'";
    final rows = await db.query('audio_cache', where: where);
    for (final row in rows) {
      await _deleteCachedFile(row['file_path'] as String);
    }
    await db.delete('audio_cache', where: where);
  }

  /// Leaves one row per (paragraph, voice, format): the download if there is
  /// one, otherwise the most recent.
  ///
  /// Builds before this one inserted a second row whenever the same paragraph
  /// was cached under a new path, and the renames above can merge two keys into
  /// one. Runs on every start, alongside [migrateCacheKeys], and does nothing
  /// once the table is clean.
  Future<void> _dropDuplicateRows() async {
    final db = await _db;
    // Deliberately no window function: Android 7 — the oldest release this app
    // supports — ships SQLite 3.9, and ROW_NUMBER() needs 3.25. This picks out
    // every row that has a better-ranked sibling, which is the same set.
    final losers = await db.rawQuery('''
      SELECT a.id AS id, a.file_path AS file_path FROM audio_cache a
      WHERE EXISTS (
        SELECT 1 FROM audio_cache b
        WHERE b.book_id = a.book_id AND b.chapter_idx = a.chapter_idx
          AND b.para_idx = a.para_idx AND b.voice_id = a.voice_id
          AND b.speed_hash = a.speed_hash
          AND (b.pinned > a.pinned OR (b.pinned = a.pinned AND b.id > a.id))
      )
    ''');
    if (losers.isEmpty) return;
    for (final row in losers) {
      await _deleteCachedFile(row['file_path'] as String);
    }
    await db.delete('audio_cache',
        where: 'id IN (${List.filled(losers.length, '?').join(',')})',
        whereArgs: [for (final row in losers) row['id']]);
  }

  /// Pinned paragraphs whose cache key starts with [prefix] and ends with
  /// [suffix]. Used to warn before a setting change orphans what is already
  /// downloaded.
  ///
  /// Both are literals, not patterns: cache keys are full of '_', which `LIKE`
  /// reads as "any character". Matching 'piper-1_25' without escaping also
  /// matched 'piper-1x25', and every other key of that shape.
  Future<int> countPinnedByKey({String prefix = '', String suffix = ''}) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM audio_cache WHERE pinned=1 '
      "AND voice_id LIKE ? ESCAPE '\\'",
      ['${_escapeLike(prefix)}%${_escapeLike(suffix)}'],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  /// Diagnostic: what is actually stored for a book, grouped by cache key.
  Future<List<Map<String, Object?>>> debugKeys(int bookId) async {
    final db = await _db;
    return db.rawQuery(
      'SELECT voice_id, speed_hash, pinned, COUNT(*) AS n, '
      'MIN(chapter_idx) AS ch_min, MAX(chapter_idx) AS ch_max, '
      'MIN(file_path) AS sample '
      'FROM audio_cache WHERE book_id=? '
      'GROUP BY voice_id, speed_hash, pinned',
      [bookId],
    );
  }

  Future<void> _touch(int id) async {
    final db = await _db;
    await db.update(
      'audio_cache',
      {'last_accessed': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> totalSizeKb() async {
    final db = await _db;
    final result =
        await db.rawQuery('SELECT COALESCE(SUM(file_size_kb), 0) AS total FROM audio_cache');
    return result.first['total'] as int;
  }

  Future<void> evictLruUntilFit(int estimatedKb, int maxMb) async {
    final maxKb = maxMb * 1024;
    final currentKb = await totalSizeKb();
    if (currentKb + estimatedKb <= maxKb) return;
    await _evictToTarget((maxKb * 0.8).toInt());
  }

  Future<void> evict(int maxMb) async {
    final maxKb = maxMb * 1024;
    final currentKb = await totalSizeKb();
    if (currentKb <= maxKb) return;
    await _evictToTarget((maxKb * 0.8).toInt());
  }

  /// Drops cache entries untouched for five days — **never downloads**.
  ///
  /// This runs on every launch, so forgetting the `pinned` filter meant a book
  /// downloaded and not opened for a week vanished on its own: hours of Kokoro
  /// synthesis, gone without a word. Downloads expire only when the reader says
  /// so, via [deleteDownloads].
  Future<void> pruneExpired() async {
    final db = await _db;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 5)).toIso8601String();
    const where = 'last_accessed < ? AND pinned = 0';
    final rows =
        await db.query('audio_cache', where: where, whereArgs: [cutoff]);
    for (final row in rows) {
      await _deleteCachedFile(row['file_path'] as String);
    }
    await db.delete('audio_cache', where: where, whereArgs: [cutoff]);
  }

  /// Clears the temporary cache, **keeping downloads**.
  ///
  /// Pinned entries are audio the reader deliberately downloaded for offline
  /// listening — often hours of synthesis. Wiping those from a button labelled
  /// "clear cache" would be a nasty surprise; [deleteDownloads] exists for when
  /// that is really what is wanted.
  Future<void> clearAll() async {
    final db = await _db;
    final rows = await db.query('audio_cache', where: 'pinned = 0');
    for (final row in rows) {
      await _deleteCachedFile(row['file_path'] as String);
    }
    await db.delete('audio_cache', where: 'pinned = 0');
  }

  /// Deletes the downloaded (pinned) audio.
  Future<void> deleteDownloads() async {
    final db = await _db;
    final rows = await db.query('audio_cache', where: 'pinned = 1');
    for (final row in rows) {
      await _deleteCachedFile(row['file_path'] as String);
    }
    await db.delete('audio_cache', where: 'pinned = 1');
  }

  /// Usage for one book, grouped by engine.
  ///
  /// The engine is the prefix of the cache key ("kokoro-af_bella"), so no extra
  /// column is needed: the key already names what produced the audio.
  Future<List<BookEngineUsage>> usageForBook(int bookId) async {
    final db = await _db;
    final rows = await db.rawQuery(
      'SELECT voice_id, pinned, COUNT(*) AS n, SUM(file_size_kb) AS kb '
      'FROM audio_cache WHERE book_id = ? GROUP BY voice_id, pinned',
      [bookId],
    );

    final byEngine = <String, BookEngineUsage>{};
    for (final r in rows) {
      final key = (r['voice_id'] as String?) ?? '';
      final engine = key.contains('-') ? key.split('-').first : 'edge';
      final kb = (r['kb'] as int?) ?? 0;
      final n = (r['n'] as int?) ?? 0;
      final pinned = (r['pinned'] as int?) == 1;

      final current = byEngine[engine] ??
          BookEngineUsage(engine: engine, cacheKb: 0, downloadsKb: 0, items: 0);
      byEngine[engine] = BookEngineUsage(
        engine: engine,
        cacheKb: current.cacheKb + (pinned ? 0 : kb),
        downloadsKb: current.downloadsKb + (pinned ? kb : 0),
        items: current.items + n,
      );
    }

    final list = byEngine.values.toList()
      ..sort((a, b) => (b.cacheKb + b.downloadsKb)
          .compareTo(a.cacheKb + a.downloadsKb));
    return list;
  }

  /// Deletes one book's audio, optionally narrowed to a single [engine].
  Future<void> deleteForBook(int bookId, {String? engine}) async {
    final db = await _db;
    final where = engine == null
        ? 'book_id = ?'
        : 'book_id = ? AND voice_id LIKE ?';
    final args = engine == null ? [bookId] : [bookId, '$engine-%'];

    final rows = await db.query('audio_cache', where: where, whereArgs: args);
    for (final row in rows) {
      await _deleteCachedFile(row['file_path'] as String);
    }
    await db.delete('audio_cache', where: where, whereArgs: args);
  }

  /// Wipes everything: cache and downloads, every book.
  Future<void> deleteEverything() async {
    final db = await _db;
    final rows = await db.query('audio_cache');
    for (final row in rows) {
      await _deleteCachedFile(row['file_path'] as String);
    }
    await db.delete('audio_cache');
  }

  /// Size in KB split by whether it was downloaded on purpose.
  Future<({int cacheKb, int downloadsKb})> sizeBreakdown() async {
    final db = await _db;
    final rows = await db.rawQuery(
        'SELECT pinned, SUM(file_size_kb) AS kb FROM audio_cache GROUP BY pinned');
    var cache = 0, downloads = 0;
    for (final r in rows) {
      final kb = (r['kb'] as int?) ?? 0;
      if ((r['pinned'] as int?) == 1) {
        downloads = kb;
      } else {
        cache = kb;
      }
    }
    return (cacheKb: cache, downloadsKb: downloads);
  }

  Future<void> _evictToTarget(int targetKb) async {
    final db = await _db;
    while (true) {
      final current = await totalSizeKb();
      if (current <= targetKb) break;
      // Never evict pinned (downloaded) entries.
      final rows = await db.query('audio_cache',
          where: 'pinned = 0', orderBy: 'last_accessed ASC', limit: 1);
      if (rows.isEmpty) break;
      final row = rows.first;
      await _deleteCachedFile(row['file_path'] as String);
      await db.delete('audio_cache',
          where: 'id = ?', whereArgs: [row['id']]);
    }
  }
}
