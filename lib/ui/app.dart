import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/settings_provider.dart';
import 'screens/library_screen.dart';
import 'screens/reader_screen.dart';
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
  ],
);

class VoiceXApp extends ConsumerWidget {
  const VoiceXApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final themeStr =
        settingsAsync.valueOrNull?.theme ?? 'dark';

    return MaterialApp.router(
      title: 'VoiceX',
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
