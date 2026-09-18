import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/ui/providers/reading_stats_provider.dart';
import 'package:voicex_movil/ui/widgets/book_tower.dart';
import 'package:voicex_movil/ui/widgets/library_skin.dart';
import 'package:voicex_movil/ui/widgets/rank_header.dart';

const _stats = ReadingStats(
  // 250 páginas: nivel 4, Lector asiduo.
  readChars: 1800 * 150,
  listenedChars: 1800 * 100,
  lastFourteen: [],
  bestDay: null,
  finished: [
    {'title': 'El talismán', 'total_paragraphs': 3000},
    {'title': "Alice's Adventures in Wonderland", 'total_paragraphs': 800},
  ],
  current: (title: '22/11/63', totalParagraphs: 4000, at: 1000),
);

Future<void> _pump(WidgetTester tester, LibrarySkin skin, Widget child) =>
    tester.pumpWidget(MaterialApp(
      theme: libraryThemeData(skin, ThemeData()),
      home: Scaffold(body: ListView(children: [child])),
    ));

void main() {
  for (final skin in [
    LibrarySkin.modern,
    LibrarySkin.catalog,
    LibrarySkin.classic
  ]) {
    group('cabecera en la piel ${skin.name}', () {
      testWidgets('dice rango, nivel, páginas y libros', (tester) async {
        await _pump(tester, skin,
            RankHeader(stats: _stats, skin: skin, onTap: () {}));
        expect(find.text('Lector asiduo  ·  Nivel 4'), findsOneWidget);
        expect(find.text('250 páginas  ·  2 libros'), findsOneWidget);
        expect(find.text('Faltan 150 para Devorador de libros'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('tocarla abre el progreso', (tester) async {
        var abierto = false;
        await _pump(tester, skin,
            RankHeader(stats: _stats, skin: skin, onTap: () => abierto = true));
        await tester.tap(find.byType(RankHeader));
        expect(abierto, isTrue);
      });
    });
  }

  testWidgets('sin libros terminados no dice "0 libros"', (tester) async {
    await _pump(
        tester,
        LibrarySkin.modern,
        RankHeader(
            stats: ReadingStats.empty,
            skin: LibrarySkin.modern,
            onTap: () {}));
    expect(find.text('0 páginas'), findsOneWidget);
    expect(find.textContaining('libro'), findsNothing);
  });

  group('la torre', () {
    testWidgets('un lomo por libro terminado y el libro en curso encima',
        (tester) async {
      await _pump(
          tester,
          LibrarySkin.classic,
          const BookTower(
            finished: [
              {'title': 'El talismán', 'total_paragraphs': 3000},
              {'title': 'Pedro Páramo', 'total_paragraphs': 400},
            ],
            current: (title: '22/11/63', totalParagraphs: 4000, at: 1000),
            skin: LibrarySkin.classic,
          ));
      expect(find.text('El talismán'), findsOneWidget);
      expect(find.text('Pedro Páramo'), findsOneWidget);
      expect(find.text('En curso: 22/11/63'), findsOneWidget);
      expect(find.byType(Opacity), findsOneWidget);
    });

    testWidgets('vacía, lo dice en vez de dibujar nada', (tester) async {
      await _pump(
          tester,
          LibrarySkin.modern,
          const BookTower(
              finished: [], current: null, skin: LibrarySkin.modern));
      expect(find.textContaining('se irán apilando'), findsOneWidget);
    });

    testWidgets('con muchos, se corta y dice cuántos quedan', (tester) async {
      await _pump(
          tester,
          LibrarySkin.modern,
          BookTower(
            finished: [
              for (var i = 0; i < BookTower.maxSpines + 3; i++)
                {'title': 'Libro $i', 'total_paragraphs': 500},
            ],
            current: null,
            skin: LibrarySkin.modern,
          ));
      expect(find.text('y 3 más debajo'), findsOneWidget);
      expect(find.text('Libro 14'), findsNothing);
    });
  });
}
