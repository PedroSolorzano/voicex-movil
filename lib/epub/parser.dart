import 'dart:io';
import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' as html_parser;
import 'models.dart';

Future<Book> parseEpub(String path) async {
  final bytes = await File(path).readAsBytes();
  final epub = await EpubReader.readBook(bytes);

  final title = epub.Title ?? 'Sin título';
  final author = epub.Author ?? 'Desconocido';
  final lang = _detectLanguage(epub.Schema?.Package?.Metadata?.Languages);

  final chapters = <Chapter>[];
  int chapterIdx = 0;

  for (final item in epub.Chapters ?? []) {
    final paragraphs = _extractParagraphs(item.HtmlContent ?? '', chapterIdx);
    if (paragraphs.isEmpty) continue;
    chapters.add(Chapter(
      title: item.Title ?? 'Capítulo ${chapterIdx + 1}',
      paragraphs: paragraphs,
      index: chapterIdx,
    ));
    chapterIdx++;
  }

  return Book(
    title: title,
    author: author,
    language: lang,
    filePath: path,
    chapters: chapters,
  );
}

List<Paragraph> _extractParagraphs(String htmlContent, int chapterIdx) {
  final doc = html_parser.parse(htmlContent);

  // Remove script/style tags
  doc.querySelectorAll('script, style, nav').forEach((e) => e.remove());

  final paragraphs = <Paragraph>[];
  int paraIdx = 0;

  for (final element in doc.querySelectorAll('p, div, li')) {
    final raw = element.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (raw.length < 20) continue;

    final sentences = _splitSentences(raw, paraIdx);
    if (sentences.isEmpty) continue;

    paragraphs.add(Paragraph(
      rawText: raw,
      sentences: sentences,
      index: paraIdx,
    ));
    paraIdx++;
  }

  return paragraphs;
}

List<Sentence> _splitSentences(String text, int paraIdx) {
  final parts = text.split(RegExp(r'(?<=[.!?…])\s+'));
  return parts
      .asMap()
      .entries
      .where((e) => e.value.trim().isNotEmpty)
      .map((e) => Sentence(text: e.value.trim(), index: e.key))
      .toList();
}

String _detectLanguage(List<String?>? languages) {
  if (languages == null || languages.isEmpty) return 'es';
  final lang = languages.first?.toLowerCase() ?? 'es';
  if (lang.startsWith('en')) return 'en';
  return 'es';
}
