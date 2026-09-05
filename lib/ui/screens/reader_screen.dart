import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../widgets/typography_sheet.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../../config/settings.dart';
import '../../tts/tts_factory.dart';
import '../../epub/models.dart';
import '../../epub/text_align.dart';
import '../providers/reader_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/highlighted_text.dart';
import '../widgets/reader_theme.dart';
import '../widgets/word_sheet.dart';

/// "41 min", "1 h 12 min". Used by both the download bar and its confirmation.
String _shortDuration(int seconds) {
  if (seconds < 60) return '$seconds s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}

/// Rough narration rate in characters per second at 1× for a neural voice.
/// Only used for the "time left" estimate, so approximate is fine.
const _charsPerSecond = 14.0;

/// How long after the last scroll event the reading position is persisted.
const _scrollSettleDelay = Duration(milliseconds: 900);

/// How much of a paragraph may hang off the top before it stops counting as
/// "where the reader is". 5 % of the viewport.
const _partiallyVisible = 0.05;

/// How much to pre-synthesize for offline listening.
enum _DownloadScope { chapter, ahead, book }

class ReaderScreen extends ConsumerStatefulWidget {
  final int bookId;

  /// Null when reached by deep link; resolved from the library on load.
  final String? filePath;

  const ReaderScreen({super.key, required this.bookId, this.filePath});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  final _scrollController = ItemScrollController();
  final _positionsListener = ItemPositionsListener.create();

  bool _chromeVisible = true;
  Timer? _scrollSettleTimer;

  /// True while an automatic scroll is animating.
  ///
  /// The auto-scroll fires its own scroll events, and acting on those was the
  /// bug behind "pausar y perder el sitio": the events queued a position update
  /// that landed *after* playback stopped and rewrote the position with the
  /// paragraph sitting above the one being read.
  bool _programmaticScroll = false;
  Timer? _programmaticScrollTimer;

  /// Separate from the book player: hearing one word must not move the
  /// listening position.
  final _wordPlayer = ja.AudioPlayer();
  int _lastParagraphIndex = -1;

  @override
  void initState() {
    super.initState();
    _positionsListener.itemPositions.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(readerProvider.notifier).loadBook(widget.bookId, widget.filePath);
    });
  }

  /// Último valor aplicado, para no llamar al sistema en cada build.
  bool? _pantallaEncendida;

  /// Mantiene la pantalla despierta mientras se lee, si el ajuste lo pide.
  void _aplicarWakelock(bool activo) {
    if (_pantallaEncendida == activo) return;
    _pantallaEncendida = activo;
    unawaited(WakelockPlus.toggle(enable: activo));
  }

  @override
  void dispose() {
    // Salir del lector devuelve el teléfono a su comportamiento normal.
    unawaited(WakelockPlus.disable());
    _wordPlayer.dispose();
    _programmaticScrollTimer?.cancel();
    _scrollSettleTimer?.cancel();
    _positionsListener.itemPositions.removeListener(_onScroll);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Tracks the topmost visible paragraph so silent reading advances the shared
  /// position. Without this, reading without audio saved nothing and reopening
  /// the book jumped back to wherever the audio had stopped.
  void _onScroll() {
    // Only a scroll the reader performed says anything about where they are.
    if (_programmaticScroll) return;

    final positions = _positionsListener.itemPositions.value;
    if (positions.isEmpty) return;

    // The first paragraph that is actually on screen, not merely clipping it.
    // Taking the topmost with any visible pixel picked the paragraph half
    // scrolled off the top, which is the one already read.
    final candidates = positions
        .where((p) => p.itemLeadingEdge >= -_partiallyVisible)
        .toList()
      ..sort((a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge));
    if (candidates.isEmpty) return;
    final index = candidates.first.index;

    _scrollSettleTimer?.cancel();
    _scrollSettleTimer = Timer(_scrollSettleDelay, () {
      if (!mounted) return;
      ref.read(readerProvider.notifier).updateReadingPosition(index);
    });
  }

  /// Height reserved under the text for the floating controls.
  ///
  /// Computed from what is actually on screen rather than measured, so it
  /// cannot oscillate between frames.
  double _bottomChromeHeight(ReaderState reader) {
    var height = 160.0; // progress bar + transport row + status line
    if (reader.highlightedSentence >= 0) height += 52; // repeat / loop
    if (reader.isDownloading) height += 64; // download progress + its label
    return height;
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    SystemChrome.setEnabledSystemUIMode(
      _chromeVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky,
    );
  }

  void _scrollTo(int index, {double alignment = 0.15}) {
    if (!_scrollController.isAttached) return;

    // Suppress position tracking for the whole animation plus a margin: the
    // list keeps emitting settling events for a beat after it stops.
    const duration = Duration(milliseconds: 350);
    _programmaticScroll = true;
    _scrollSettleTimer?.cancel();
    _programmaticScrollTimer?.cancel();
    _programmaticScrollTimer = Timer(duration + const Duration(milliseconds: 250),
        () => _programmaticScroll = false);

    _scrollController.scrollTo(
      index: index,
      alignment: alignment,
      duration: duration,
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reader = ref.watch(readerProvider);
    final settings = ref.watch(settingsProvider).valueOrNull ?? AppSettings();
    final book = reader.book;

    _aplicarWakelock(settings.keepScreenOn);

    final palette = ReaderPalette.of(
        settings.readerTheme, MediaQuery.platformBrightnessOf(context));

    ref.listen<ReaderState>(readerProvider, (prev, next) {
      final startedPlaying = prev?.status != next.status &&
          next.status == ReaderStatus.playing;

      // Playback started or stopped: drop anything the previous state queued,
      // so a pending update cannot be applied under the new one.
      if (prev?.status != next.status) {
        _scrollSettleTimer?.cancel();
      }

      final chapterChanged = prev?.chapterIndex != next.chapterIndex;
      final paragraphChanged = prev?.paragraphIndex != next.paragraphIndex;

      // Resuming brings the view back to what is being read. Without this,
      // scrolling away and pressing play left the highlight off screen: the
      // paragraph had not changed, so nothing scrolled.
      if (startedPlaying && settings.followAudioScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _lastParagraphIndex = next.paragraphIndex;
          _scrollTo(next.paragraphIndex);
        });
        return;
      }

      if (!chapterChanged && !paragraphChanged) return;

      // Follow along only while audio drives the position; during silent
      // reading the user owns the scroll.
      final shouldFollow = chapterChanged ||
          (settings.followAudioScroll && next.isOnAudio);
      if (shouldFollow && next.paragraphIndex != _lastParagraphIndex) {
        _lastParagraphIndex = next.paragraphIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollTo(next.paragraphIndex);
        });
      }
    });

    if (book == null) {
      return Scaffold(
        appBar: reader.status == ReaderStatus.error ? AppBar() : null,
        body: Center(
          child: reader.status == ReaderStatus.error
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(reader.statusMessage, textAlign: TextAlign.center),
                    ],
                  ),
                )
              : const CircularProgressIndicator(),
        ),
      );
    }

    if (book.chapters.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(book.title)),
        body: const Center(child: Text('El libro no tiene capítulos legibles')),
      );
    }

    final chapter = reader.currentChapter;
    final paragraphs = chapter?.paragraphs ?? const <Paragraph>[];

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          // ── Reading surface ─────────────────────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleChrome,
              child: paragraphs.isEmpty
                  ? Center(
                      child: Text('Sin contenido',
                          style: TextStyle(color: palette.muted)))
                  : ScrollablePositionedList.builder(
                      itemScrollController: _scrollController,
                      itemPositionsListener: _positionsListener,
                      itemCount: paragraphs.length,
                      padding: EdgeInsets.only(
                        left: settings.margin,
                        right: settings.margin,
                        // The top bar is a row of 48 dp icon buttons plus its
                        // own padding; 64 left the first line grazing it.
                        top: MediaQuery.paddingOf(context).top + 80,
                        // Must clear the whole bottom bar, which grows with the
                        // practice row and the download progress. Too little and
                        // the last lines of a chapter sit under the controls.
                        bottom: MediaQuery.paddingOf(context).bottom +
                            _bottomChromeHeight(reader),
                      ),
                      itemBuilder: (_, i) {
                        final para = paragraphs[i];
                        final isActive = i == reader.paragraphIndex;
                        return _ParagraphTile(
                          para: para,
                          isActive: isActive,
                          sentenceRange: isActive
                              ? _rangeForSentence(
                                  reader.sentenceRanges,
                                  reader.highlightedSentence)
                              : null,
                          wordRange: isActive ? reader.activeWord : null,
                          settings: settings,
                          palette: palette,
                          onTap: () => ref
                              .read(readerProvider.notifier)
                              .navigateParagraph(i),
                          onWordLongPress: (word) =>
                              _showWordSheet(context, word, book.language),
                        );
                      },
                    ),
            ),
          ),

          // ── Chrome ──────────────────────────────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            top: _chromeVisible ? 0 : -140,
            left: 0,
            right: 0,
            child: _TopBar(
              title: chapter?.title ?? book.title,
              palette: palette,
              onBack: () => context.pop(),
              onToc: () => _showToc(context),
              onBookmarks: () => _showBookmarks(context),
              onAddBookmark: () => _addBookmark(context),
              onSettings: () => context.push('/settings'),
              onTypography: () => showTypographySheet(context),
              isDownloading: reader.isDownloading,
              onCancelDownload:
                  ref.read(readerProvider.notifier).cancelDownload,
              onDownload: (scope) => _download(context, scope, settings),
            ),
          ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            bottom: _chromeVisible ? 0 : -220,
            left: 0,
            right: 0,
            child: _BottomBar(
              reader: reader,
              settings: settings,
              palette: palette,
              notifier: ref.read(readerProvider.notifier),
              onSpeedChanged: (speed) async {
                final updated = settings.copyWith(playbackSpeed: speed);
                await ref.read(settingsProvider.notifier).save(updated);
                await ref.read(readerProvider.notifier).setSpeed(speed);
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Pre-synthesizes audio so it can be heard away from the home server.
  Future<void> _download(
      BuildContext context, _DownloadScope scope, AppSettings settings) async {
    final notifier = ref.read(readerProvider.notifier);
    final reader = ref.read(readerProvider);
    final chapters = reader.book?.chapters.length ?? 0;
    final from = reader.chapterIndex;

    final (count, label) = switch (scope) {
      _DownloadScope.chapter => (1, 'este capítulo'),
      _DownloadScope.ahead => (
          settings.prefetchChapters,
          'los próximos ${settings.prefetchChapters} capítulos'
        ),
      _DownloadScope.book => (chapters - from, 'el resto del libro'),
    };

    // Estimate before starting: chapters in this book run to ~450 paragraphs,
    // so even "the next three" is over an hour with Kokoro. Confirm whenever
    // that is more than a couple of minutes, not just for a whole book.
    final book = reader.book;
    var paragraphs = 0;
    if (book != null) {
      for (var c = from; c < (from + count).clamp(0, chapters); c++) {
        paragraphs += book.chapters[c].paragraphs.length;
      }
    }
    final estimate =
        (paragraphs * ReaderNotifier.estimatedSecondsPerParagraph(settings))
            .round();

    if (estimate > 120) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Descargar $label'),
          content: Text(
              'Son $paragraphs párrafos: alrededor de ${_shortDuration(estimate)} '
              'de síntesis con ${providerLabel(settings.ttsProvider)}, y unos '
              '${(paragraphs * 0.25).round()} MB.\n\n'
              'Conviene dejar la app abierta mientras tanto.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Descargar')),
          ],
        ),
      );
      if (ok != true) return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Descargando $label…')));
    await notifier.downloadChapters(from, count);
  }

  /// Long-pressing a word offers to hear it, define it, or send it elsewhere.
  Future<void> _showWordSheet(
      BuildContext context, ({String text, int offset}) word, String language) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => WordSheet(
        word: word.text,
        language: language,
        onPronounce: () => _pronounceWord(word),
      ),
    );
  }

  /// Prefers the clip already on disk — instant and offline — and only asks the
  /// engine to synthesize the word when this paragraph has no audio yet.
  Future<bool> _pronounceWord(({String text, int offset}) word) async {
    final notifier = ref.read(readerProvider.notifier);

    final clip = notifier.wordClipAt(word.offset);
    if (clip != null) {
      try {
        await _wordPlayer.setAudioSource(ja.ClippingAudioSource(
          child: ja.AudioSource.file(clip.path),
          start: Duration(milliseconds: clip.startMs),
          end: Duration(milliseconds: clip.endMs),
        ));
        await _wordPlayer.play();
        return true;
      } catch (_) {
        // Fall through to synthesis rather than leaving the button dead.
      }
    }

    final path = await notifier.synthesizeWord(word.text);
    if (path == null) return false;
    try {
      await _wordPlayer.setFilePath(path);
      await _wordPlayer.play();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _addBookmark(BuildContext context) async {
    await ref.read(readerProvider.notifier).addBookmark();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Marcador guardado')));
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
                b['sentence_index'] as int? ?? 0,
              );
        },
        onDelete: (id) => ref.read(readerProvider.notifier).deleteBookmark(id),
      ),
    );
  }

  void _showToc(BuildContext context) {
    final reader = ref.read(readerProvider);
    final book = reader.book;
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
          currentIndex: reader.chapterIndex,
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

// ─── Paragraph ───────────────────────────────────────────────────────────────

/// Character range of [sentenceIndex] within the paragraph, if known.
(int, int)? _rangeForSentence(List<SentenceRange> ranges, int sentenceIndex) {
  if (sentenceIndex < 0) return null;
  for (final r in ranges) {
    if (r.index == sentenceIndex) return (r.start, r.end);
  }
  return null;
}

class _ParagraphTile extends StatefulWidget {
  final Paragraph para;
  final bool isActive;
  final (int, int)? sentenceRange;
  final (int, int)? wordRange;
  final AppSettings settings;
  final ReaderPalette palette;
  final VoidCallback onTap;
  final ValueChanged<({String text, int offset})> onWordLongPress;

  const _ParagraphTile({
    required this.para,
    required this.isActive,
    required this.sentenceRange,
    required this.wordRange,
    required this.settings,
    required this.palette,
    required this.onTap,
    required this.onWordLongPress,
  });

  @override
  State<_ParagraphTile> createState() => _ParagraphTileState();
}

class _ParagraphTileState extends State<_ParagraphTile> {
  final _textKey = GlobalKey();

  /// Maps a touch to the word under it, using the laid-out paragraph rather
  /// than a tappable span per word — which would make a whole chapter far more
  /// expensive to render.
  void _handleLongPress(LongPressStartDetails details) {
    final render = _textKey.currentContext?.findRenderObject();
    if (render is! RenderParagraph) return;

    final local = render.globalToLocal(details.globalPosition);
    final position = render.getPositionForOffset(local);
    final bounds = wordBoundaryAt(widget.para.rawText, position.offset);
    if (bounds == null) return;

    widget.onWordLongPress((
      text: widget.para.rawText.substring(bounds.$1, bounds.$2),
      offset: bounds.$1,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final para = widget.para;
    final settings = widget.settings;
    final palette = widget.palette;
    final isActive = widget.isActive;

    final bodyStyle = readerBodyStyle(settings, palette);
    final headingStyle = readerHeadingStyle(settings, palette);

    Widget content;
    if (para.isHeading) {
      content = Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Text(para.rawText, key: _textKey, style: headingStyle),
      );
    } else if (isActive) {
      content = HighlightedText(
        rawText: para.rawText,
        sentenceRange: widget.sentenceRange,
        wordRange: widget.wordRange,
        baseStyle: bodyStyle,
        palette: palette,
        textKey: _textKey,
      );
    } else {
      content = Text(para.rawText, key: _textKey, style: bodyStyle);
    }

    return Semantics(
      button: true,
      label: para.isHeading ? 'Título: ${para.rawText}' : null,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPressStart: _handleLongPress,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 14),
          padding: isActive
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
              : const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: isActive && !para.isHeading
              ? BoxDecoration(
                  color: palette.activeParagraph,
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          child: content,
        ),
      ),
    );
  }
}

// ─── Top bar ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  final ReaderPalette palette;
  final VoidCallback onBack, onToc, onBookmarks, onAddBookmark, onSettings;
  final VoidCallback onTypography;
  final ValueChanged<_DownloadScope> onDownload;
  final VoidCallback onCancelDownload;
  final bool isDownloading;

  const _TopBar({
    required this.title,
    required this.palette,
    required this.onBack,
    required this.onToc,
    required this.onBookmarks,
    required this.onAddBookmark,
    required this.onSettings,
    required this.onTypography,
    required this.onDownload,
    required this.onCancelDownload,
    required this.isDownloading,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.background,
      elevation: 2,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: 'Volver',
              color: palette.text,
              onPressed: onBack,
            ),
            Expanded(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: palette.text, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.toc),
              tooltip: 'Índice',
              color: palette.text,
              onPressed: onToc,
            ),
            if (isDownloading)
              IconButton(
                icon: const Icon(Icons.cancel_outlined),
                tooltip: 'Cancelar descarga',
                color: palette.text,
                onPressed: onCancelDownload,
              )
            else
              PopupMenuButton<_DownloadScope>(
                icon: Icon(Icons.download_outlined, color: palette.text),
                tooltip: 'Descargar para escuchar sin conexión',
                onSelected: onDownload,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: _DownloadScope.chapter,
                      child: Text('Este capítulo')),
                  PopupMenuItem(
                      value: _DownloadScope.ahead,
                      child: Text('Los próximos capítulos')),
                  PopupMenuItem(
                      value: _DownloadScope.book,
                      child: Text('Libro completo')),
                ],
              ),
            IconButton(
              icon: const Icon(Icons.bookmark_add_outlined),
              tooltip: 'Agregar marcador',
              color: palette.text,
              onPressed: onAddBookmark,
            ),
            IconButton(
              icon: const Icon(Icons.bookmarks_outlined),
              tooltip: 'Ver marcadores',
              color: palette.text,
              onPressed: onBookmarks,
            ),
            // Delante de Ajustes a propósito: es lo que más se toca, y hasta
            // ahora obligaba a salir del libro para llegar a ello.
            IconButton(
              icon: const Icon(Icons.text_fields),
              tooltip: 'Letra y márgenes',
              color: palette.text,
              onPressed: onTypography,
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Ajustes',
              color: palette.text,
              onPressed: onSettings,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom bar ──────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final ReaderState reader;
  final AppSettings settings;
  final ReaderPalette palette;
  final ReaderNotifier notifier;
  final ValueChanged<double> onSpeedChanged;

  const _BottomBar({
    required this.reader,
    required this.settings,
    required this.palette,
    required this.notifier,
    required this.onSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final progress = reader.progressFraction;
    final remaining = _remainingLabel(reader, settings);

    return Material(
      color: palette.background,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Un control, no un indicador: hasta ahora moverse por el libro
            // solo se podía por el índice de capítulos o párrafo a párrafo.
            _ProgressSlider(
                reader: reader, notifier: notifier, palette: palette),
            if (reader.isDownloading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Column(
                  children: [
                    LinearProgressIndicator(
                      value: reader.downloadTotal > 0
                          ? reader.downloadDone / reader.downloadTotal
                          : 0,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _downloadLabel(reader),
                      style: TextStyle(fontSize: 11, color: palette.muted),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const _ChapterStepIcon(forward: false),
                    tooltip: 'Capítulo anterior',
                    color: palette.text,
                    onPressed: reader.chapterIndex > 0
                        ? notifier.previousChapter
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous),
                    tooltip: 'Párrafo anterior',
                    color: palette.text,
                    onPressed: notifier.previousParagraph,
                  ),
                  _PlayButton(
                      reader: reader, notifier: notifier, palette: palette),
                  IconButton(
                    icon: const Icon(Icons.stop),
                    tooltip: 'Detener',
                    color: palette.text,
                    onPressed: reader.status == ReaderStatus.idle
                        ? null
                        : notifier.stop,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next),
                    tooltip: 'Párrafo siguiente',
                    color: palette.text,
                    onPressed: notifier.nextParagraph,
                  ),
                  IconButton(
                    icon: const _ChapterStepIcon(forward: true),
                    tooltip: 'Capítulo siguiente',
                    color: palette.text,
                    onPressed: reader.chapterIndex <
                            (reader.book?.chapters.length ?? 1) - 1
                        ? notifier.nextChapter
                        : null,
                  ),
                  _SpeedMenu(
                    current: settings.playbackSpeed,
                    palette: palette,
                    onChanged: onSpeedChanged,
                  ),
                ],
              ),
            ),
            // Shadowing controls: only meaningful once there is a sentence to
            // repeat, so they stay out of the way until then.
            if (reader.highlightedSentence >= 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.replay, size: 18),
                      label: const Text('Repetir'),
                      style: TextButton.styleFrom(foregroundColor: palette.text),
                      onPressed: notifier.repeatSentence,
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      avatar: Icon(Icons.loop,
                          size: 18,
                          color: reader.sentenceLoop ? null : palette.muted),
                      label: const Text('Bucle'),
                      selected: reader.sentenceLoop,
                      onSelected: (_) => notifier.toggleSentenceLoop(),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    [
                      '${(progress * 100).toStringAsFixed(0)}%',
                      if (remaining.isNotEmpty) remaining,
                      // Named by engine: what was downloaded with another one
                      // will not be used.
                      if (reader.downloadedChapters > 0)
                        '${reader.downloadedChapters} cap. en '
                            '${providerLabel(settings.ttsProvider)}',
                    ].join('  ·  '),
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                  Text(
                    [
                      if (reader.statusMessage.isNotEmpty) reader.statusMessage,
                      if (reader.engineLabel.isNotEmpty) reader.engineLabel,
                      if (reader.sessionDataKb > 0)
                        '${(reader.sessionDataKb / 1024).toStringAsFixed(1)} MB',
                    ].join('  ·  '),
                    style: TextStyle(fontSize: 11, color: palette.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "Descargando 120 / 1350 · faltan ~41 min · 3 fallidos".
  ///
  /// The bare paragraph count said nothing useful: a chapter of this book is
  /// ~450 paragraphs, so three of them are well over an hour with Kokoro.
  static String _downloadLabel(ReaderState reader) {
    final parts = <String>[
      'Descargando ${reader.downloadDone} / ${reader.downloadTotal}',
    ];

    final seconds = reader.downloadSecondsLeft;
    if (seconds > 0) parts.add('faltan ~${_shortDuration(seconds)}');
    if (reader.downloadFailed > 0) {
      parts.add('${reader.downloadFailed} fallidos');
    }
    if (reader.downloadEngineNotice.isNotEmpty) {
      parts.add(reader.downloadEngineNotice);
    }
    return parts.join('  ·  ');
  }

  /// Estimated listening time left, derived from remaining characters.
  static String _remainingLabel(ReaderState reader, AppSettings settings) {
    final book = reader.book;
    if (book == null) return '';
    var chars = 0;
    for (var c = reader.chapterIndex; c < book.chapters.length; c++) {
      final paras = book.chapters[c].paragraphs;
      final from = c == reader.chapterIndex ? reader.paragraphIndex : 0;
      for (var p = from; p < paras.length; p++) {
        chars += paras[p].rawText.length;
      }
    }
    if (chars == 0) return '';
    final seconds = chars / (_charsPerSecond * settings.playbackSpeed);
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return 'faltan ~$hours h $minutes min';
    return 'faltan ~$minutes min';
  }
}

/// Barra de progreso arrastrable.
///
/// Mientras se arrastra manda el valor local, no el del estado: sin eso el
/// pulgar da saltos, porque el estado solo cambia cuando se suelta.
class _ProgressSlider extends StatefulWidget {
  const _ProgressSlider({
    required this.reader,
    required this.notifier,
    required this.palette,
  });

  final ReaderState reader;
  final ReaderNotifier notifier;
  final ReaderPalette palette;

  @override
  State<_ProgressSlider> createState() => _ProgressSliderState();
}

class _ProgressSliderState extends State<_ProgressSlider> {
  double? _arrastrando;

  @override
  Widget build(BuildContext context) {
    final total = widget.reader.totalParagraphs;
    if (total <= 1) {
      return LinearProgressIndicator(
        value: widget.reader.progressFraction,
        minHeight: 2,
        backgroundColor: widget.palette.muted.withValues(alpha: 0.2),
      );
    }

    final valor =
        _arrastrando ?? widget.reader.globalParagraph.toDouble();
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        inactiveTrackColor: widget.palette.muted.withValues(alpha: 0.25),
      ),
      child: Slider(
        value: valor.clamp(0, (total - 1).toDouble()),
        max: (total - 1).toDouble(),
        // El porcentaje, no el número de párrafo: nadie piensa en párrafos.
        label: '${((valor / (total - 1)) * 100).round()} %',
        divisions: total > 1 ? total - 1 : null,
        onChanged: (v) => setState(() => _arrastrando = v),
        onChangeEnd: (v) {
          setState(() => _arrastrando = null);
          widget.notifier.jumpToGlobalIndex(v.round());
        },
      ),
    );
  }
}

/// Una página con un "+" o un "-", para que un salto de capítulo no se
/// confunda a simple vista con `skip_previous`/`skip_next` (párrafo), que
/// leen como controles de un reproductor de audio.
class _ChapterStepIcon extends StatelessWidget {
  final bool forward;
  const _ChapterStepIcon({required this.forward});

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.description_outlined, size: 22, color: color),
          Positioned(
            right: -3,
            bottom: -3,
            child: Icon(forward ? Icons.add_circle : Icons.remove_circle,
                size: 13, color: color),
          ),
        ],
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final ReaderState reader;
  final ReaderNotifier notifier;
  final ReaderPalette palette;

  const _PlayButton({
    required this.reader,
    required this.notifier,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    if (reader.status == ReaderStatus.synthesizing) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final isPlaying = reader.status == ReaderStatus.playing;
    return IconButton.filled(
      iconSize: 30,
      icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
      tooltip: isPlaying ? 'Pausar' : 'Reproducir',
      onPressed: () {
        if (isPlaying) {
          notifier.pause();
        } else if (reader.status == ReaderStatus.paused) {
          notifier.resume();
        } else {
          notifier.play();
        }
      },
    );
  }
}

class _SpeedMenu extends StatelessWidget {
  final double current;
  final ReaderPalette palette;
  final ValueChanged<double> onChanged;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  const _SpeedMenu({
    required this.current,
    required this.palette,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Velocidad',
      initialValue: current,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final s in _speeds)
          PopupMenuItem(value: s, child: Text('${s.toStringAsFixed(2)}×')),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Text(
          '${current.toStringAsFixed(2)}×',
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ─── Sheets ──────────────────────────────────────────────────────────────────

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
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Índice', style: Theme.of(context).textTheme.titleMedium),
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
                          : null,
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
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
                subtitle: Text('${ch.paragraphs.length} párrafos',
                    style: Theme.of(context).textTheme.bodySmall),
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

class _BookmarksSheet extends StatelessWidget {
  final List<Map<String, dynamic>> bookmarks;
  final ValueChanged<Map<String, dynamic>> onJump;
  final ValueChanged<int> onDelete;

  const _BookmarksSheet({
    required this.bookmarks,
    required this.onJump,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child:
              Text('Marcadores', style: Theme.of(context).textTheme.titleMedium),
        ),
        // Previously both the empty message and the list were rendered, giving
        // two Expanded siblings fighting for the same space.
        if (bookmarks.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 40),
            child: Text('No hay marcadores guardados'),
          )
        else
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: bookmarks.length,
              itemBuilder: (ctx, i) {
                final b = bookmarks[i];
                return ListTile(
                  leading: const Icon(Icons.bookmark),
                  title: Text('Cap. ${(b['chapter_index'] as int) + 1}'
                      ' · Pár. ${(b['paragraph_index'] as int) + 1}'),
                  subtitle: b['note'] != null ? Text(b['note'] as String) : null,
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Eliminar marcador',
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
