import 'package:flutter/material.dart';

import '../../epub/models.dart';
import '../../epub/parser.dart';
import '../../storage/audio_usage.dart';
import '../../storage/repositories.dart';
import '../widgets/audio_labels.dart';

Future<Book?> _parseOrNull(String path) async {
  try {
    return await parseEpubInBackground(path);
  } catch (_) {
    return null;
  }
}

/// What is stored for one book, chapter by chapter, and the way to delete it
/// without deleting everything.
///
/// A chapter of a long novel can run to several hours of audio, and the reader
/// may be well into it: what was downloaded earlier is of no use any more, but
/// the whole-book and per-engine deletes in Ajustes could not say "everything
/// before where I am".
class BookDownloadsScreen extends StatefulWidget {
  final int bookId;

  /// Reads the EPUB to get chapter titles and sizes. Injectable so a test does
  /// not need a real book.
  final Future<Book?> Function(String path) loadBook;

  const BookDownloadsScreen(
      {super.key, required this.bookId, this.loadBook = _parseOrNull});

  @override
  State<BookDownloadsScreen> createState() => _BookDownloadsScreenState();
}

class _BookDownloadsScreenState extends State<BookDownloadsScreen> {
  final _repo = AudioCacheRepo();

  bool _loaded = false;
  String _title = '';
  List<ChapterAudioUsage> _chapters = const [];
  ({int chapter, int paragraph}) _position = (chapter: 0, paragraph: 0);
  ({int kb, int paragraphs}) _before = (kb: 0, paragraphs: 0);
  final Map<int, String> _chapterTitles = {};
  final Map<int, int> _chapterTotals = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final row = await LibraryRepo().get(widget.bookId);
    final usage = await _repo.usageByChapter(widget.bookId);
    final progress = await ProgressRepo().get(widget.bookId);
    final before = await _repo.usageBefore(
        widget.bookId, progress.chapter, progress.paragraph);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _title = (row?['title'] as String?) ?? 'Libro eliminado';
      _chapters = usage;
      _position = (chapter: progress.chapter, paragraph: progress.paragraph);
      _before = before;
    });

    // The titles come from the EPUB, which takes a moment to read: the list is
    // already on screen without them ("Capítulo 4"), and fills in after.
    final path = row?['file_path'] as String?;
    if (path == null || _chapterTitles.isNotEmpty) return;
    final book = await widget.loadBook(path);
    if (book == null || !mounted) return;
    setState(() {
      for (final c in book.chapters) {
        _chapterTitles[c.index] = c.title;
        _chapterTotals[c.index] = c.paragraphs.length;
      }
    });
  }

  String _chapterName(int chapter) {
    final title = _chapterTitles[chapter];
    return title == null || title.isEmpty ? 'Capítulo ${chapter + 1}' : title;
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _deleteChapter(ChapterAudioUsage c) async {
    if (!await _confirm(
        'Borrar ${_chapterName(c.chapter)}',
        'Se liberan ${formatSize(c.kb)} de audio de este capítulo '
            '(${paragraphsLabel(c.paragraphs)}). Si quieres oírlo después, '
            'habrá que descargarlo otra vez.',
        'Borrar')) {
      return;
    }
    await _repo.deleteChapter(widget.bookId, c.chapter);
    await _load();
  }

  Future<void> _deleteBefore() async {
    final spot = '${_chapterName(_position.chapter)}, párrafo '
        '${_position.paragraph + 1}';
    if (!await _confirm(
        'Borrar lo anterior a tu posición',
        'Vas por $spot. Se borran ${formatSize(_before.kb)} '
            '(${paragraphsLabel(_before.paragraphs)}) de lo que está antes: '
            'los capítulos anteriores y el principio de este. Tu posición y lo '
            'que sigue se quedan.',
        'Borrar')) {
      return;
    }
    await _repo.deleteBefore(
        widget.bookId, _position.chapter, _position.paragraph);
    await _load();
  }

  Future<void> _deleteAll() async {
    final kb = _chapters.fold<int>(0, (n, c) => n + c.kb);
    if (!await _confirm(
        'Borrar todo el audio de este libro',
        'Se liberan ${formatSize(kb)}. Lo que quieras oír después habrá que '
            'generarlo otra vez.',
        'Borrar todo')) {
      return;
    }
    await _repo.deleteForBook(widget.bookId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalKb = _chapters.fold<int>(0, (n, c) => n + c.kb);

    return Scaffold(
      appBar: AppBar(title: const Text('Descargas del libro')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(_title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(
                    _chapters.isEmpty
                        ? 'Este libro no tiene audio guardado.'
                        : '${formatSize(totalKb)} en '
                            '${_chapters.length == 1 ? '1 capítulo' : '${_chapters.length} capítulos'}',
                    style: theme.textTheme.bodySmall),
                if (_chapters.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.vertical_align_top),
                      title: const Text('Borrar lo anterior a mi posición'),
                      subtitle: Text(_before.kb > 0
                          ? 'Vas por ${_chapterName(_position.chapter)}, párrafo '
                              '${_position.paragraph + 1}. Libera '
                              '${formatSize(_before.kb)} '
                              '(${paragraphsLabel(_before.paragraphs)}).'
                          : 'No hay audio antes de donde vas '
                              '(${_chapterName(_position.chapter)}, párrafo '
                              '${_position.paragraph + 1}).'),
                      onTap: _before.kb > 0 ? _deleteBefore : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Por capítulo', style: theme.textTheme.titleSmall),
                ],
                for (final c in _chapters)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_chapterName(c.chapter),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text([
                      if (_chapterTotals[c.chapter] != null)
                        '${c.paragraphs} de ${paragraphsLabel(_chapterTotals[c.chapter]!)}'
                      else
                        paragraphsLabel(c.paragraphs),
                      formatSize(c.kb),
                      if (c.chapter == _position.chapter) 'vas por aquí',
                    ].join(' · ')),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Borrar ${_chapterName(c.chapter)}',
                      onPressed: () => _deleteChapter(c),
                    ),
                  ),
                if (_chapters.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_sweep_outlined),
                    label: Text('Borrar todo lo de este libro '
                        '(${formatSize(totalKb)})'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error),
                    onPressed: _deleteAll,
                  ),
                ],
              ],
            ),
    );
  }
}
