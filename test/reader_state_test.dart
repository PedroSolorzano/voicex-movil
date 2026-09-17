import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/epub/models.dart';
import 'package:voicex_movil/ui/providers/reader_provider.dart';

/// El temporizador de apagado guarda un instante, y "apagarlo" es ponerlo a
/// null. Con `sleepAt ?? this.sleepAt` eso sería indistinguible de "no lo
/// toques", así que apagar el temporizador no habría apagado nada.
void main() {
  group('ReaderState.copyWith y el temporizador', () {
    final conTemporizador = const ReaderState()
        .copyWith(sleepAt: DateTime(2026, 9, 17, 23, 30));

    test('omitirlo lo conserva', () {
      final despues = conTemporizador.copyWith(statusMessage: 'otra cosa');

      expect(despues.sleepAt, DateTime(2026, 9, 17, 23, 30));
    });

    test('pasar null también lo conserva, que es lo que significa omitirlo', () {
      final despues = conTemporizador.copyWith(sleepAt: null);

      expect(despues.sleepAt, isNotNull);
    });

    test('clearSleepAt es lo único que lo apaga', () {
      final despues = conTemporizador.copyWith(clearSleepAt: true);

      expect(despues.sleepAt, isNull);
    });

    test('"al final del capítulo" es un modo aparte, no un instante', () {
      final despues = const ReaderState().copyWith(sleepAtChapterEnd: true);

      expect(despues.sleepAtChapterEnd, isTrue);
      expect(despues.sleepAt, isNull);
    });

    test('un estado nuevo nace sin temporizador', () {
      expect(const ReaderState().sleepAt, isNull);
      expect(const ReaderState().sleepAtChapterEnd, isFalse);
    });
  });

  group('buildCharsPrefix', () {
    // Lo que sostiene "faltan ~41 min" sin recorrer el resto del libro en
    // cada palabra resaltada.
    Book libro(List<List<String>> capitulos) => Book(
          title: 'Prueba',
          author: 'Nadie',
          language: 'es',
          filePath: '/tmp/prueba.epub',
          chapters: [
            for (var c = 0; c < capitulos.length; c++)
              Chapter(
                title: 'Cap $c',
                index: c,
                paragraphs: [
                  for (var p = 0; p < capitulos[c].length; p++)
                    Paragraph(
                        rawText: capitulos[c][p],
                        sentences: const [],
                        index: p),
                ],
              ),
          ],
        );

    test('empieza en cero y termina en el total', () {
      final prefix = buildCharsPrefix(libro([
        ['abc', 'de'],
        ['fghi'],
      ]));

      expect(prefix.first, 0);
      expect(prefix.last, 9);
    });

    test('tiene una entrada por párrafo, más el total', () {
      final prefix = buildCharsPrefix(libro([
        ['abc', 'de'],
        ['fghi'],
      ]));

      expect(prefix.length, 4);
    });

    test('lo que falta desde un párrafo es una resta', () {
      final prefix = buildCharsPrefix(libro([
        ['abc', 'de'],
        ['fghi'],
      ]));

      // Desde el segundo párrafo quedan 'de' y 'fghi'.
      expect(prefix.last - prefix[1], 6);
    });

    test('atraviesa los capítulos, no los cuenta por separado', () {
      final prefix = buildCharsPrefix(libro([
        ['abc'],
        ['de'],
        ['f'],
      ]));

      expect(prefix, [0, 3, 5, 6]);
    });

    test('un libro sin capítulos da solo el cero', () {
      expect(buildCharsPrefix(libro([])), [0]);
    });
  });
}
