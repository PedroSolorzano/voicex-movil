import 'package:flutter/material.dart';
import 'reader_theme.dart';

/// Renders a paragraph with the sentence being spoken tinted and the current
/// word emphasised on top of it.
///
/// Both highlights are character ranges into the same raw text, so the spans
/// are built by cutting the text at every range boundary. That keeps the two
/// layers consistent even when the word sits across a sentence edge.
class HighlightedText extends StatelessWidget {
  final String rawText;
  final (int, int)? sentenceRange;
  final (int, int)? wordRange;
  final TextStyle baseStyle;
  final ReaderPalette palette;

  const HighlightedText({
    super.key,
    required this.rawText,
    required this.baseStyle,
    required this.palette,
    this.sentenceRange,
    this.wordRange,
  });

  @override
  Widget build(BuildContext context) {
    if (sentenceRange == null && wordRange == null) {
      return Text(rawText, style: baseStyle);
    }

    final cuts = <int>{0, rawText.length};
    for (final r in [sentenceRange, wordRange]) {
      if (r == null) continue;
      if (r.$1 >= 0 && r.$1 <= rawText.length) cuts.add(r.$1);
      if (r.$2 >= 0 && r.$2 <= rawText.length) cuts.add(r.$2);
    }
    final points = cuts.toList()..sort();

    final spans = <TextSpan>[];
    for (var i = 0; i < points.length - 1; i++) {
      final start = points[i];
      final end = points[i + 1];
      if (start >= end) continue;

      final inSentence = sentenceRange != null &&
          start >= sentenceRange!.$1 &&
          end <= sentenceRange!.$2;
      final inWord =
          wordRange != null && start >= wordRange!.$1 && end <= wordRange!.$2;

      var style = baseStyle;
      if (inSentence) {
        style = style.copyWith(
          backgroundColor: palette.activeSentence,
          color: palette.onActiveSentence,
        );
      }
      if (inWord) {
        style = style.copyWith(
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          decorationThickness: 2,
          decorationColor: palette.onActiveSentence,
        );
      }

      spans.add(TextSpan(text: rawText.substring(start, end), style: style));
    }

    return Text.rich(TextSpan(children: spans));
  }
}
