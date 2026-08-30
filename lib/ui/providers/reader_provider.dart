import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../audio/audio_player.dart';
import '../../config/settings.dart';
import '../../epub/models.dart';
import '../../epub/parser.dart';
import '../../storage/repositories.dart';
import '../../tts/models.dart';
import '../../tts/tts_factory.dart';
import '../../tts/tts_provider.dart';
import 'settings_provider.dart';

enum ReaderStatus { idle, synthesizing, playing, paused, error }

// Start time of each sentence in the current paragraph (from WordTimestamp data).
typedef SentenceMark = ({int startMs, int sentenceIdx});

/// Marks the audio encoding generation in the cache key. Bumping it retires
/// every previously cached file — used when the output format changed from
/// 48 kbit/s to 96 kbit/s. Playback speed is deliberately NOT part of the key:
/// speed is applied at playback time, so one file serves every speed.
const _cacheFormatTag = 'f96';

/// How often progress is persisted while audio is playing.
const _progressSaveInterval = Duration(seconds: 5);

class ReaderState {
  final Book? book;
  final int chapterIndex;
  final int paragraphIndex;
  final int highlightedSentence;
  final ReaderStatus status;
  final String statusMessage;
  final List<SentenceMark> sentenceMarks;
  final int sessionDataKb;
  final bool isDownloading;
  final int downloadDone;
  final int downloadTotal;

  const ReaderState({
    this.book,
    this.chapterIndex = 0,
    this.paragraphIndex = 0,
    this.highlightedSentence = -1,
    this.status = ReaderStatus.idle,
    this.statusMessage = '',
    this.sentenceMarks = const [],
    this.sessionDataKb = 0,
    this.isDownloading = false,
    this.downloadDone = 0,
    this.downloadTotal = 0,
  });

  ReaderState copyWith({
    Book? book,
    int? chapterIndex,
    int? paragraphIndex,
    int? highlightedSentence,
    ReaderStatus? status,
    String? statusMessage,
    List<SentenceMark>? sentenceMarks,
    int? sessionDataKb,
    bool? isDownloading,
    int? downloadDone,
    int? downloadTotal,
  }) =>
      ReaderState(
        book: book ?? this.book,
        chapterIndex: chapterIndex ?? this.chapterIndex,
        paragraphIndex: paragraphIndex ?? this.paragraphIndex,
        highlightedSentence: highlightedSentence ?? this.highlightedSentence,
        status: status ?? this.status,
        statusMessage: statusMessage ?? this.statusMessage,
        sentenceMarks: sentenceMarks ?? this.sentenceMarks,
        sessionDataKb: sessionDataKb ?? this.sessionDataKb,
        isDownloading: isDownloading ?? this.isDownloading,
        downloadDone: downloadDone ?? this.downloadDone,
        downloadTotal: downloadTotal ?? this.downloadTotal,
      );

  Chapter? get currentChapter => book?.chapters.elementAtOrNull(chapterIndex);
  Paragraph? get currentParagraph =>
      currentChapter?.paragraphs.elementAtOrNull(paragraphIndex);

  bool get isBusy =>
      status == ReaderStatus.playing || status == ReaderStatus.synthesizing;

  /// Fraction of the book already consumed, counting paragraphs across chapters.
  double get progressFraction {
    final b = book;
    if (b == null || b.chapters.isEmpty) return 0;
    var total = 0, done = 0;
    for (var c = 0; c < b.chapters.length; c++) {
      final n = b.chapters[c].paragraphs.length;
      if (c < chapterIndex) done += n;
      if (c == chapterIndex) done += paragraphIndex;
      total += n;
    }
    return total == 0 ? 0 : (done / total).clamp(0.0, 1.0);
  }
}

/// Result of making sure a paragraph's audio exists on disk.
typedef _Audio = ({String path, List<WordTimestamp> timestamps, int freshKb});

class ReaderNotifier extends Notifier<ReaderState> {
  final _progressRepo = ProgressRepo();
  final _bookmarkRepo = BookmarkRepo();
  final _cacheRepo = AudioCacheRepo();

  TTSProvider? _ttsProvider;
  String? _ttsProviderKind;

  bool _synthesizing = false;
  bool _downloadCancelled = false;

  /// When jumping to a bookmark or resuming, the sentence to seek to.
  int _pendingSentenceIdx = -1;
  int _pendingOffsetMs = 0;

  /// Guards against two prefetches racing, and lets navigation invalidate one
  /// that is already in flight.
  int _prefetchToken = 0;

  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  ReaderState build() {
    ref.onDispose(cleanup);
    return const ReaderState();
  }

  Future<void> loadBook(int bookId, String? filePath) async {
    try {
      // A deep link arrives without the path — look it up before parsing.
      final path = filePath ?? await _resolveFilePath(bookId);
      if (path == null) {
        state = state.copyWith(
          status: ReaderStatus.error,
          statusMessage: 'No se encontró el archivo de este libro.',
        );
        return;
      }
      // Parsing a large EPUB is CPU-heavy; keep it off the UI isolate.
      final book = await parseEpubInBackground(path);
      final progress = await _progressRepo.get(bookId);
      final bookWithId = book.copyWith(id: bookId);
      final maxChapter = book.chapters.isEmpty ? 0 : book.chapters.length - 1;
      final chapterIdx = progress.chapter.clamp(0, maxChapter);
      final maxPara = book.chapters.isEmpty
          ? 0
          : (book.chapters[chapterIdx].paragraphs.isEmpty
              ? 0
              : book.chapters[chapterIdx].paragraphs.length - 1);
      final paraIdx = progress.paragraph.clamp(0, maxPara);

      // Resume mid-paragraph rather than restarting it.
      _pendingSentenceIdx = progress.sentence;
      _pendingOffsetMs = progress.offsetMs;

      state = state.copyWith(
        book: bookWithId,
        chapterIndex: chapterIdx,
        paragraphIndex: paraIdx,
        highlightedSentence: progress.sentence > 0 ? progress.sentence : -1,
        status: ReaderStatus.idle,
      );
      _attachHandler();
    } catch (e) {
      state = state.copyWith(
        status: ReaderStatus.error,
        statusMessage: 'Error al cargar el libro: $e',
      );
    }
  }

  Future<String?> _resolveFilePath(int bookId) async {
    final row = await LibraryRepo().get(bookId);
    return row?['file_path'] as String?;
  }

  /// Wires this reader to the long-lived audio service handler. The handler is
  /// a singleton that outlives the screen, so callbacks are attached rather
  /// than a player being constructed.
  void _attachHandler() {
    audioHandler
      ..onTick = _onTick
      ..onEnd = _onEnd
      ..onNext = nextParagraph
      ..onPrevious = previousParagraph;
  }

  AppSettings get _settings =>
      ref.read(settingsProvider).valueOrNull ?? AppSettings();

  void _onTick(int elapsedMs) {
    final marks = state.sentenceMarks;
    if (marks.isNotEmpty && _settings.highlightSentences) {
      // Find the last sentence whose start time is <= elapsedMs.
      int sentIdx = marks.last.sentenceIdx;
      for (int i = 0; i < marks.length - 1; i++) {
        if (elapsedMs < marks[i + 1].startMs) {
          sentIdx = marks[i].sentenceIdx;
          break;
        }
      }
      if (sentIdx != state.highlightedSentence) {
        state = state.copyWith(highlightedSentence: sentIdx);
      }
    }

    // Throttled so a resume lands on the exact second without hammering SQLite.
    final now = DateTime.now();
    if (now.difference(_lastProgressSave) > _progressSaveInterval) {
      _lastProgressSave = now;
      unawaited(_saveProgress(offsetMs: elapsedMs));
    }
  }

  void _onEnd() {
    state = state.copyWith(
      status: ReaderStatus.idle,
      highlightedSentence: -1,
      sentenceMarks: [],
    );
    _advanceParagraph();
  }

  // Distributes WordTimestamps across sentences sequentially by word count,
  // producing the start time of each sentence for use in _onTick.
  List<SentenceMark> _buildSentenceMarks(
      List<WordTimestamp> timestamps, List<Sentence> sentences) {
    if (timestamps.isEmpty || sentences.isEmpty) return [];
    final result = <SentenceMark>[];
    int wordIdx = 0;
    for (final sentence in sentences) {
      if (wordIdx >= timestamps.length) break;
      result.add(
          (startMs: timestamps[wordIdx].offsetMs, sentenceIdx: sentence.index));
      wordIdx += sentence.text
          .split(RegExp(r'\s+'))
          .where((w) => w.isNotEmpty)
          .length;
    }
    return result;
  }

  /// Fallback for engines that report no word boundaries (the offline Android
  /// engine): spread sentences across the clip proportionally to their length.
  /// Approximate, but enough to keep the highlight moving instead of frozen.
  List<SentenceMark> _estimateSentenceMarks(
      List<Sentence> sentences, int durationMs) {
    if (sentences.isEmpty || durationMs <= 0) return [];
    final totalChars =
        sentences.fold<int>(0, (sum, s) => sum + s.text.length);
    if (totalChars == 0) return [];
    final marks = <SentenceMark>[];
    var acc = 0;
    for (final s in sentences) {
      marks.add((
        startMs: (durationMs * acc / totalChars).round(),
        sentenceIdx: s.index
      ));
      acc += s.text.length;
    }
    return marks;
  }

  String _cacheKeyVoice(AppSettings settings, Book book) =>
      settings.voiceFor(book.language);

  /// Reuses one provider instance instead of building a new one per paragraph.
  TTSProvider _provider(AppSettings settings) {
    if (_ttsProvider == null || _ttsProviderKind != settings.ttsProvider) {
      final old = _ttsProvider;
      _ttsProvider = getProvider(settings);
      _ttsProviderKind = settings.ttsProvider;
      if (old != null) unawaited(old.dispose());
    }
    return _ttsProvider!;
  }

  /// Returns the on-disk audio for [para], synthesizing and caching it on a miss.
  Future<_Audio> _ensureAudio(
      Book book, int chapterIdx, Paragraph para, AppSettings settings) async {
    final voice = _cacheKeyVoice(settings, book);

    final cached = await _cacheRepo.get(
        book.id!, chapterIdx, para.index, voice, _cacheFormatTag);
    if (cached != null) {
      return (
        path: cached,
        timestamps: await _readSidecar(cached),
        freshKb: 0
      );
    }

    await _cacheRepo.evictLruUntilFit(300, settings.cacheMaxMb);
    final result = await _provider(settings).synthesize(
      text: para.rawText,
      voice: voice,
      rate: settings.edgeRate,
      volume: settings.edgeVolume,
    );

    // Keep the real extension: the Android engine emits WAV, Edge emits MP3.
    final ext = result.filePath.split('.').last;
    final cacheDir = await getTemporaryDirectory();
    final dest = '${cacheDir.path}/'
        '${book.id}_${chapterIdx}_${para.index}_${voice}_$_cacheFormatTag.$ext';

    await File(result.filePath).copy(dest);
    // The provider's scratch file has served its purpose; leaving it behind
    // leaked one temp file per paragraph.
    try {
      await File(result.filePath).delete();
    } catch (_) {}

    final sizeKb = (await File(dest).length() / 1024).ceil();
    await _cacheRepo.save(
        book.id!, chapterIdx, para.index, voice, _cacheFormatTag, dest, sizeKb);
    await _writeSidecar(dest, result.timestamps);

    return (path: dest, timestamps: result.timestamps, freshKb: sizeKb);
  }

  Future<void> _writeSidecar(String dest, List<WordTimestamp> ts) async {
    await File('$dest.ts.json').writeAsString(jsonEncode(ts
        .map((t) => {
              'word': t.word,
              'offsetMs': t.offsetMs,
              'durationMs': t.durationMs,
            })
        .toList()));
  }

  Future<List<WordTimestamp>> _readSidecar(String path) async {
    try {
      final f = File('$path.ts.json');
      if (!await f.exists()) return [];
      final raw = jsonDecode(await f.readAsString()) as List;
      return raw
          .map((e) => WordTimestamp(
                word: e['word'] as String,
                offsetMs: e['offsetMs'] as int,
                durationMs: e['durationMs'] as int,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> play() async {
    if (_synthesizing) return;
    final book = state.book;
    final para = state.currentParagraph;
    if (book == null || para == null) return;

    final settings = _settings;
    state = state.copyWith(
        status: ReaderStatus.synthesizing, statusMessage: 'Sintetizando…');
    _synthesizing = true;

    try {
      final audio = await _ensureAudio(book, state.chapterIndex, para, settings);

      var marks = _buildSentenceMarks(audio.timestamps, para.sentences);

      // Resume / bookmark seek.
      final seekSentenceIdx = _pendingSentenceIdx;
      final pendingOffset = _pendingOffsetMs;
      _pendingSentenceIdx = -1;
      _pendingOffsetMs = 0;

      int startMs = 0;
      if (pendingOffset > 0) {
        startMs = pendingOffset;
      } else if (seekSentenceIdx > 0 && marks.isNotEmpty) {
        final mark = marks.firstWhere(
          (m) => m.sentenceIdx >= seekSentenceIdx,
          orElse: () => marks.first,
        );
        startMs = mark.startMs;
      }

      if (audio.freshKb > 0) {
        state = state.copyWith(sessionDataKb: state.sessionDataKb + audio.freshKb);
      }

      state = state.copyWith(
        status: ReaderStatus.playing,
        statusMessage: 'Reproduciendo…',
        sentenceMarks: marks,
        highlightedSentence: seekSentenceIdx > 0 ? seekSentenceIdx : -1,
      );

      _publishNowPlaying(book, para);
      await audioHandler.playFile(audio.path,
          startMs: startMs, speed: settings.playbackSpeed);

      // No word boundaries (offline engine): approximate from the real duration,
      // which is only known once the file is loaded.
      if (marks.isEmpty) {
        final dur = audioHandler.duration?.inMilliseconds ?? 0;
        marks = _estimateSentenceMarks(para.sentences, dur);
        if (marks.isNotEmpty) state = state.copyWith(sentenceMarks: marks);
      }

      _schedulePrefetch();
    } catch (e) {
      state = state.copyWith(
          status: ReaderStatus.error, statusMessage: _friendlyError(e));
    } finally {
      _synthesizing = false;
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('TimeoutException')) {
      return 'Sin conexión. Cambia a TTS de Android en Ajustes para leer sin internet.';
    }
    return 'Error: $s';
  }

  void _publishNowPlaying(Book book, Paragraph para) {
    final chapter = state.currentChapter;
    audioHandler.setNowPlaying(
      id: '${book.id}_${state.chapterIndex}_${para.index}',
      title: chapter?.title.isNotEmpty == true ? chapter!.title : book.title,
      album: book.title,
      artist: book.author,
    );
  }

  /// Synthesizes the next paragraph while the current one plays, so playback
  /// runs into it without the 1-2 s network gap that used to sit between them.
  void _schedulePrefetch() {
    final book = state.book;
    final chapter = state.currentChapter;
    if (book == null || chapter == null) return;

    final nextIdx = state.paragraphIndex + 1;
    if (nextIdx >= chapter.paragraphs.length) return;

    final token = ++_prefetchToken;
    final para = chapter.paragraphs[nextIdx];
    final chapterIdx = state.chapterIndex;
    final settings = _settings;

    unawaited(() async {
      try {
        final voice = _cacheKeyVoice(settings, book);
        final hit = await _cacheRepo.get(
            book.id!, chapterIdx, para.index, voice, _cacheFormatTag);
        if (hit != null || token != _prefetchToken) return;
        await _ensureAudio(book, chapterIdx, para, settings);
        dev.log('[Reader] Prefetched paragraph ${para.index}');
      } catch (e) {
        // A failed prefetch is invisible: play() will retry synchronously.
        dev.log('[Reader] Prefetch of ${para.index} failed: $e');
      }
    }());
  }

  Future<void> pause() async {
    await audioHandler.pause();
    state = state.copyWith(status: ReaderStatus.paused);
    await _saveProgress(offsetMs: audioHandler.elapsedMs);
  }

  Future<void> resume() async {
    await audioHandler.play();
    state = state.copyWith(status: ReaderStatus.playing);
  }

  Future<void> stop() async {
    await _saveProgress(offsetMs: audioHandler.elapsedMs);
    await audioHandler.stop();
    state = state.copyWith(
      status: ReaderStatus.idle,
      highlightedSentence: -1,
      sentenceMarks: [],
    );
  }

  /// Applies a new playback speed immediately, without re-synthesizing.
  Future<void> setSpeed(double speed) async {
    await audioHandler.setSpeed(speed);
  }

  void _advanceParagraph() {
    final chapter = state.currentChapter;
    if (chapter == null) return;
    if (state.paragraphIndex < chapter.paragraphs.length - 1) {
      unawaited(navigateParagraph(state.paragraphIndex + 1).then((_) => play()));
    } else if (state.chapterIndex < (state.book?.chapters.length ?? 1) - 1) {
      unawaited(
          navigateChapter(state.chapterIndex + 1, paragraph: 0).then((_) => play()));
    } else {
      state = state.copyWith(
          statusMessage: 'Fin del libro', status: ReaderStatus.idle);
    }
  }

  /// Lock-screen "next": jump forward a paragraph and keep playing.
  Future<void> nextParagraph() async {
    final wasPlaying = state.isBusy;
    final chapter = state.currentChapter;
    if (chapter == null) return;
    if (state.paragraphIndex < chapter.paragraphs.length - 1) {
      await navigateParagraph(state.paragraphIndex + 1);
    } else if (state.chapterIndex < (state.book?.chapters.length ?? 1) - 1) {
      await navigateChapter(state.chapterIndex + 1, paragraph: 0);
    } else {
      return;
    }
    if (wasPlaying) await play();
  }

  /// Lock-screen "previous": back one paragraph, or to the end of the previous
  /// chapter when already at the top of this one.
  Future<void> previousParagraph() async {
    final wasPlaying = state.isBusy;
    if (state.paragraphIndex > 0) {
      await navigateParagraph(state.paragraphIndex - 1);
    } else if (state.chapterIndex > 0) {
      final prev = state.book?.chapters.elementAtOrNull(state.chapterIndex - 1);
      final lastPara =
          prev == null || prev.paragraphs.isEmpty ? 0 : prev.paragraphs.length - 1;
      await navigateChapter(state.chapterIndex - 1, paragraph: lastPara);
    } else {
      return;
    }
    if (wasPlaying) await play();
  }

  Future<void> navigateChapter(int index, {int paragraph = 0}) async {
    _prefetchToken++;
    await stop();
    state = state.copyWith(
        chapterIndex: index, paragraphIndex: paragraph, highlightedSentence: -1);
    await _saveProgress();
  }

  Future<void> navigateParagraph(int index) async {
    _prefetchToken++;
    await stop();
    state = state.copyWith(paragraphIndex: index, highlightedSentence: -1);
    await _saveProgress();
  }

  /// Called while the user scrolls in silent reading mode. Updates the shared
  /// position without touching playback, so picking up the audio later resumes
  /// exactly where the eyes stopped.
  Future<void> updateReadingPosition(int paragraphIndex) async {
    if (state.isBusy) return;
    if (paragraphIndex == state.paragraphIndex) return;
    final chapter = state.currentChapter;
    if (chapter == null ||
        paragraphIndex < 0 ||
        paragraphIndex >= chapter.paragraphs.length) {
      return;
    }
    state = state.copyWith(paragraphIndex: paragraphIndex);
    await _saveProgress();
  }

  Future<void> _saveProgress({int offsetMs = 0}) async {
    final book = state.book;
    if (book?.id == null) return;
    await _progressRepo.save(
      book!.id!,
      state.chapterIndex,
      state.paragraphIndex,
      sentenceIndex:
          state.highlightedSentence < 0 ? 0 : state.highlightedSentence,
      offsetMs: offsetMs,
    );
  }

  Future<void> addBookmark() async {
    final book = state.book;
    if (book?.id == null) return;
    final sentenceIdx = state.highlightedSentence < 0 ? 0 : state.highlightedSentence;
    await _bookmarkRepo.add(
      book!.id!,
      state.chapterIndex,
      state.paragraphIndex,
      sentenceIndex: sentenceIdx,
    );
  }

  Future<List<Map<String, dynamic>>> getBookmarks() async {
    final book = state.book;
    if (book?.id == null) return [];
    return _bookmarkRepo.listForBook(book!.id!);
  }

  Future<void> deleteBookmark(int id) async {
    await _bookmarkRepo.delete(id);
  }

  Future<void> jumpToBookmark(
      int chapterIndex, int paragraphIndex, int sentenceIndex) async {
    await navigateChapter(chapterIndex, paragraph: paragraphIndex);
    _pendingSentenceIdx = sentenceIndex;
    await play();
  }

  // Synthesizes all paragraphs of the current chapter and stores them as
  // pinned entries in getApplicationDocumentsDirectory() so the OS never clears them.
  Future<void> downloadChapter() async {
    final book = state.book;
    final chapter = state.currentChapter;
    if (book == null || chapter == null || state.isDownloading) return;

    final settings = _settings;
    final voice = _cacheKeyVoice(settings, book);
    final docsDir = await getApplicationDocumentsDirectory();

    _downloadCancelled = false;
    state = state.copyWith(
      isDownloading: true,
      downloadDone: 0,
      downloadTotal: chapter.paragraphs.length,
    );

    for (final para in chapter.paragraphs) {
      if (_downloadCancelled) break;

      final alreadyPinned = await _cacheRepo.isPinnedParagraph(
          book.id!, state.chapterIndex, para.index, voice, _cacheFormatTag);
      if (alreadyPinned) {
        state = state.copyWith(downloadDone: state.downloadDone + 1);
        continue;
      }

      try {
        final result = await _provider(settings).synthesize(
          text: para.rawText,
          voice: voice,
          rate: settings.edgeRate,
          volume: settings.edgeVolume,
        );

        final ext = result.filePath.split('.').last;
        final dest = '${docsDir.path}/dl_${book.id}_${state.chapterIndex}_'
            '${para.index}_${voice}_$_cacheFormatTag.$ext';
        await File(result.filePath).copy(dest);
        try {
          await File(result.filePath).delete();
        } catch (_) {}

        await _writeSidecar(dest, result.timestamps);
        final sizeKb = (await File(dest).length() / 1024).ceil();
        await _cacheRepo.savePin(book.id!, state.chapterIndex, para.index,
            voice, _cacheFormatTag, dest, sizeKb);
      } catch (e) {
        dev.log('[Reader] Download para ${para.index} failed: $e');
      }

      state = state.copyWith(downloadDone: state.downloadDone + 1);
    }

    state = state.copyWith(isDownloading: false);
  }

  void cancelDownload() {
    _downloadCancelled = true;
    state = state.copyWith(isDownloading: false);
  }

  void cleanup() {
    _prefetchToken++;
    // The handler is a long-lived singleton shared with the media service —
    // detach this screen's callbacks rather than disposing it.
    audioHandler.detach();
    unawaited(audioHandler.stop());
    unawaited(_ttsProvider?.dispose() ?? Future.value());
    _ttsProvider = null;
    _ttsProviderKind = null;
  }
}

final readerProvider =
    NotifierProvider<ReaderNotifier, ReaderState>(ReaderNotifier.new);
