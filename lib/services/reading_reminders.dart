import 'dart:developer' as dev;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../stats/quotes.dart';
import '../stats/reader_rank.dart';
import '../storage/repositories.dart';
import '../ui/providers/reading_stats_provider.dart';

/// The two optional reading notifications: a weekly summary and a daily
/// reminder. Both are off until the reader turns them on in Settings.
///
/// Everything is decided on the phone and scheduled with the system; nothing
/// is sent anywhere, and no notification ever carries text from a book — only
/// counts, the rank, and a quote.
///
/// Scheduling is inexact on purpose: exact alarms need a permission that
/// Android 14 restricts, and a reminder landing a few minutes late loses
/// nothing. There is no boot receiver either. The schedule is redone every
/// time the app starts and every time the reading figures change, so a phone
/// that restarts and is never opened simply has nothing new to summarise.
class ReadingReminders {
  static final _plugin = FlutterLocalNotificationsPlugin();

  static const _weeklyId = 7001;
  static const _dailyId = 7002;
  static const payload = 'progress';

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'resumen_lectura',
      'Tu lectura',
      channelDescription:
          'Resumen semanal y recordatorio para leer, solo si los enciendes en '
          'Ajustes.',
      importance: Importance.low,
      priority: Priority.low,
      playSound: false,
      enableVibration: false,
    ),
  );

  /// What to do when a notification is tapped while the app is running.
  static void Function()? onOpen;

  /// Whether the app was started by tapping one of these notifications.
  static bool launchedFromNotification = false;

  static bool _ready = false;
  static String? _lastScheduled;

  static Future<void> init() async {
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          if (response.payload == payload) onOpen?.call();
        },
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      launchedFromNotification = (launch?.didNotificationLaunchApp ?? false) &&
          launch?.notificationResponse?.payload == payload;
      _ready = true;
    } catch (e) {
      // Without notifications the app is exactly what it was before them.
      dev.log('[Reminders] init failed: $e');
    }
  }

  /// Asks Android for permission to post notifications (13 and later). True
  /// when granted, or when the version does not ask.
  static Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    } catch (e) {
      dev.log('[Reminders] permission request failed: $e');
      return false;
    }
  }

  /// Brings what is scheduled in line with the settings and the figures.
  ///
  /// Cheap to call often: when nothing would change it does not touch the
  /// system at all, which matters because the figures change with every
  /// paragraph read.
  static Future<void> reschedule({
    required bool weekly,
    required String dailyAt,
    required ReadingStats stats,
    DateTime? now,
  }) async {
    if (!_ready) return;
    final at = now ?? DateTime.now();

    final summary = weekly ? weeklySummaryText(stats, at) : null;
    final weeklyWhen = summary == null ? null : nextWeeklySummary(at);
    final reminder = dailyAt.isEmpty ? null : dailyReminderText(stats);
    final dailyWhen = reminder == null ? null : nextDaily(at, dailyAt);

    final signature = '$summary|$weeklyWhen|$reminder|$dailyAt';
    if (signature == _lastScheduled) return;

    try {
      await _plugin.cancel(id: _weeklyId);
      await _plugin.cancel(id: _dailyId);
      if (summary != null && weeklyWhen != null) {
        await _plugin.zonedSchedule(
          id: _weeklyId,
          title: 'Tu semana de lectura',
          body: summary,
          scheduledDate: _utc(weeklyWhen),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      }
      if (reminder != null && dailyWhen != null) {
        await _plugin.zonedSchedule(
          id: _dailyId,
          title: '¿Unas páginas hoy?',
          body: reminder,
          scheduledDate: _utc(dailyWhen),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          // Repeats every day at that time until it is turned off.
          matchDateTimeComponents: DateTimeComponents.time,
          payload: payload,
        );
      }
      _lastScheduled = signature;
    } catch (e) {
      dev.log('[Reminders] scheduling failed: $e');
    }
  }

  /// The local instant expressed in UTC, which needs no time zone database.
  ///
  /// The cost: the daily repeat keeps the same UTC time, so in a place with
  /// daylight saving it drifts an hour twice a year until the app is opened
  /// and reschedules it. Mexico dropped DST in 2022; elsewhere it is an hour.
  static tz.TZDateTime _utc(DateTime local) =>
      tz.TZDateTime.from(local.toUtc(), tz.UTC);
}

// ── Pure parts, tested on their own ─────────────────────────────────────────

/// Sunday 20:00 local: the next one, or today's if it has not passed yet.
DateTime nextWeeklySummary(DateTime now) {
  final daysToSunday = (DateTime.sunday - now.weekday) % 7;
  var at = DateTime(now.year, now.month, now.day + daysToSunday, 20);
  if (!at.isAfter(now)) at = DateTime(at.year, at.month, at.day + 7, 20);
  return at;
}

/// The next time the clock reads [hhmm] ("21:30").
DateTime nextDaily(DateTime now, String hhmm) {
  final parts = hhmm.split(':');
  final hour = int.parse(parts[0]);
  final minute = int.parse(parts[1]);
  var at = DateTime(now.year, now.month, now.day, hour, minute);
  if (!at.isAfter(now)) at = DateTime(now.year, now.month, now.day + 1, hour, minute);
  return at;
}

/// Pages read in the calendar week (Monday to Sunday) that contains [now],
/// and in the week before it.
({double thisWeek, double lastWeek}) calendarWeeks(
    ReadingStats stats, DateTime now) {
  final byDay = {for (final d in stats.lastFourteen) d.day: d.chars};
  final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
  int sum(DateTime from, int days) {
    var total = 0;
    for (var i = 0; i < days; i++) {
      total += byDay[ReadingLogRepo.dayOf(
              DateTime(from.year, from.month, from.day + i))] ??
          0;
    }
    return total;
  }

  return (
    thisWeek: ReaderRank.pagesOf(sum(monday, now.weekday)),
    lastWeek: ReaderRank.pagesOf(
        sum(DateTime(monday.year, monday.month, monday.day - 7), 7)),
  );
}

/// The weekly summary, or null when there was no reading this week: a
/// notification to say "0 pages" is a reproach, not a reward.
String? weeklySummaryText(ReadingStats stats, DateTime now) {
  final weeks = calendarWeeks(stats, now);
  if (weeks.thisWeek < 0.5) return null;
  final pages = formatPages(weeks.thisWeek);
  final diff = weeks.thisWeek - weeks.lastWeek;
  final comparison = weeks.lastWeek < 0.5
      ? ''
      : diff >= 0.5
          ? ', ${formatPages(diff)} más que la anterior'
          : diff <= -0.5
              ? ''
              : ', igual que la anterior';
  final quote = quoteForDay(now);
  return 'Esta semana: $pages páginas$comparison. '
      'Vas por ${stats.title}.\n«${quote.text}» — ${quote.author}';
}

/// The daily reminder. Total pages rather than today's: the total cannot go
/// stale between one opening of the app and the next, because nothing is read
/// without opening it.
String dailyReminderText(ReadingStats stats) {
  if (stats.pages < 1) {
    return 'Diez minutos de lectura antes de dormir. El primer rango está a '
        '${formatPages(stats.pagesToNext)} páginas.';
  }
  return 'Llevas ${formatPages(stats.pages)} páginas y vas por ${stats.title}. '
      '¿Unas cuantas más?';
}
