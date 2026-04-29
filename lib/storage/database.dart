import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

Database? _db;

Future<Database> getDatabase() async {
  if (_db != null) return _db!;
  final dbPath = await getDatabasesPath();
  _db = await openDatabase(
    join(dbPath, 'voicex.db'),
    version: 1,
    onCreate: _onCreate,
  );
  return _db!;
}

Future<void> _onCreate(Database db, int version) async {
  await db.execute('''
    CREATE TABLE books (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      title       TEXT NOT NULL,
      author      TEXT NOT NULL,
      language    TEXT NOT NULL DEFAULT 'es',
      file_path   TEXT NOT NULL UNIQUE,
      added_at    TEXT NOT NULL DEFAULT (datetime('now'))
    )
  ''');

  await db.execute('''
    CREATE TABLE reading_progress (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      book_id         INTEGER NOT NULL REFERENCES books(id) ON DELETE CASCADE,
      chapter_index   INTEGER NOT NULL DEFAULT 0,
      paragraph_index INTEGER NOT NULL DEFAULT 0,
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
      created_at     TEXT NOT NULL DEFAULT (datetime('now')),
      last_accessed  TEXT NOT NULL DEFAULT (datetime('now'))
    )
  ''');
}
