import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/reading_reminders.dart';
import 'providers/reading_stats_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/library_screen.dart';
import 'screens/progress_screen.dart';
import 'screens/reader_screen.dart';
import 'screens/report_screen.dart';
import 'screens/settings_screen.dart';

final _router = GoRouter(
  initialLocation: '/library',
  routes: [
    GoRoute(
      path: '/library',
      builder: (context, state) => const LibraryScreen(),
    ),
    GoRoute(
      path: '/reader/:bookId',
      builder: (_, state) {
        final bookId = int.parse(state.pathParameters['bookId']!);
        // `extra` is absent on a cold deep link; ReaderScreen then resolves the
        // path from the library instead of crashing on a failed cast.
        final filePath = state.extra as String?;
        return ReaderScreen(bookId: bookId, filePath: filePath);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/progress',
      builder: (context, state) => const ProgressScreen(),
    ),
    GoRoute(
      path: '/report',
      builder: (context, state) => const ReportScreen(),
    ),
  ],
);

class VoiceXApp extends ConsumerStatefulWidget {
  const VoiceXApp({super.key});

  @override
  ConsumerState<VoiceXApp> createState() => _VoiceXAppState();
}

class _VoiceXAppState extends ConsumerState<VoiceXApp> {
  @override
  void initState() {
    super.initState();
    ReadingReminders.onOpen = () => _router.push('/progress');
    if (ReadingReminders.launchedFromNotification) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _router.push('/progress'));
    }
  }

  /// Reading notifications follow both the settings and the figures: turning
  /// one on schedules it, and every paragraph read may change its text.
  /// [ReadingReminders.reschedule] skips the call when nothing changed.
  void _reschedule() {
    final settings = ref.read(settingsProvider).valueOrNull;
    final stats = ref.read(readingStatsProvider).valueOrNull;
    if (settings == null || stats == null) return;
    ReadingReminders.reschedule(
      weekly: settings.weeklySummary,
      dailyAt: settings.dailyReminderAt,
      stats: stats,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (_, _) => _reschedule());
    ref.listen(readingStatsProvider, (_, _) => _reschedule());

    final settingsAsync = ref.watch(settingsProvider);
    final themeStr =
        settingsAsync.valueOrNull?.theme ?? 'dark';

    return MaterialApp.router(
      title: 'VoiceX',
      // Every string of our own is already Spanish; this translates the ones
      // that belong to Material itself — the time picker said "Cancel" and
      // "OK". Fixed to Spanish rather than following the phone, because the
      // rest of the app does not follow it either.
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: switch (themeStr) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      routerConfig: _router,
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7B5EA7),
      brightness: brightness,
    );
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
    );
  }
}
