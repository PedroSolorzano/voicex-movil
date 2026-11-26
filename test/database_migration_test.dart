import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicex_movil/storage/database.dart';

/// A phone that updates the app keeps its database: the upgrade path is what
/// runs there, not the fresh `CREATE TABLE`.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('a v9 database keeps its queued reports and learns body_sent',
      () async {
    final dir = await Directory.systemTemp.createTemp('voicex_mig');
    final path = '${dir.path}/v9.db';
    // The reports table exactly as version 9 created it.
    final old = await databaseFactory.openDatabase(path,
        options: OpenDatabaseOptions(
            version: 9,
            onCreate: (db, _) async {
              await db.execute('''
                CREATE TABLE reports (
                  id          INTEGER PRIMARY KEY AUTOINCREMENT,
                  body        TEXT NOT NULL,
                  audio_path  TEXT,
                  created_at  TEXT NOT NULL DEFAULT (datetime('now')),
                  attempts    INTEGER NOT NULL DEFAULT 0
                )''');
              await db.insert('reports', {'body': '{}', 'audio_path': 'n.m4a'});
            }));
    await old.close();

    await useDatabaseAt(path);
    final rows = await (await getDatabase()).query('reports');

    expect(rows.single['audio_path'], 'n.m4a');
    expect(rows.single['body_sent'], 0);
    await useDatabaseAt(inMemoryDatabasePath);
    await dir.delete(recursive: true);
  });
}
