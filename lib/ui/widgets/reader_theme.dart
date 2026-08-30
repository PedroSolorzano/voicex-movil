import 'package:flutter/material.dart';
import '../../config/settings.dart';

/// Colours for the reading surface. Previously the sepia background was
/// hardcoded in the reader, so the text pane stayed cream even in dark mode.
class ReaderPalette {
  final Color background;
  final Color text;
  final Color muted;
  final Color activeParagraph;
  final Color activeSentence;
  final Color onActiveSentence;

  const ReaderPalette({
    required this.background,
    required this.text,
    required this.muted,
    required this.activeParagraph,
    required this.activeSentence,
    required this.onActiveSentence,
  });

  static const sepia = ReaderPalette(
    background: Color(0xFFF5E6C8),
    text: Color(0xFF3E2723),
    muted: Color(0xFF7A6A5A),
    activeParagraph: Color(0x33FFB300),
    activeSentence: Color(0xFFFFD54F),
    onActiveSentence: Color(0xFF2B1A12),
  );

  static const light = ReaderPalette(
    background: Color(0xFFFCFCFC),
    text: Color(0xFF1B1B1B),
    muted: Color(0xFF6B6B6B),
    activeParagraph: Color(0x1A000000),
    activeSentence: Color(0xFFFFE082),
    onActiveSentence: Color(0xFF1B1B1B),
  );

  /// Low-luminance surface rather than pure black: less halation on OLED at
  /// night while keeping contrast comfortably above WCAG AA.
  static const dark = ReaderPalette(
    background: Color(0xFF15171A),
    text: Color(0xFFD8D4CE),
    muted: Color(0xFF8A8781),
    activeParagraph: Color(0x1FFFFFFF),
    activeSentence: Color(0xFF4A3B12),
    onActiveSentence: Color(0xFFFFE9A8),
  );

  static ReaderPalette of(String name, Brightness platformBrightness) =>
      switch (name) {
        'light' => light,
        'dark' => dark,
        'sepia' => sepia,
        // Unknown value: follow the system rather than guessing.
        _ => platformBrightness == Brightness.dark ? dark : sepia,
      };
}

/// Android resolves the generic families 'serif' and 'sans-serif' to Noto Serif
/// and Roboto, so a real book face is available without bundling a font.
/// The previous code asked for 'Georgia', which does not exist on Android and
/// silently fell back to the default sans.
String? readerFontFamily(String choice) => switch (choice) {
      'serif' => 'serif',
      'sans' => 'sans-serif',
      _ => null,
    };

TextStyle readerBodyStyle(AppSettings s, ReaderPalette palette) => TextStyle(
      fontSize: s.fontSize,
      height: s.lineHeight,
      fontFamily: readerFontFamily(s.readerFont),
      color: palette.text,
    );

TextStyle readerHeadingStyle(AppSettings s, ReaderPalette palette) => TextStyle(
      fontSize: s.fontSize + 3,
      height: s.lineHeight + 0.2,
      fontFamily: readerFontFamily(s.readerFont),
      fontWeight: FontWeight.bold,
      color: palette.text,
    );
