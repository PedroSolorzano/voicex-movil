import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/reader_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/highlighted_text.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final int bookId;
  final String filePath;

  const ReaderScreen({super.key, required this.bookId, required this.filePath});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(readerProvider.notifier).loadBook(widget.bookId, widget.filePath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reader = ref.watch(readerProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final book = reader.book;

    if (book == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final chapter = reader.currentChapter;
    final para = reader.currentParagraph;

    return Scaffold(
      appBar: AppBar(
        title: Text(chapter?.title ?? '', overflow: TextOverflow.ellipsis),
        actions: [
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
          // Reading area
          Expanded(
            child: Container(
              color: const Color(0xFFF5E6C8), // sepia
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: para == null
                    ? const Text('Sin contenido')
                    : HighlightedText(
                        paragraph: para,
                        highlightedIndex: reader.highlightedSentence,
                        baseStyle: const TextStyle(
                          fontSize: 18,
                          height: 1.7,
                          fontFamily: 'Georgia',
                          color: Color(0xFF3E2723),
                        ),
                      ),
              ),
            ),
          ),
          // Paragraph navigation
          _ParagraphNav(
            paraIndex: reader.paragraphIndex,
            totalParas: chapter?.paragraphs.length ?? 0,
            onPrev: reader.paragraphIndex > 0
                ? () => ref
                    .read(readerProvider.notifier)
                    .navigateParagraph(reader.paragraphIndex - 1)
                : null,
            onNext: reader.paragraphIndex < (chapter?.paragraphs.length ?? 1) - 1
                ? () => ref
                    .read(readerProvider.notifier)
                    .navigateParagraph(reader.paragraphIndex + 1)
                : null,
          ),
          // Controls
          _Controls(status: reader.status, reader: ref.read(readerProvider.notifier)),
          // Gender toggle
          _GenderToggle(
            gender: settings?.gender ?? 'female',
            onToggle: (g) {
              final s = settings?.copyWith(gender: g);
              if (s != null) ref.read(settingsProvider.notifier).save(s);
            },
          ),
          // Status bar
          _StatusBar(message: reader.statusMessage),
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
              b['chapter_index'] as int, b['paragraph_index'] as int);
        },
        onDelete: (id) =>
            ref.read(readerProvider.notifier).deleteBookmark(id),
      ),
    );
  }
}

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

class _ParagraphNav extends StatelessWidget {
  final int paraIndex;
  final int totalParas;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _ParagraphNav(
      {required this.paraIndex,
      required this.totalParas,
      this.onPrev,
      this.onNext});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
            icon: const Icon(Icons.chevron_left),
            label: const Text('Párrafo'),
            onPressed: onPrev),
        Text('${paraIndex + 1} / $totalParas',
            style: Theme.of(context).textTheme.labelSmall),
        TextButton.icon(
            icon: const Icon(Icons.chevron_right),
            label: const Text('Párrafo'),
            onPressed: onNext),
      ],
    );
  }
}

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

class _StatusBar extends StatelessWidget {
  final String message;
  const _StatusBar({required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return const SizedBox(height: 4);
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(message,
          style: Theme.of(context).textTheme.labelSmall,
          textAlign: TextAlign.center),
    );
  }
}

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
                subtitle: b['note'] != null ? Text(b['note'] as String) : null,
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
