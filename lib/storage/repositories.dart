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
  }) async {
    final db = await _db;
    return db.insert('books', {
      'title': title,
      'author': author,
      'language': language,
      'file_path': filePath,
    });
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

  Future<void> save(int bookId, int chapterIndex, int paragraphIndex) async {
    final db = await _db;
    await db.insert(
      'reading_progress',
      {
        'book_id': bookId,
        'chapter_index': chapterIndex,
        'paragraph_index': paragraphIndex,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<({int chapter, int paragraph})> get(int bookId) async {
    final db = await _db;
    final rows = await db.query('reading_progress',
        where: 'book_id = ?', whereArgs: [bookId]);
    if (rows.isEmpty) return (chapter: 0, paragraph: 0);
    return (
      chapter: rows.first['chapter_index'] as int,
      paragraph: rows.first['paragraph_index'] as int,
    );
  }
}

// ─── Bookmarks ───────────────────────────────────────────────────────────────

class BookmarkRepo {
  Future<Database> get _db => getDatabase();

  Future<int> add(int bookId, int chapterIndex, int paragraphIndex,
      {String? note}) async {
    final db = await _db;
    return db.insert('bookmarks', {
      'book_id': bookId,
      'chapter_index': chapterIndex,
      'paragraph_index': paragraphIndex,
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
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
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
      final f = File(row['file_path'] as String);
      if (f.existsSync()) await f.delete();
    }
    await db.delete('audio_cache', where: 'last_accessed < ?', whereArgs: [cutoff]);
  }

  Future<void> clearAll() async {
    final db = await _db;
    final rows = await db.query('audio_cache');
    for (final row in rows) {
      final f = File(row['file_path'] as String);
      if (f.existsSync()) await f.delete();
    }
    await db.delete('audio_cache');
  }

  Future<void> _evictToTarget(int targetKb) async {
    final db = await _db;
    while (true) {
      final current = await totalSizeKb();
      if (current <= targetKb) break;
      final rows = await db.query('audio_cache',
          orderBy: 'last_accessed ASC', limit: 1);
      if (rows.isEmpty) break;
      final row = rows.first;
      final f = File(row['file_path'] as String);
      if (f.existsSync()) await f.delete();
      await db.delete('audio_cache',
          where: 'id = ?', whereArgs: [row['id']]);
    }
  }
}
