import 'package:flutter_test/flutter_test.dart';
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
}
