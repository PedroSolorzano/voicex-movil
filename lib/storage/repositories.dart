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

class AudioCacheRepo {
  Future<Database> get _db => getDatabase();

  Future<String?> get(int bookId, int chapterIdx, int paraIdx, String voiceId,
      String speedHash) async {
    final db = await _db;
    final rows = await db.query(
      'audio_cache',
      where:
          'book_id=? AND chapter_idx=? AND para_idx=? AND voice_id=? AND speed_hash=?',
      whereArgs: [bookId, chapterIdx, paraIdx, voiceId, speedHash],
    );
    if (rows.isEmpty) return null;
    final filePath = rows.first['file_path'] as String;
    if (!File(filePath).existsSync()) {
      await db.delete('audio_cache',
          where: 'file_path = ?', whereArgs: [filePath]);
      return null;
    }
    await _touch(rows.first['id'] as int);
    return filePath;
  }

  Future<void> save(int bookId, int chapterIdx, int paraIdx, String voiceId,
      String speedHash, String filePath, int fileSizeKb) async {
    final db = await _db;
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
        'pinned': 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Saves as pinned (permanent download — not subject to LRU eviction).
  Future<void> savePin(int bookId, int chapterIdx, int paraIdx, String voiceId,
      String speedHash, String filePath, int fileSizeKb) async {
    final db = await _db;
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
        'pinned': 1,
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
    await db.execute(
        "UPDATE audio_cache SET voice_id = 'kokoro-' || substr(voice_id, 8) "
        "WHERE voice_id LIKE 'kokoro:%'");
    await db.execute(
        "UPDATE audio_cache SET voice_id = 'piper-' || "
        "replace(substr(voice_id, 7), '.', '_') WHERE voice_id LIKE 'piper@%'");
    await db.execute(
        "UPDATE audio_cache SET voice_id = 'android-' || substr(voice_id, 9) "
        "WHERE voice_id LIKE 'android:%'");
    // Anything with no engine prefix predates the split and came from Edge.
    await db.execute(
        "UPDATE audio_cache SET voice_id = 'edge-' || voice_id "
        "WHERE voice_id NOT LIKE 'edge-%' AND voice_id NOT LIKE 'kokoro-%' "
        "AND voice_id NOT LIKE 'piper-%' AND voice_id NOT LIKE 'android-%'");
  }

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

  Future<void> pruneExpired() async {
    final db = await _db;
    final cutoff =
        DateTime.now().subtract(const Duration(days: 5)).toIso8601String();
    final rows = await db.query('audio_cache',
        where: 'last_accessed < ?', whereArgs: [cutoff]);
    for (final row in rows) {
      await _deleteCachedFile(row['file_path'] as String);
    }
    await db.delete('audio_cache', where: 'last_accessed < ?', whereArgs: [cutoff]);
  }

  Future<void> clearAll() async {
    final db = await _db;
    final rows = await db.query('audio_cache');
    for (final row in rows) {
      await _deleteCachedFile(row['file_path'] as String);
    }
    await db.delete('audio_cache');
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
