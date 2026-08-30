import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/reader_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/highlighted_text.dart';
import '../../epub/models.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final int bookId;

  /// Null when reached by deep link; resolved from the library on load.
  final String? filePath;

  const ReaderScreen({super.key, required this.bookId, this.filePath});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _scrollController = ScrollController();
  List<GlobalKey> _paraKeys = [];
  int _lastChapterIndex = -1;
  int _lastParagraphCount = -1;

  static const _bodyStyle = TextStyle(
    fontSize: 18,
    height: 1.7,
    fontFamily: 'Georgia',
    color: Color(0xFF3E2723),
  );

  static const _headingStyle = TextStyle(
    fontSize: 20,
    height: 2.0,
    fontFamily: 'Georgia',
    fontWeight: FontWeight.bold,
    color: Color(0xFF3E2723),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(readerProvider.notifier).loadBook(widget.bookId, widget.filePath);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncKeys(int count) {
    if (count != _lastParagraphCount) {
      _paraKeys = List.generate(count, (_) => GlobalKey());
      _lastParagraphCount = count;
    }
  }

  void _scrollToIndex(int index) {
    if (index < 0 || index >= _paraKeys.length) return;
    final ctx = _paraKeys[index].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.15,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reader = ref.watch(readerProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final book = reader.book;

    ref.listen<ReaderState>(readerProvider, (prev, next) {
      final chapter = next.currentChapter;
      if (chapter != null) {
        // Rebuild keys when chapter changes.
        if (next.chapterIndex != _lastChapterIndex) {
          _lastChapterIndex = next.chapterIndex;
          _syncKeys(chapter.paragraphs.length);
        }
        // Scroll to active paragraph when it changes (TTS advance or bookmark).
        if (prev?.paragraphIndex != next.paragraphIndex ||
            prev?.chapterIndex != next.chapterIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToIndex(next.paragraphIndex);
          });
        }
      }
    });

    if (book == null) {
      if (reader.status == ReaderStatus.error) {
        return Scaffold(
          appBar: AppBar(title: const Text('Error')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(reader.statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 15)),
                ],
              ),
            ),
          ),
        );
      }
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (book.chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(book.title)),
        body: const Center(child: Text('El libro no tiene capítulos legibles')),
      );
    }

    final chapter = reader.currentChapter;
    final paraCount = chapter?.paragraphs.length ?? 0;
    _syncKeys(paraCount);

    return Scaffold(
      appBar: AppBar(
        title: Text(chapter?.title ?? '', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: const Icon(Icons.toc),
            tooltip: 'Índice',
            onPressed: () => _showToc(context),
          ),
          if (reader.isDownloading)
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: 'Cancelar descarga',
              onPressed: () => ref.read(readerProvider.notifier).cancelDownload(),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Descargar capitulo',
              onPressed: () => ref.read(readerProvider.notifier).downloadChapter(),
            ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Agregar marcador',
            onPressed: () => _addBookmark(context),
          ),
          IconButton(
            icon: const Icon(Icons.bookmarks_outlined),
            tooltip: 'Ver marcadores',
            onPressed: () => _showBookmarks(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Chapter navigation
          _ChapterNav(
            chapterIndex: reader.chapterIndex,
            totalChapters: book.chapters.length,
            onPrev: reader.chapterIndex > 0
                ? () => ref
                    .read(readerProvider.notifier)
                    .navigateChapter(reader.chapterIndex - 1)
                : null,
            onNext: reader.chapterIndex < book.chapters.length - 1
                ? () => ref
                    .read(readerProvider.notifier)
                    .navigateChapter(reader.chapterIndex + 1)
                : null,
          ),
          // Full-chapter scrollable reading area
          Expanded(
            child: Container(
              color: const Color(0xFFF5E6C8),
              child: paraCount == 0
                  ? const Center(child: Text('Sin contenido'))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 16),
                      itemCount: paraCount,
                      itemBuilder: (_, i) {
                        final para = chapter!.paragraphs[i];
                        final isActive = i == reader.paragraphIndex;
                        return _ParagraphTile(
                          key: _paraKeys[i],
                          para: para,
                          isActive: isActive,
                          highlightedSentence:
                              isActive ? reader.highlightedSentence : -1,
                          bodyStyle: _bodyStyle,
                          headingStyle: _headingStyle,
                          onTap: () => ref
                              .read(readerProvider.notifier)
                              .navigateParagraph(i),
                        );
                      },
                    ),
            ),
          ),
          // Controls
          _Controls(
              status: reader.status,
              reader: ref.read(readerProvider.notifier)),
          // Download progress
          if (reader.isDownloading)
            _DownloadProgress(
              done: reader.downloadDone,
              total: reader.downloadTotal,
            ),
          // Gender toggle
          _GenderToggle(
            gender: settings?.gender ?? 'female',
            onToggle: (g) {
              final s = settings?.copyWith(gender: g);
              if (s != null) ref.read(settingsProvider.notifier).save(s);
            },
          ),
          // Speed selector
          _SpeedSelector(
            currentRate: settings?.edgeRate ?? '+0%',
            onChanged: (rate) {
              final s = settings?.copyWith(edgeRate: rate);
              if (s != null) ref.read(settingsProvider.notifier).save(s);
            },
          ),
          // Status bar
          _StatusBar(
            message: reader.statusMessage,
            sessionDataKb: reader.sessionDataKb,
          ),
        ],
      ),
    );
  }

  Future<void> _addBookmark(BuildContext context) async {
    await ref.read(readerProvider.notifier).addBookmark();
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Marcador guardado')));
    }
  }

  Future<void> _showBookmarks(BuildContext context) async {
    final bookmarks = await ref.read(readerProvider.notifier).getBookmarks();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      builder: (_) => _BookmarksSheet(
        bookmarks: bookmarks,
        onJump: (b) {
          Navigator.pop(context);
          ref.read(readerProvider.notifier).jumpToBookmark(
              b['chapter_index'] as int,
              b['paragraph_index'] as int,
              b['sentence_index'] as int? ?? 0);
        },
        onDelete: (id) => ref.read(readerProvider.notifier).deleteBookmark(id),
      ),
    );
  }

  void _showToc(BuildContext context) {
    final book = ref.read(readerProvider).book;
    final currentChapterIndex = ref.read(readerProvider).chapterIndex;
    if (book == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollCtrl) => _TocSheet(
          chapters: book.chapters,
          currentIndex: currentChapterIndex,
          scrollController: scrollCtrl,
          onSelect: (idx) {
            Navigator.pop(context);
            ref.read(readerProvider.notifier).navigateChapter(idx);
          },
        ),
      ),
    );
  }
}

// ─── Paragraph tile ──────────────────────────────────────────────────────────

class _ParagraphTile extends StatelessWidget {
  final Paragraph para;
  final bool isActive;
  final int highlightedSentence;
  final TextStyle bodyStyle;
  final TextStyle headingStyle;
  final VoidCallback onTap;

  const _ParagraphTile({
    super.key,
    required this.para,
    required this.isActive,
    required this.highlightedSentence,
    required this.bodyStyle,
    required this.headingStyle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (para.isHeading) {
      content = Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 4),
        child: Text(para.rawText, style: headingStyle),
      );
    } else if (isActive) {
      content = HighlightedText(
        paragraph: para,
        highlightedIndex: highlightedSentence,
        baseStyle: bodyStyle,
      );
    } else {
      content = Text(para.rawText, style: bodyStyle);
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: isActive
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
            : EdgeInsets.zero,
        decoration: isActive && !para.isHeading
            ? BoxDecoration(
                color: Colors.amber.withAlpha(51),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: Colors.amber.withAlpha(128), width: 1),
              )
            : null,
        child: content,
      ),
    );
  }
}

// ─── Table of contents sheet ─────────────────────────────────────────────────

class _TocSheet extends StatelessWidget {
  final List<Chapter> chapters;
  final int currentIndex;
  final ScrollController scrollController;
  final ValueChanged<int> onSelect;

  const _TocSheet({
    required this.chapters,
    required this.currentIndex,
    required this.scrollController,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.grey[400],
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Índice',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: chapters.length,
            itemBuilder: (_, i) {
              final ch = chapters[i];
              final isCurrent = i == currentIndex;
              return ListTile(
                leading: Text('${i + 1}.',
                    style: TextStyle(
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[600],
                      fontWeight: isCurrent
                          ? FontWeight.bold
                          : FontWeight.normal,
                    )),
                title: Text(
                  ch.title,
                  style: TextStyle(
                    fontWeight:
                        isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: isCurrent
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                subtitle: Text(
                  '${ch.paragraphs.length} párrafos',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                trailing: isCurrent
                    ? Icon(Icons.play_arrow,
                        color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () => onSelect(i),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Chapter navigation ───────────────────────────────────────────────────────

class _ChapterNav extends StatelessWidget {
  final int chapterIndex;
  final int totalChapters;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _ChapterNav(
      {required this.chapterIndex,
      required this.totalChapters,
      this.onPrev,
      this.onNext});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: onPrev,
            tooltip: 'Cap. anterior'),
        Text('Cap. ${chapterIndex + 1} / $totalChapters',
            style: Theme.of(context).textTheme.labelMedium),
        IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: onNext,
            tooltip: 'Cap. siguiente'),
      ],
    );
  }
}

// ─── Controls ─────────────────────────────────────────────────────────────────

class _Controls extends StatelessWidget {
  final ReaderStatus status;
  final ReaderNotifier reader;
  const _Controls({required this.status, required this.reader});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (status == ReaderStatus.idle || status == ReaderStatus.error)
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Reproducir'),
              onPressed: reader.play,
            ),
          if (status == ReaderStatus.playing)
            ElevatedButton.icon(
              icon: const Icon(Icons.pause),
              label: const Text('Pausar'),
              onPressed: reader.pause,
            ),
          if (status == ReaderStatus.paused) ...[
            ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow),
              label: const Text('Continuar'),
              onPressed: reader.resume,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Detener'),
              onPressed: reader.stop,
            ),
          ],
          if (status == ReaderStatus.synthesizing)
            const SizedBox(
                height: 36,
                width: 36,
                child: CircularProgressIndicator(strokeWidth: 2)),
          if (status == ReaderStatus.playing) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.stop),
              label: const Text('Detener'),
              onPressed: reader.stop,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Gender toggle ────────────────────────────────────────────────────────────

class _GenderToggle extends StatelessWidget {
  final String gender;
  final ValueChanged<String> onToggle;
  const _GenderToggle({required this.gender, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Voz: '),
          ChoiceChip(
            label: const Text('♀ Femenina'),
            selected: gender == 'female',
            onSelected: (_) => onToggle('female'),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('♂ Masculina'),
            selected: gender == 'male',
            onSelected: (_) => onToggle('male'),
          ),
        ],
      ),
    );
  }
}

// ─── Download progress ────────────────────────────────────────────────────────

class _DownloadProgress extends StatelessWidget {
  final int done;
  final int total;
  const _DownloadProgress({required this.done, required this.total});

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? done / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          LinearProgressIndicator(value: progress),
          const SizedBox(height: 2),
          Text('Descargando $done / $total parrafos',
              style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

// ─── Speed selector ───────────────────────────────────────────────────────────

class _SpeedSelector extends StatelessWidget {
  final String currentRate;
  final ValueChanged<String> onChanged;

  const _SpeedSelector({required this.currentRate, required this.onChanged});

  static const _levels = [
    ('-20%', 'Lento'),
    ('+0%', 'Normal'),
    ('+25%', 'Rapido'),
    ('+50%', 'Veloz'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Vel: '),
          ..._levels.map((level) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: ChoiceChip(
                  label: Text(level.$2),
                  selected: currentRate == level.$1,
                  onSelected: (_) => onChanged(level.$1),
                ),
              )),
        ],
      ),
    );
  }
}

// ─── Status bar ───────────────────────────────────────────────────────────────

class _StatusBar extends StatelessWidget {
  final String message;
  final int sessionDataKb;

  const _StatusBar({required this.message, this.sessionDataKb = 0});

  @override
  Widget build(BuildContext context) {
    final hasMessage = message.isNotEmpty;
    final hasData = sessionDataKb > 0;
    if (!hasMessage && !hasData) return const SizedBox(height: 4);

    final dataMb = (sessionDataKb / 1024).toStringAsFixed(1);
    final parts = [
      if (hasMessage) message,
      if (hasData) 'Datos: $dataMb MB',
    ];

    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(parts.join('  ·  '),
          style: Theme.of(context).textTheme.labelSmall,
          textAlign: TextAlign.center),
    );
  }
}

// ─── Bookmarks sheet ──────────────────────────────────────────────────────────

class _BookmarksSheet extends StatelessWidget {
  final List<Map<String, dynamic>> bookmarks;
  final ValueChanged<Map<String, dynamic>> onJump;
  final ValueChanged<int> onDelete;
  const _BookmarksSheet(
      {required this.bookmarks, required this.onJump, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Marcadores',
              style: Theme.of(context).textTheme.titleMedium),
        ),
        if (bookmarks.isEmpty)
          const Expanded(
              child: Center(child: Text('No hay marcadores guardados'))),
        Expanded(
          child: ListView.builder(
            itemCount: bookmarks.length,
            itemBuilder: (ctx, i) {
              final b = bookmarks[i];
              return ListTile(
                leading: const Icon(Icons.bookmark),
                title: Text(
                    'Cap. ${(b['chapter_index'] as int) + 1} · Pár. ${(b['paragraph_index'] as int) + 1}'),
                subtitle:
                    b['note'] != null ? Text(b['note'] as String) : null,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete(b['id'] as int),
                ),
                onTap: () => onJump(b),
              );
            },
          ),
        ),
      ],
    );
  }
}
