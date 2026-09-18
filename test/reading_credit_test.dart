import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/stats/reading_credit.dart';

/// Las reglas que hacen que un rango signifique algo: suma leer y escuchar,
/// no suma saltar.
void main() {
  // Diez párrafos de 500 caracteres: prefix[i] = 500 * i.
  final prefix = [for (var i = 0; i <= 10; i++) i * 500];
  final t0 = DateTime(2026, 9, 17, 22);

  group('escuchar', () {
    test('un párrafo que terminó de sonar cuenta entero', () {
      final credit = ReadingCredit(prefix).listened(3, t0);
      expect(credit.chars, 500);
      expect(credit.finished, isFalse);
    });

    test('el último párrafo termina el libro', () {
      expect(ReadingCredit(prefix).listened(9, t0).finished, isTrue);
    });

    test('un índice fuera del libro no suma', () {
      expect(ReadingCredit(prefix).listened(10, t0).chars, 0);
      expect(ReadingCredit(prefix).listened(-1, t0).chars, 0);
    });
  });

  group('leer en silencio', () {
    test('avanzar 1, 2 o 3 párrafos cuenta los que se pasaron', () {
      expect(ReadingCredit(prefix).read(2, 3, t0).chars, 500);
      expect(ReadingCredit(prefix).read(2, 4, t0).chars, 1000);
      expect(ReadingCredit(prefix).read(2, 5, t0).chars, 1500);
    });

    test('4 o más de golpe es arrastrar el dedo, no leer', () {
      expect(ReadingCredit(prefix).read(2, 6, t0).chars, 0);
      expect(ReadingCredit(prefix).read(0, 9, t0).chars, 0);
    });

    test('volver atrás ni suma ni resta', () {
      expect(ReadingCredit(prefix).read(5, 4, t0).chars, 0);
      expect(ReadingCredit(prefix).read(5, 5, t0).chars, 0);
    });

    test('a una página del final el libro queda terminado, con lo que falta',
        () {
      // Del 7 al 8 quedan 1.000 caracteres (8 y 9), menos de una página: se
      // ven en pantalla y cuentan.
      final credit = ReadingCredit(prefix).read(7, 8, t0);
      expect(credit.finished, isTrue);
      expect(credit.chars, 1500);
    });

    test('lejos del final no se da por terminado', () {
      expect(ReadingCredit(prefix).read(2, 3, t0).finished, isFalse);
    });
  });

  group('tope de ritmo', () {
    // Párrafos enormes, para llegar al tope en pocos pasos.
    final big = [for (var i = 0; i <= 40; i++) i * 2500];

    test('no más de 6.000 caracteres por minuto', () {
      final credit = ReadingCredit(big);
      final a = credit.listened(0, t0).chars;
      final b = credit.listened(1, t0.add(const Duration(seconds: 10))).chars;
      final c = credit.listened(2, t0.add(const Duration(seconds: 20))).chars;
      expect(a + b + c, ReadingCredit.maxCharsPerMinute);
      expect(c, 1000);
    });

    test('pasado el minuto vuelve a acreditar', () {
      final credit = ReadingCredit(big);
      credit.listened(0, t0);
      credit.listened(1, t0);
      credit.listened(2, t0);
      final later = credit.listened(3, t0.add(const Duration(seconds: 61)));
      expect(later.chars, 2500);
    });

    test('lo que el tope descarta no se cobra en la ventana', () {
      final credit = ReadingCredit(big);
      credit.listened(0, t0); // 2.500
      credit.listened(1, t0); // 2.500
      credit.listened(2, t0); // 1.000 de 2.500
      expect(credit.listened(3, t0).chars, 0);
    });
  });
}
