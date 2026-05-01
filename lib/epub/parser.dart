import 'dart:io';
import 'dart:typed_data';
import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' as html_parser;
import 'models.dart';

Future<Book> parseEpub(String path) async {
  final bytes = await File(path).readAsBytes();
  final epub = await EpubReader.readBook(bytes);

  final title = epub.Title ?? 'Sin título';
  final author = epub.Author ?? 'Desconocido';
  final lang = _detectLanguage(epub.Schema?.Package?.Metadata?.Languages);

  final chapters = _parseChaptersFromSpine(epub);

  return Book(
    title: title,
    author: author,
    language: lang,
    filePath: path,
    chapters: chapters,
  );
}

// Reads content in spine order (OPF) and groups files under their TOC chapter.
// This handles EPUBs (e.g. Calibre-generated) where the TOC points to a
// heading-only file and the actual body text is in the next spine file.
List<Chapter> _parseChaptersFromSpine(EpubBook epub) {
  // normalized filename → chapter title from NCX/TOC
  final tocByFile = <String, String>{};
  for (final ch in _flattenChapters(epub.Chapters ?? [])) {
    final name = _normHref(ch.ContentFileName ?? '');
    if (name.isNotEmpty) tocByFile.putIfAbsent(name, () => ch.Title ?? '');
  }

  final spineRefs = epub.Schema?.Package?.Spine?.Items ?? [];
  final manifestItems = epub.Schema?.Package?.Manifest?.Items ?? [];
  final htmlFiles = epub.Content?.Html ?? {};

  // Build ordered list of (href, htmlContent) matching the spine
  final spineFiles = <(String, String)>[];
  for (final ref in spineRefs) {
    String? href;
    for (final m in manifestItems) {
      if (m.Id == ref.IdRef) { href = m.Href; break; }
    }
    if (href == null || href.isEmpty) continue;

    String? content;
    final normHref = _normHref(href);
    for (final e in htmlFiles.entries) {
      if (_normHref(e.key) == normHref) { content = e.value.Content; break; }
    }
    if (content != null) spineFiles.add((href, content));
  }

  // Walk spine files, flushing a new Chapter each time a TOC boundary is hit
  final chapters = <Chapter>[];
  int chIdx = 0;
  String currentTitle = '';
  final accumulated = <Paragraph>[];

  void flush() {
    if (accumulated.isEmpty || currentTitle.isEmpty) return;
    // Re-index paragraphs sequentially across merged files
    final reindexed = <Paragraph>[];
    for (int i = 0; i < accumulated.length; i++) {
      final p = accumulated[i];
      reindexed.add(Paragraph(
        rawText: p.rawText,
        sentences: p.sentences,
        index: i,
        isHeading: p.isHeading,
      ));
    }
    chapters.add(Chapter(title: currentTitle, paragraphs: reindexed, index: chIdx++));
    accumulated.clear();
  }

  for (final (href, content) in spineFiles) {
    final norm = _normHref(href);
    if (tocByFile.containsKey(norm)) {
      flush();
      currentTitle = tocByFile[norm]!;
    }
    accumulated.addAll(_extractParagraphs(content, 0));
  }
  flush();

  // Fallback: if spine parsing yielded nothing, use the TOC chapter list
  if (chapters.isEmpty) {
    int fallbackIdx = 0;
    for (final item in _flattenChapters(epub.Chapters ?? [])) {
      final paragraphs = _extractParagraphs(item.HtmlContent ?? '', fallbackIdx);
      if (paragraphs.isEmpty) continue;
      chapters.add(Chapter(
        title: item.Title ?? 'Capítulo ${fallbackIdx + 1}',
        paragraphs: paragraphs,
        index: fallbackIdx,
      ));
      fallbackIdx++;
    }
  }

  return chapters;
}

// Strips path prefix and anchor so "text/part0004.html#sec1" → "part0004.html"
String _normHref(String href) => href.split('/').last.split('#').first;

List<EpubChapter> _flattenChapters(List<EpubChapter> chapters) {
  final result = <EpubChapter>[];
  for (final ch in chapters) {
    result.add(ch);
    if (ch.SubChapters != null && ch.SubChapters!.isNotEmpty) {
      result.addAll(_flattenChapters(ch.SubChapters!));
    }
  }
  return result;
}

final _headingRe = RegExp(r'^h[1-6]$');

List<Paragraph> _extractParagraphs(String htmlContent, int chapterIdx) {
  final doc = html_parser.parse(htmlContent);
  doc.querySelectorAll('script, style, nav').forEach((e) => e.remove());

  const blockSel = 'p, li, blockquote, h1, h2, h3, h4, h5, h6';
  var elements = doc.querySelectorAll(blockSel).toList();

  // Leaf divs: divs with no block-element children — covers EPUBs that use
  // raw <div> tags instead of <p> for body paragraphs.
  final leafDivs = doc
      .querySelectorAll('div')
      .where((d) => d.querySelectorAll(blockSel).isEmpty)
      .toList();

  if (elements.isEmpty) {
    elements = leafDivs;
  } else {
    // If only headings were found, body text must be in leaf divs — merge them.
    final hasBodyText =
        elements.any((e) => !_headingRe.hasMatch(e.localName ?? ''));
    if (!hasBodyText) elements = [...elements, ...leafDivs];
  }

  final paragraphs = <Paragraph>[];
  int paraIdx = 0;

  for (final element in elements) {
    final raw = element.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (raw.isEmpty) continue;

    final tag = element.localName ?? '';
    final isHeading = _headingRe.hasMatch(tag);

    // Headings need only 2+ chars; body text needs 20+ to skip noise.
    if (raw.length < (isHeading ? 2 : 20)) continue;

    final sentences = _splitSentences(raw, paraIdx);
    if (sentences.isEmpty) continue;

    paragraphs.add(Paragraph(
      rawText: raw,
      sentences: sentences,
      index: paraIdx,
      isHeading: isHeading,
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

String? _stripHtml(String? raw) {
  if (raw == null || raw.isEmpty) return raw;
  return html_parser.parse(raw).body?.text.trim();
}

String _detectLanguage(List<String?>? languages) {
  if (languages == null || languages.isEmpty) return 'es';
  final lang = languages.first?.toLowerCase() ?? 'es';
  if (lang.startsWith('en')) return 'en';
  return 'es';
}

// ─── EpubExtras ──────────────────────────────────────────────────────────────

class EpubExtras {
  final Uint8List? coverBytes;
  final String coverExt;
  final String? description;
  final String? publisher;
  final String? publishedDate;
  final String? subject;

  EpubExtras({
    this.coverBytes,
    this.coverExt = 'jpg',
    this.description,
    this.publisher,
    this.publishedDate,
    this.subject,
  });
}

Future<EpubExtras> extractEpubExtras(String path) async {
  final bytes = await File(path).readAsBytes();
  final epub = await EpubReader.readBook(bytes);

  // ── Cover image ───────────────────────────────────────────────────────────
  Uint8List? coverBytes;
  String coverExt = 'jpg';

  final images = epub.Content?.Images;

  if (images != null && images.isNotEmpty) {
    EpubByteContentFile? coverFile;

    // 1. Check metadata meta items for a 'cover' entry pointing to a manifest id.
    final metaItems = epub.Schema?.Package?.Metadata?.MetaItems;
    String? coverHref;
    if (metaItems != null) {
      for (final meta in metaItems) {
        if (meta.Name == 'cover') {
          final coverId = meta.Content;
          if (coverId != null) {
            // Find the manifest item with that id.
            final manifestItems =
                epub.Schema?.Package?.Manifest?.Items;
            if (manifestItems != null) {
              for (final item in manifestItems) {
                if (item.Id == coverId) {
                  coverHref = item.Href;
                  break;
                }
              }
            }
          }
          break;
        }
      }
    }

    if (coverHref != null) {
      // Extract just the filename portion of the href.
      final hrefFileName = coverHref.split('/').last;
      // Find the image whose FileName ends with that filename.
      for (final entry in images.entries) {
        if (entry.key.endsWith(hrefFileName)) {
          coverFile = entry.value;
          break;
        }
      }
    }

    // 2. Fallback: look for an image whose key contains 'cover'.
    if (coverFile == null) {
      for (final entry in images.entries) {
        if (entry.key.toLowerCase().contains('cover')) {
          coverFile = entry.value;
          break;
        }
      }
    }

    // 3. Fallback: use the first image.
    coverFile ??= images.values.first;

    final rawContent = coverFile.Content;
    if (rawContent != null) {
      coverBytes = Uint8List.fromList(rawContent);
    }
    final fileName = coverFile.FileName ?? '';
    if (fileName.toLowerCase().endsWith('.png')) {
      coverExt = 'png';
    } else {
      coverExt = 'jpg';
    }
  }

  // ── Metadata ──────────────────────────────────────────────────────────────
  final metadata = epub.Schema?.Package?.Metadata;
  final description = _stripHtml(metadata?.Description);
  final publisher = metadata?.Publishers?.firstOrNull;
  final publishedDate = metadata?.Dates?.firstOrNull?.Date;
  final subject = metadata?.Subjects?.firstOrNull;

  return EpubExtras(
    coverBytes: coverBytes,
    coverExt: coverExt,
    description: description,
    publisher: publisher,
    publishedDate: publishedDate,
    subject: subject,
  );
}
