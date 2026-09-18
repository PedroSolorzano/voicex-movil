import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicex_movil/config/settings.dart';
import 'package:voicex_movil/storage/database.dart';
import 'package:voicex_movil/storage/repositories.dart';

void main() {
  late ReadingLogRepo repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await useDatabaseAt(inMemoryDatabasePath);
    final db = await getDatabase();
    await db.delete('reading_days');
    await db.delete('books');
    await db.insert('books', {
      'id': 1,
      'title': 'El talismán',
      'author': 'Stephen King, Peter Straub',
      'file_path': '/tmp/talisman.epub',
      'language': 'es',
      'total_paragraphs': 3000,
    });
    repo = ReadingLogRepo();
  });

  group('el registro diario', () {
    test('el mismo día suma, leído y escuchado por separado', () async {
      await repo.credit('2026-09-17', readChars: 900, paragraphs: 2);
      await repo.credit('2026-09-17', listenedChars: 1800, paragraphs: 3);

      final t = await repo.totals();
      expect(t.readChars, 900);
      expect(t.listenedChars, 1800);
      expect(t.paragraphs, 5);
    });

    test('días distintos no se mezclan', () async {
      await repo.credit('2026-09-16', readChars: 100);
      await repo.credit('2026-09-17', readChars: 200);

      final days = await repo.lastDays(2, today: DateTime(2026, 9, 17));
      expect(days, [
        (day: '2026-09-16', chars: 100),
        (day: '2026-09-17', chars: 200),
      ]);
    });

    test('los días sin lectura están, con cero', () async {
      await repo.credit('2026-09-15', listenedChars: 500);

      final days = await repo.lastDays(7, today: DateTime(2026, 9, 17));
      expect(days, hasLength(7));
      expect(days.first.day, '2026-09-11');
      expect(days.last.day, '2026-09-17');
      expect(days.where((d) => d.chars > 0).single.day, '2026-09-15');
    });

    test('cruzar fin de mes no rompe los días', () async {
      final days = await repo.lastDays(3, today: DateTime(2026, 10, 1));
      expect(days.map((d) => d.day), ['2026-09-29', '2026-09-30', '2026-10-01']);
    });

    test('un crédito vacío no deja una fila', () async {
      await repo.credit('2026-09-17');
      expect(await repo.bestDay(), isNull);
    });

    test('el mejor día es el de más caracteres', () async {
      await repo.credit('2026-09-03', readChars: 9000);
      await repo.credit('2026-09-17', listenedChars: 4000);
      expect((await repo.bestDay())!.day, '2026-09-03');
    });
  });

  group('libros terminados', () {
    test('marcarlo dos veces no mueve la fecha', () async {
      final first = DateTime(2026, 9, 17, 22);
      expect(await repo.markFinished(1, first), isTrue);
      expect(await repo.markFinished(1, DateTime(2026, 9, 20)), isFalse);

      final done = (await repo.finishedBooks()).single;
      expect(done['title'], 'El talismán');
      expect(done['finished_at'], first.toIso8601String());
    });

    test('un libro terminado deja de ser el libro en curso', () async {
      final db = await getDatabase();
      await db.insert('reading_progress', {'book_id': 1, 'global_index': 800});
      expect((await repo.currentBook())!.at, 800);

      await repo.markFinished(1, DateTime(2026, 9, 17));
      expect(await repo.currentBook(), isNull);
    });

    test('un libro sin abrir no es el libro en curso', () async {
      final db = await getDatabase();
      await db.insert('reading_progress', {'book_id': 1, 'global_index': 0});
      expect(await repo.currentBook(), isNull);
    });
  });

  test('la migración de v8 a v9 conserva los libros y agrega el registro',
      () async {
    final dir = await Directory.systemTemp.createTemp('voicex_mig_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/v8.db';

    // Lo mínimo de un esquema v8: la tabla que la migración toca.
    final old = await databaseFactoryFfi.openDatabase(path,
        options: OpenDatabaseOptions(
          version: 8,
          onCreate: (db, _) => db.execute('''
            CREATE TABLE books (
              id INTEGER PRIMARY KEY, title TEXT NOT NULL, author TEXT,
              language TEXT, file_path TEXT, total_paragraphs INTEGER
            )'''),
        ));
    await old.insert('books', {'id': 7, 'title': 'La Odisea'});
    await old.close();

    await useDatabaseAt(path);
    final db = await getDatabase();

    expect((await db.query('books')).single['title'], 'La Odisea');
    expect((await db.query('books')).single['finished_at'], isNull);
    await ReadingLogRepo().credit('2026-09-17', readChars: 1);
    expect((await ReadingLogRepo().totals()).readChars, 1);
    await useDatabaseAt(inMemoryDatabasePath);
  });

  group('ajustes de rango y avisos', () {
    test('por defecto: rango visible, avisos apagados', () async {
      SharedPreferences.setMockInitialValues({});
      final s = await AppSettings.load();
      expect(s.showReaderRank, isTrue);
      expect(s.weeklySummary, isFalse);
      expect(s.dailyReminderAt, '');
    });

    test('se guardan y se vuelven a leer', () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings()
          .copyWith(
              showReaderRank: false,
              weeklySummary: true,
              dailyReminderAt: '21:30')
          .save();
      final s = await AppSettings.load();
      expect(s.showReaderRank, isFalse);
      expect(s.weeklySummary, isTrue);
      expect(s.dailyReminderAt, '21:30');
    });
  });
}
