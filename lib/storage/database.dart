import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

Database? _db;
String? _pathOverride;

Future<Database> getDatabase() async {
  if (_db != null) return _db!;
  _db = await openDatabase(
    _pathOverride ?? join(await getDatabasesPath(), 'voicex.db'),
    version: 6,
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
    onConfigure: _onConfigure,
  );
  return _db!;
}

/// Points the repositories at [path] — `inMemoryDatabasePath` in tests.
///
/// The connection is a module-level singleton, so tests need a way to drop it
/// between cases; without this the schema and rows of one test leak into the
/// next.
@visibleForTesting
Future<void> useDatabaseAt(String path) async {
  await _db?.close();
  _db = null;
  _pathOverride = path;
}

// sqflite opens every connection with foreign keys OFF. Without this the
// ON DELETE CASCADE clauses below never fire and deleting a book leaves
// orphaned progress, bookmark and cache rows behind.
Future<void> _onConfigure(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
}

Future<void> _onCreate(Database db, int version) async {
  await db.execute('''
    CREATE TABLE books (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      title          TEXT NOT NULL,
      author         TEXT NOT NULL,
      language       TEXT NOT NULL DEFAULT 'es',
      file_path      TEXT NOT NULL UNIQUE,
      added_at       TEXT NOT NULL DEFAULT (datetime('now')),
      cover_path     TEXT,
      description    TEXT,
      publisher      TEXT,
      published_date TEXT,
      subject        TEXT,
      total_paragraphs INTEGER NOT NULL DEFAULT 0
    )
  ''');

  await db.execute('''
    CREATE TABLE reading_progress (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id         INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      chapter_index   INTEGER NOT NULL DEFAULT 0,
      paragraph_index INTEGER NOT NULL DEFAULT 0,
      sentence_index  INTEGER NOT NULL DEFAULT 0,
      offset_ms       INTEGER NOT NULL DEFAULT 0,
      global_index    INTEGER NOT NULL DEFAULT 0,
      updated_at      TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(book_id)
    )
  ''');

  await db.execute('''
    CREATE TABLE bookmarks (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id         INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      chapter_index   INTEGER NOT NULL,
      paragraph_index INTEGER NOT NULL,
      sentence_index  INTEGER NOT NULL DEFAULT 0,
      note            TEXT,
      created_at      TEXT NOT NULL DEFAULT (datetime('now'))
    )
  ''');

  await db.execute('''
    CREATE TABLE audio_cache (
      id             INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id        INTEGER NOT NULL,
      chapter_idx    INTEGER NOT NULL,
      para_idx       INTEGER NOT NULL,
      voice_id       TEXT NOT NULL,
      speed_hash     TEXT NOT NULL,
      file_path      TEXT NOT NULL UNIQUE,
      file_size_kb   INTEGER NOT NULL,
      pinned         INTEGER NOT NULL DEFAULT 0,
      created_at     TEXT NOT NULL DEFAULT (datetime('now')),
      last_accessed  TEXT NOT NULL DEFAULT (datetime('now'))
    )
  ''');
}

Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    await db.execute(
        'ALTER TABLE audio_cache ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0');
  }
  if (oldVersion < 3) {
    await db.execute(
        'ALTER TABLE bookmarks ADD COLUMN sentence_index INTEGER NOT NULL DEFAULT 0');
  }
  if (oldVersion < 4) {
    await db.execute('ALTER TABLE books ADD COLUMN cover_path TEXT');
    await db.execute('ALTER TABLE books ADD COLUMN description TEXT');
    await db.execute('ALTER TABLE books ADD COLUMN publisher TEXT');
    await db.execute('ALTER TABLE books ADD COLUMN published_date TEXT');
    await db.execute('ALTER TABLE books ADD COLUMN subject TEXT');
  }
  if (oldVersion < 5) {
    // Sentence + millisecond resume, so reopening a book no longer restarts
    // the current paragraph from zero.
    await db.execute(
        'ALTER TABLE reading_progress ADD COLUMN sentence_index INTEGER NOT NULL DEFAULT 0');
    await db.execute(
        'ALTER TABLE reading_progress ADD COLUMN offset_ms INTEGER NOT NULL DEFAULT 0');
    // Clean up rows orphaned before foreign keys were enforced.
    await db.execute(
        'DELETE FROM reading_progress WHERE book_id NOT IN (SELECT id FROM books)');
    await db.execute(
        'DELETE FROM bookmarks WHERE book_id NOT IN (SELECT id FROM books)');
    await db.execute(
        'DELETE FROM audio_cache WHERE book_id NOT IN (SELECT id FROM books)');
  }
  if (oldVersion < 6) {
    // Absolute paragraph position + book length, so the library can show a
    // progress bar without re-parsing every EPUB. Backfilled the first time
    // each book is opened.
    await db.execute(
        'ALTER TABLE books ADD COLUMN total_paragraphs INTEGER NOT NULL DEFAULT 0');
    await db.execute(
        'ALTER TABLE reading_progress ADD COLUMN global_index INTEGER NOT NULL DEFAULT 0');
  }
}
