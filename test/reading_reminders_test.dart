import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/services/reading_reminders.dart';
import 'package:voicex_movil/storage/repositories.dart';
import 'package:voicex_movil/ui/providers/reading_stats_provider.dart';

/// Stats whose last fourteen days end on [today], with [pagesByOffset] pages
/// on the day that many days before it.
ReadingStats _stats(DateTime today, Map<int, double> pagesByOffset,
    {int totalChars = 0}) {
  return ReadingStats(
    readChars: totalChars,
    listenedChars: 0,
    lastFourteen: [
      for (var i = 13; i >= 0; i--)
        (
          day: ReadingLogRepo.dayOf(
              DateTime(today.year, today.month, today.day - i)),
          chars: ((pagesByOffset[i] ?? 0) * 1800).round(),
        ),
    ],
    bestDay: null,
    finished: const [],
    current: null,
  );
}

void main() {
  // Miércoles 16 de septiembre de 2026.
  final wednesday = DateTime(2026, 9, 16, 12);

  group('cuándo', () {
    test('el resumen es el próximo domingo a las 20:00', () {
      expect(nextWeeklySummary(wednesday), DateTime(2026, 9, 20, 20));
    });

    test('un domingo antes de las 20:00 es ese mismo día', () {
      expect(nextWeeklySummary(DateTime(2026, 9, 20, 9)),
          DateTime(2026, 9, 20, 20));
    });

    test('un domingo pasadas las 20:00 es el siguiente', () {
      expect(nextWeeklySummary(DateTime(2026, 9, 20, 21)),
          DateTime(2026, 9, 27, 20));
    });

    test('el recordatorio es hoy si la hora no pasó, si no mañana', () {
      expect(nextDaily(wednesday, '21:30'), DateTime(2026, 9, 16, 21, 30));
      expect(nextDaily(wednesday, '08:00'), DateTime(2026, 9, 17, 8));
    });
  });

  group('la semana es de lunes a domingo', () {
    test('cuenta desde el lunes, no los siete días anteriores', () {
      // El miércoles es el día 0; el lunes, el 2; el domingo pasado, el 3.
      final stats = _stats(wednesday, {0: 10, 2: 5, 3: 7, 9: 4});
      final weeks = calendarWeeks(stats, wednesday);
      expect(weeks.thisWeek, 15);
      expect(weeks.lastWeek, 11);
    });
  });

  group('el texto del resumen', () {
    test('sin lectura en la semana no hay resumen', () {
      expect(weeklySummaryText(_stats(wednesday, {5: 30}), wednesday), isNull);
    });

    test('más que la anterior: lo dice', () {
      final text =
          weeklySummaryText(_stats(wednesday, {0: 20, 5: 6}), wednesday)!;
      expect(text, contains('Esta semana: 20 páginas'));
      expect(text, contains('14 más que la anterior'));
    });

    test('menos que la anterior: no lo reprocha', () {
      final text =
          weeklySummaryText(_stats(wednesday, {0: 5, 5: 30}), wednesday)!;
      expect(text, contains('Esta semana: 5 páginas.'));
      expect(text, isNot(contains('menos')));
      expect(text, isNot(contains('anterior')));
    });

    test('la primera semana no se compara con nada', () {
      final text = weeklySummaryText(_stats(wednesday, {0: 12}), wednesday)!;
      expect(text, isNot(contains('anterior')));
    });

    test('lleva el rango y una cita', () {
      final text = weeklySummaryText(_stats(wednesday, {0: 12}), wednesday)!;
      expect(text, contains('Vas por'));
      expect(text, contains('«'));
    });
  });

  group('el recordatorio diario', () {
    test('antes de leer nada, invita sin cifras vacías', () {
      final text = dailyReminderText(ReadingStats.empty);
      expect(text, isNot(matches(RegExp(r'(^|\s)0 páginas'))));
      expect(text, contains('primer rango'));
    });

    test('después, dice el total y el rango', () {
      final text = dailyReminderText(
          _stats(wednesday, const {}, totalChars: 1800 * 250));
      expect(text, contains('250 páginas'));
      expect(text, contains('Lector asiduo'));
    });
  });
}
