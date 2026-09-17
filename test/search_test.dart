import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/epub/models.dart';
import 'package:voicex_movil/epub/search.dart';

Paragraph _p(String text, int index) =>
    Paragraph(rawText: text, sentences: const [], index: index);

Book _book(List<List<String>> chapters) => Book(
      title: 'Prueba',
      author: 'Nadie',
      language: 'es',
      filePath: '/tmp/prueba.epub',
      chapters: [
        for (var c = 0; c < chapters.length; c++)
          Chapter(
            title: 'Capítulo ${c + 1}',
            index: c,
            paragraphs: [
              for (var p = 0; p < chapters[c].length; p++)
                _p(chapters[c][p], p),
            ],
          ),
      ],
    );

void main() {
  group('searchBook', () {
    test('encuentra sin distinguir mayúsculas', () {
      final hits = _book([
        ['El Árbol estaba seco.']
      ]);

      expect(searchBook(hits, 'árbol').length, 1);
      expect(searchBook(hits, 'ÁRBOL').length, 1);
    });

    test('una consulta sin tildes encuentra el texto con tildes', () {
      // El caso que importa en un teléfono: nadie escribe la tilde al buscar.
      final book = _book([
        ['El árbol estaba seco.']
      ]);

      expect(searchBook(book, 'arbol').length, 1);
    });

    test('y al revés: con tilde encuentra lo que no la lleva', () {
      final book = _book([
        ['El arbol estaba seco.']
      ]);

      expect(searchBook(book, 'árbol').length, 1);
    });

    test('la eñe no se pliega, porque es otra letra', () {
      // Plegarla haría que "año" saliera al buscar "ano".
      final book = _book([
        ['Pasó un año entero.']
      ]);

      expect(searchBook(book, 'ano'), isEmpty);
      expect(searchBook(book, 'año').length, 1);
    });

    test('señala dónde está la coincidencia dentro del fragmento', () {
      final book = _book([
        ['El árbol estaba seco.']
      ]);

      final hit = searchBook(book, 'arbol').single;

      expect(hit.snippet.substring(hit.matchStart, hit.matchEnd), 'árbol');
    });

    test('dice en qué capítulo y párrafo, para poder saltar ahí', () {
      final book = _book([
        ['nada aquí'],
        ['tampoco', 'aquí sí: ballena'],
      ]);

      final hit = searchBook(book, 'ballena').single;

      expect(hit.chapterIndex, 1);
      expect(hit.paragraphIndex, 1);
    });

    test('encuentra varias veces en el mismo párrafo', () {
      final book = _book([
        ['mar y mar y mar']
      ]);

      expect(searchBook(book, 'mar').length, 3);
    });

    test('una consulta de una letra no devuelve nada', () {
      final book = _book([
        ['a a a a a']
      ]);

      expect(searchBook(book, 'a'), isEmpty);
    });

    test('los espacios sueltos no cuentan como consulta', () {
      final book = _book([
        ['algo que buscar']
      ]);

      expect(searchBook(book, '   '), isEmpty);
    });

    test('el tope corta antes de construir miles de filas', () {
      final book = _book([
        [List.filled(50, 'mar').join(' ')]
      ]);

      expect(searchBook(book, 'mar', limit: 10).length, 10);
    });

    test('el fragmento recorta y avisa con puntos suspensivos', () {
      final book = _book([
        ['${'x' * 200} ballena ${'y' * 200}']
      ]);

      final hit = searchBook(book, 'ballena').single;

      expect(hit.snippet.length, lessThan(120));
      expect(hit.snippet, startsWith('…'));
      expect(hit.snippet, endsWith('…'));
    });
  });
}
