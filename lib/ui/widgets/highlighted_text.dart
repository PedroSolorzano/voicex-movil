import 'package:flutter/material.dart';
import '../../epub/models.dart';
import 'reader_theme.dart';

/// Renders a paragraph with the sentence currently being spoken highlighted.
class HighlightedText extends StatelessWidget {
  final Paragraph paragraph;
  final int highlightedIndex;
  final TextStyle baseStyle;
  final ReaderPalette palette;

  const HighlightedText({
    super.key,
    required this.paragraph,
    required this.highlightedIndex,
    required this.baseStyle,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          for (final s in paragraph.sentences)
            TextSpan(
              text: '${s.text} ',
              style: s.index == highlightedIndex
                  ? baseStyle.copyWith(
                      backgroundColor: palette.activeSentence,
                      color: palette.onActiveSentence,
                    )
                  : baseStyle,
            ),
        ],
      ),
    );
  }
}
