import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicex_movil/epub/models.dart';
import 'package:voicex_movil/storage/database.dart';
import 'package:voicex_movil/storage/repositories.dart';
import 'package:voicex_movil/ui/screens/book_downloads_screen.dart';
import 'package:voicex_movil/ui/screens/downloads_screen.dart';

/// The screens that answer "which book is using my 107 MB?" and delete part of
/// it. They run against a real in-memory database: the queries are the point.
void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await useDatabaseAt(inMemoryDatabasePath);
    tmp = await Directory.systemTemp.createTemp('voicex_screen_test');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

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

  Future<void> addAudio(int book, int chapter, int para, String voice,
      {bool pinned = true, int kb = 100}) async {
    final db = await getDatabase();
    await db.insert('audio_cache', {
      'book_id': book,
      'chapter_idx': chapter,
      'para_idx': para,
      'voice_id': voice,
      'speed_hash': 'f96',
      'file_path': '${tmp.path}/${book}_${chapter}_${para}_$voice.mp3',
      'file_size_kb': kb,
      'pinned': pinned ? 1 : 0,
    });
  }

  /// Runs database work in real time. Inside a widget test the clock is fake,
  /// and a query awaited there never completes: that is what hung the first
  /// version of these tests.
  Future<void> db(WidgetTester tester, Future<void> Function() body) async {
    await tester.runAsync(body);
  }

  /// DB work does not complete inside the fake clock of a widget test, so it
  /// gets real time to finish before the frame is pumped. The first call also
  /// opens the database, which takes longer than any later one: wait until the
  /// loading spinner is gone, with a ceiling so a real hang fails instead of
  /// stalling the run.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      if (i >= 7 && find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Waits until [done] holds, in small real-time slices.
  ///
  /// A delete followed by a reload is a chain of awaits, and each one only
  /// advances when the real clock gets to run: a fixed wait either cuts the
  /// chain short or pads every test. Polling for the outcome does neither.
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 400 && !done(); i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 15)));
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// Lets a dialog or a route transition finish. Not `pumpAndSettle`: a spinner
  /// still on screen would keep it waiting forever.
  Future<void> frames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// The two screens behind the routes the app uses, so navigation between them
  /// is the real one.
  Future<void> pumpApp(WidgetTester tester, {String start = '/'}) async {
    final router = GoRouter(initialLocation: start, routes: [
      GoRoute(
          path: '/',
          builder: (_, _) => DownloadsScreen(audioDirs: () async => [tmp])),
      GoRoute(
        path: '/downloads/:bookId',
        builder: (_, state) => BookDownloadsScreen(
          bookId: int.parse(state.pathParameters['bookId']!),
          loadBook: (_) async => Book(
            title: 'Visión ciega',
            author: 'Peter Watts',
            language: 'es',
            filePath: '/1.epub',
            chapters: [
              for (final t in ['Prólogo', 'Teseo', 'Rorschach'])
                Chapter(
                  title: t,
                  index: ['Prólogo', 'Teseo', 'Rorschach'].indexOf(t),
                  paragraphs: [
                    for (var i = 0; i < 10; i++)
                      Paragraph(rawText: 'p$i', sentences: const [], index: i)
                  ],
                ),
            ],
          ),
        ),
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await settle(tester);
  }

  testWidgets('empty: says so instead of showing a blank list', (tester) async {
    await pumpApp(tester);

    expect(find.text('No hay audio guardado.'), findsOneWidget);
    expect(find.text('0 KB'), findsWidgets);
  });

  testWidgets('lists every book with its size, engine and voice',
      (tester) async {
    await db(tester, () async {
      await addBook(1, 'Visión ciega');
      await addBook(2, 'El talismán');
      await addAudio(1, 0, 0, 'qwen3-esposa', kb: 3000);
      await addAudio(2, 0, 0, 'edge-es-MX-DaliaNeural', kb: 500);
    });

    await pumpApp(tester);

    expect(find.text('Visión ciega'), findsOneWidget);
    expect(find.text('El talismán'), findsOneWidget);
    expect(find.textContaining('Qwen3 · esposa'), findsOneWidget);
    expect(find.textContaining('Edge · es-MX-DaliaNeural'), findsOneWidget);
    // The headline is the sum of what the list shows: 3500 KB.
    expect(find.text('3.4 MB'), findsWidgets);
    expect(find.text('Se puede liberar sin perder nada'), findsNothing);
  });

  testWidgets('shows the audio of a deleted book and frees it on request',
      (tester) async {
    await db(tester, () async {
      await addBook(1, 'Visión ciega');
      await addAudio(1, 0, 0, 'qwen3-esposa', kb: 1000);
      await addAudio(7, 0, 0, 'qwen3-esposa', kb: 8000); // book no longer there
    });

    await pumpApp(tester);

    expect(find.text('Libro eliminado de la biblioteca'), findsOneWidget);
    expect(find.text('Libros que ya no están en tu biblioteca'),
        findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Liberar'));
    await frames(tester);
    expect(find.textContaining('nadie puede reproducirlo'.toLowerCase()),
        findsNothing); // dialog text starts with a capital
    await tester.tap(find.widgetWithText(TextButton, 'Borrar'));
    await settleUntil(tester, () => find.text('Libro eliminado de la biblioteca').evaluate().isEmpty);

    expect(find.text('Libro eliminado de la biblioteca'), findsNothing);
    expect(find.text('Visión ciega'), findsOneWidget);
    expect((await tester.runAsync(() => AudioCacheRepo().usageByBook()))!.length,
        1);
  });

  testWidgets('flags audio from a retired engine in a book that still exists',
      (tester) async {
    await db(tester, () async {
      await addBook(1, 'Visión ciega');
      await addAudio(1, 0, 0, 'qwen3-esposa', kb: 100);
      await addAudio(1, 1, 0, 'kokoro-af_bella', kb: 5000);
    });

    await pumpApp(tester);

    expect(find.text('Motores que la app ya no tiene'), findsOneWidget);
    expect(find.textContaining('Motor retirado (kokoro)'), findsOneWidget);
  });

  testWidgets('borrar todo empties the phone, files included', (tester) async {
    await db(tester, () async {
      await addBook(1, 'Visión ciega');
      await addAudio(1, 0, 0, 'qwen3-esposa', kb: 100);
    });
    final stray = File('${tmp.path}/9_0_0_x_f96.mp3')
      ..writeAsBytesSync(List.filled(2048, 1));

    await pumpApp(tester);
    expect(find.text('Archivos sin registro'), findsWidgets);

    await tester.scrollUntilVisible(find.textContaining('Borrar todo ('), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.textContaining('Borrar todo ('));
    await frames(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Borrar todo'));
    await settleUntil(
        tester, () => find.text('No hay audio guardado.').evaluate().isNotEmpty);

    expect(find.text('No hay audio guardado.'), findsOneWidget);
    expect(stray.existsSync(), isFalse);
  });

  testWidgets('does not overflow on a small phone screen', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await db(tester, () async {
      await addBook(1, 'Un libro con un título bastante largo que no cabe en una línea');
      await addAudio(1, 0, 0, 'qwen3-esposa', kb: 3000);
      await addAudio(1, 0, 1, 'chatterbox2-colombiana', kb: 3000);
      await addAudio(1, 0, 2, 'edge-es-MX-DaliaNeural', kb: 3000);
      await addAudio(1, 0, 3, 'kokoro-af_bella', kb: 3000);
      await addAudio(7, 0, 0, 'qwen3-esposa', kb: 8000);
    });

    await pumpApp(tester);

    expect(tester.takeException(), isNull);
  });

  group('per book', () {
    Future<void> seed() async {
      await addBook(1, 'Visión ciega');
      // Reading position: chapter 1 (Teseo), paragraph 4.
      await ProgressRepo().save(1, 1, 4);
      // Prólogo whole, Teseo's first 6 paragraphs, Rorschach's first 2.
      for (var p = 0; p < 10; p++) {
        await addAudio(1, 0, p, 'qwen3-esposa', kb: 100);
      }
      for (var p = 0; p < 6; p++) {
        await addAudio(1, 1, p, 'qwen3-esposa', kb: 100);
      }
      for (var p = 0; p < 2; p++) {
        await addAudio(1, 2, p, 'qwen3-esposa', kb: 100);
      }
    }

    testWidgets('lists the chapters with titles and where you are',
        (tester) async {
      await db(tester, seed);

      await pumpApp(tester, start: '/downloads/1');

      expect(find.text('Prólogo'), findsOneWidget);
      expect(find.text('Teseo'), findsOneWidget);
      expect(find.text('Rorschach'), findsOneWidget);
      expect(find.textContaining('6 de 10 párrafos'), findsOneWidget);
      expect(find.textContaining('vas por aquí'), findsOneWidget,
          reason: 'only the chapter in progress is marked');
    });

    testWidgets('says what "borrar lo anterior" frees before it does it',
        (tester) async {
      await db(tester, seed);

      await pumpApp(tester, start: '/downloads/1');

      // Prólogo (10) + Teseo paragraphs 0..3 (4) = 14 paragraphs, 1400 KB.
      expect(find.textContaining('Libera 1.4 MB (14 párrafos)'), findsOneWidget);
    });

    testWidgets('borrar lo anterior keeps the position and what follows',
        (tester) async {
      await db(tester, seed);
      await pumpApp(tester, start: '/downloads/1');

      await tester.tap(find.text('Borrar lo anterior a mi posición'));
      await frames(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Borrar'));
      await settleUntil(tester, () => find.text('Prólogo').evaluate().isEmpty);

      final left = (await tester.runAsync(
          () => AudioCacheRepo().usageByChapter(1)))!;
      expect(left.map((c) => (c.chapter, c.paragraphs)), [(1, 2), (2, 2)],
          reason: 'Teseo keeps paragraphs 4 and 5; Rorschach is untouched');
      expect(find.text('Prólogo'), findsNothing);
      expect(find.text('No hay audio antes de donde vas', skipOffstage: false),
          findsNothing);
    });

    testWidgets('a chapter can be deleted on its own', (tester) async {
      await db(tester, seed);
      await pumpApp(tester, start: '/downloads/1');

      await tester.tap(find.byTooltip('Borrar Teseo'));
      await frames(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Borrar'));
      await settleUntil(tester, () => find.text('Teseo').evaluate().isEmpty);

      final left = (await tester.runAsync(
          () => AudioCacheRepo().usageByChapter(1)))!;
      expect(left.map((c) => c.chapter), [0, 2]);
    });

    testWidgets('cancelling a delete keeps everything', (tester) async {
      await db(tester, seed);
      await pumpApp(tester, start: '/downloads/1');

      await tester.tap(find.byTooltip('Borrar Teseo'));
      await frames(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
      await settle(tester);

      final left = (await tester.runAsync(
          () => AudioCacheRepo().usageByChapter(1)))!;
      expect(left, hasLength(3));
    });

    testWidgets('navigates from the global list into a book', (tester) async {
      await db(tester, seed);
      await pumpApp(tester);

      await tester.tap(find.text('Visión ciega'));
      await settle(tester);

      expect(find.text('Descargas del libro'), findsOneWidget);
      expect(find.text('Teseo'), findsOneWidget);
    });

    testWidgets('a book with no audio says so', (tester) async {
      await db(tester, () async {
        await addBook(1, 'Visión ciega');
      });

      await pumpApp(tester, start: '/downloads/1');

      expect(find.text('Este libro no tiene audio guardado.'), findsOneWidget);
    });

    testWidgets('falls back to "Capítulo N" when the book cannot be read',
        (tester) async {
      await db(tester, seed);
      final router = GoRouter(initialLocation: '/', routes: [
        GoRoute(
          path: '/',
          builder: (_, _) =>
              BookDownloadsScreen(bookId: 1, loadBook: (_) async => null),
        ),
      ]);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await settle(tester);

      expect(find.text('Capítulo 2'), findsOneWidget);
    });
  });
}
