import 'package:flutter/material.dart';
import '../../epub/models.dart';

class HighlightedText extends StatelessWidget {
  final Paragraph paragraph;
  final int highlightedIndex;
  final TextStyle baseStyle;
  final Color highlightColor;

  const HighlightedText({
    super.key,
    required this.paragraph,
    required this.highlightedIndex,
    required this.baseStyle,
    this.highlightColor = const Color(0xFFFFD54F),
  });

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: paragraph.sentences.map((s) {
          final isActive = s.index == highlightedIndex;
          return TextSpan(
            text: '${s.text} ',
            style: isActive
                ? baseStyle.copyWith(
                    backgroundColor: highlightColor,
                    color: Colors.black87,
                  )
                : baseStyle,
          );
        }).toList(),
      ),
    );
  }
}
