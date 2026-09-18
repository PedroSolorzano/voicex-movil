import 'package:flutter/material.dart';

/// How the library screen dresses itself.
///
/// Mirrors `ReaderPalette` and `readerThemeData`: a handful of colours and
/// assets, and one function that turns them into a full [ThemeData], so every
/// dialog, menu and sheet opened from the library matches without being
/// dressed by hand.
///
/// The classic skins are paper and **ignore the app's dark mode** on purpose,
/// the same way the sepia reading palette does: a dark card catalogue is not a
/// card catalogue.
class LibrarySkin {
  final String name;

  /// Card and sheet surface. Null on [modern], which defers to the app theme.
  final Color? paper;
  final Color? ink;
  final Color? inkMuted;

  /// Old gold: ornaments, rules, text on wood.
  final Color? accent;

  /// Dark wood: app bar and, for [catalog], the whole background.
  final Color? frame;

  /// Behind the list. Wood for [catalog] (cards sit on a shelf), paper for
  /// [classic] (the list *is* the page).
  final Color? background;
  final String? backgroundTexture;
  final String? barTexture;

  const LibrarySkin._({
    required this.name,
    this.paper,
    this.ink,
    this.inkMuted,
    this.accent,
    this.frame,
    this.background,
    this.backgroundTexture,
    this.barTexture,
  });

  static const _parchment = 'assets/skins/parchment.png';
  static const _wood = 'assets/skins/wood.png';

  static const modern = LibrarySkin._(name: 'modern');

  /// Library index cards, the design in `Propuestas/…xtzy (1).jpg`.
  static const catalog = LibrarySkin._(
    name: 'catalog',
    paper: Color(0xFFF4E9CF),
    ink: Color(0xFF2A1B10),
    // 6.6:1 on the card. Measured in test/library_skin_test.dart.
    inkMuted: Color(0xFF5A4632),
    accent: Color(0xFFE2C27A),
    frame: Color(0xFF3A2415),
    background: Color(0xFF4A2E1B),
    backgroundTexture: _wood,
    barTexture: _wood,
  );

  /// Parchment page with bound volumes, `Propuestas/Screenshot …210113.png`.
  static const classic = LibrarySkin._(
    name: 'classic',
    paper: Color(0xFFF1E4C6),
    ink: Color(0xFF2B1A12),
    inkMuted: Color(0xFF5E4A36),
    accent: Color(0xFF8A6424),
    frame: Color(0xFF3A2415),
    background: Color(0xFFF1E4C6),
    backgroundTexture: _parchment,
    barTexture: _wood,
  );

  bool get isModern => name == 'modern';

  /// Text on the wooden bar. Gold, whatever [accent] is on the page.
  static const onWood = Color(0xFFEAD9A8);

  static LibrarySkin of(String name) => switch (name) {
        'catalog' => catalog,
        'classic' => classic,
        // Unknown value from a later or earlier build: the modern skin is the
        // one that existed before any of this.
        _ => modern,
      };
}

/// Weight on a variable font. [FontWeight] alone does not move the `wght` axis
/// of Cinzel and EB Garamond, which ship only as variable fonts.
List<FontVariation> wght(double value) => [FontVariation('wght', value)];

TextStyle skinTitleStyle(double size, Color color) => TextStyle(
      fontFamily: 'Cinzel',
      fontSize: size,
      fontWeight: FontWeight.w700,
      fontVariations: wght(700),
      color: color,
      height: 1.15,
      letterSpacing: 0.4,
    );

/// Material theme for [skin], built on top of the app's own.
///
/// [modern] returns [app] untouched: choosing it must look exactly like the
/// library did before skins existed.
ThemeData libraryThemeData(LibrarySkin skin, ThemeData app) {
  if (skin.isModern) return app;

  final paper = skin.paper!;
  final ink = skin.ink!;
  final muted = skin.inkMuted!;
  final frame = skin.frame!;

  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8A6424),
    brightness: Brightness.light,
  ).copyWith(
    surface: paper,
    onSurface: ink,
    onSurfaceVariant: muted,
    primary: const Color(0xFF6E4A1C),
    onPrimary: Colors.white,
    secondaryContainer: const Color(0xFFE3CFA3),
    onSecondaryContainer: ink,
    surfaceContainerHighest: const Color(0xFFE3D3B0),
    outlineVariant: muted.withValues(alpha: 0.4),
  );

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final text = base.textTheme.apply(
    fontFamily: 'EBGaramond',
    bodyColor: ink,
    displayColor: ink,
  );

  return base.copyWith(
    scaffoldBackgroundColor: skin.background,
    textTheme: text.copyWith(
      titleLarge: skinTitleStyle(20, ink),
      titleMedium: skinTitleStyle(16, ink),
      // Garamond runs small next to Roboto: one step up keeps it readable.
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 15.5),
      bodySmall: text.bodySmall?.copyWith(fontSize: 13.5, color: muted),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: frame,
      foregroundColor: LibrarySkin.onWood,
      iconTheme: const IconThemeData(color: LibrarySkin.onWood),
      actionsIconTheme: const IconThemeData(color: LibrarySkin.onWood),
      titleTextStyle: skinTitleStyle(22, LibrarySkin.onWood),
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: Color(0xFF3A2415),
      foregroundColor: LibrarySkin.onWood,
      shape: StadiumBorder(
        side: BorderSide(color: Color(0xFFB08A45), width: 1.5),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: paper,
      textStyle: text.bodyLarge?.copyWith(color: ink),
    ),
    dialogTheme: DialogThemeData(backgroundColor: paper),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: paper,
      modalBackgroundColor: paper,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: ink,
      linearTrackColor: muted.withValues(alpha: 0.2),
    ),
  );
}
