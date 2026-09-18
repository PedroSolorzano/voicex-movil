import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/stats/quotes.dart';
import 'package:voicex_movil/stats/reader_rank.dart';
import 'package:voicex_movil/stats/tangible.dart';

void main() {
  group('rangos', () {
    test('los umbrales son los de la tabla', () {
      expect([for (var n = 1; n <= 10; n++) ReaderRank.threshold(n)],
          [0, 40, 120, 240, 400, 600, 840, 1120, 1440, 1800]);
    });

    test('suben siempre', () {
      for (var n = 1; n < 40; n++) {
        expect(ReaderRank.threshold(n + 1), greaterThan(ReaderRank.threshold(n)));
      }
    });

    test('1.800 caracteres son una página', () {
      expect(ReaderRank.pagesOf(1800), 1);
      expect(ReaderRank.pagesOf(0), 0);
    });

    test('el nivel cambia justo en el umbral', () {
      expect(ReaderRank.levelFor(0), 1);
      expect(ReaderRank.levelFor(39.9), 1);
      expect(ReaderRank.levelFor(40), 2);
      expect(ReaderRank.levelFor(600), 6);
      expect(ReaderRank.titleFor(6), 'Ratón de biblioteca');
    });

    test('pasado el décimo, maestro con número romano', () {
      expect(ReaderRank.titleFor(10), 'Maestro bibliotecario');
      expect(ReaderRank.titleFor(11), 'Maestro bibliotecario II');
      expect(ReaderRank.titleFor(14), 'Maestro bibliotecario V');
      expect(ReaderRank.titleFor(19), 'Maestro bibliotecario X');
    });

    test('el progreso al siguiente va de 0 a 1', () {
      expect(ReaderRank.progressToNext(40), 0);
      expect(ReaderRank.progressToNext(80), 0.5);
      for (var p = 0.0; p < 3000; p += 37) {
        expect(ReaderRank.progressToNext(p), inInclusiveRange(0, 1));
      }
    });
  });

  group('equivalencias', () {
    test('siempre un múltiplo entre la mitad y diez veces', () {
      for (var pages = 48.0; pages < 30000; pages *= 1.37) {
        for (var seed = 0; seed < 5; seed++) {
          final phrase = equivalence(pages, seed);
          expect(phrase, isNotNull, reason: '$pages páginas');
        }
      }
    });

    test('con muy poco leído no hay frase', () {
      expect(equivalence(0, 0), isNull);
      expect(equivalence(20, 3), isNull);
    });

    test('la misma semilla elige la misma obra', () {
      expect(equivalence(600, 4), equivalence(600, 4));
    });

    test('por debajo de una obra entera, en porcentaje', () {
      // 64 páginas solo caben en El principito (0,67) y Pedro Páramo (0,5).
      expect(equivalence(64, 0), 'Ya leíste el 67 % de «El principito»');
    });

    test('por encima, en veces, con coma decimal', () {
      expect(equivalence(1100 * 2.5, 0), contains('veces'));
      expect(equivalence(1100 * 2.5, 0), contains(','));
    });

    test('la pila de papel: 2.000 páginas son 10 cm', () {
      expect(stackHeightCm(2000), closeTo(10, 1e-9));
    });

    test('la cifra de referencia dice de dónde sale', () {
      expect(nationalReference.source, contains('INEGI'));
      expect(nationalReference.text, contains('62,5'));
    });
  });

  group('citas', () {
    test('la misma fecha da la misma cita, a cualquier hora', () {
      expect(quoteForDay(DateTime(2026, 9, 17, 0, 5)),
          quoteForDay(DateTime(2026, 9, 17, 23, 55)));
    });

    test('dos días seguidos dan citas distintas', () {
      for (var d = 1; d < 60; d++) {
        expect(quoteForDay(DateTime(2026, 1, d)),
            isNot(quoteForDay(DateTime(2026, 1, d + 1))));
      }
    });

    test('ninguna está vacía ni sin autor', () {
      for (final q in quotes) {
        expect(q.text.trim(), isNotEmpty);
        expect(q.author.trim(), isNotEmpty);
      }
    });
  });
}
