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
}

class ReaderNotifier extends Notifier<ReaderState> {
  final _progressRepo = ProgressRepo();
  final _bookmarkRepo = BookmarkRepo();
  final _cacheRepo = AudioCacheRepo();
  VoiceXAudioPlayer? _player;
  TTSProvider? _ttsProvider;
  bool _synthesizing = false;
  bool _downloadCancelled = false;
  // When jumping to a bookmark, holds the sentence to seek to after synthesis.
  int _pendingSentenceIdx = -1;

  @override
  ReaderState build() {
    ref.onDispose(cleanup);
    return const ReaderState();
  }

  Future<void> loadBook(int bookId, String filePath) async {
    try {
      final book = await parseEpub(filePath);
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
      state = state.copyWith(
        book: bookWithId,
        chapterIndex: chapterIdx,
        paragraphIndex: paraIdx,
        status: ReaderStatus.idle,
      );
      await _initPlayer();
    } catch (e) {
      state = state.copyWith(
        status: ReaderStatus.error,
        statusMessage: 'Error al cargar el libro: $e',
      );
    }
  }

  Future<void> _initPlayer() async {
    await _player?.dispose();
    _player = VoiceXAudioPlayer()
      ..onTick = _onTick
      ..onEnd = _onEnd;
  }

  AppSettings get _settings =>
      ref.read(settingsProvider).valueOrNull ?? AppSettings();

  void _onTick(int elapsedMs) {
    final marks = state.sentenceMarks;
    if (marks.isEmpty || !_settings.highlightSentences) return;

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

  Future<void> play() async {
    if (_synthesizing) return;
    final book = state.book;
    final para = state.currentParagraph;
    if (book == null || para == null) return;

    final settings = _settings;
    final voice =
        resolveVoice(settings.ttsProvider, book.language, settings.gender);
    // Edge TTS rate is part of the audio content — include it in the cache key.
    final speedHash = settings.ttsProvider == 'edge'
        ? settings.edgeRate
        : settings.androidSpeed.toString();

    state = state.copyWith(
        status: ReaderStatus.synthesizing, statusMessage: 'Sintetizando…');
    _synthesizing = true;

    try {
      String? filePath = await _cacheRepo.get(
          book.id!, state.chapterIndex, para.index, voice, speedHash);

      List<WordTimestamp> timestamps = [];

      if (filePath == null) {
        await _cacheRepo.evictLruUntilFit(300, settings.cacheMaxMb);

        _ttsProvider?.dispose();
        _ttsProvider = getProvider(settings);
        final result = await _ttsProvider!.synthesize(
          text: para.rawText,
          voice: voice,
          rate: settings.edgeRate,
          volume: settings.edgeVolume,
        );
        timestamps = result.timestamps;

        final cacheDir = await getTemporaryDirectory();
        final dest =
            '${cacheDir.path}/${book.id}_${state.chapterIndex}_${para.index}_${voice}_$speedHash.mp3';
        await File(result.filePath).copy(dest);
        final sizeKb = (await File(dest).length() / 1024).ceil();
        await _cacheRepo.save(book.id!, state.chapterIndex, para.index, voice,
            speedHash, dest, sizeKb);
        // Persist timestamps alongside the MP3 so highlight works on cache hits.
        await File('$dest.ts.json').writeAsString(jsonEncode(timestamps
            .map((t) => {
                  'word': t.word,
                  'offsetMs': t.offsetMs,
                  'durationMs': t.durationMs,
                })
            .toList()));
        filePath = dest;
        state = state.copyWith(sessionDataKb: state.sessionDataKb + sizeKb);
      } else {
        // Load timestamps from the sidecar file when serving from cache.
        final tsFile = File('$filePath.ts.json');
        if (await tsFile.exists()) {
          final raw = jsonDecode(await tsFile.readAsString()) as List;
          timestamps = raw
              .map((e) => WordTimestamp(
                    word: e['word'] as String,
                    offsetMs: e['offsetMs'] as int,
                    durationMs: e['durationMs'] as int,
                  ))
              .toList();
        }
      }

      final marks = _buildSentenceMarks(timestamps, para.sentences);

      // If jumping from a bookmark, seek to the saved sentence position.
      final seekSentenceIdx = _pendingSentenceIdx;
      _pendingSentenceIdx = -1;
      int startMs = 0;
      if (seekSentenceIdx >= 0 && marks.isNotEmpty) {
        final mark = marks.firstWhere(
          (m) => m.sentenceIdx >= seekSentenceIdx,
          orElse: () => marks.first,
        );
        startMs = mark.startMs;
      }

      state = state.copyWith(
        status: ReaderStatus.playing,
        statusMessage: 'Reproduciendo…',
        sentenceMarks: marks,
        highlightedSentence: seekSentenceIdx >= 0 ? seekSentenceIdx : -1,
      );
      await _player!.play(filePath, startMs: startMs);
    } catch (e) {
      state = state.copyWith(
          status: ReaderStatus.error, statusMessage: 'Error: $e');
    } finally {
      _synthesizing = false;
    }
  }

  Future<void> pause() async {
    await _player?.pause();
    state = state.copyWith(status: ReaderStatus.paused);
  }

  Future<void> resume() async {
    await _player?.resume();
    state = state.copyWith(status: ReaderStatus.playing);
  }

  Future<void> stop() async {
    await _player?.stop();
    state = state.copyWith(
      status: ReaderStatus.idle,
      highlightedSentence: -1,
      sentenceMarks: [],
    );
  }

  void _advanceParagraph() {
    final chapter = state.currentChapter;
    if (chapter == null) return;
    if (state.paragraphIndex < chapter.paragraphs.length - 1) {
      navigateParagraph(state.paragraphIndex + 1).then((_) => play());
    } else if (state.chapterIndex < (state.book?.chapters.length ?? 1) - 1) {
      navigateChapter(state.chapterIndex + 1, paragraph: 0).then((_) => play());
    } else {
      state = state.copyWith(
          statusMessage: 'Fin del libro', status: ReaderStatus.idle);
    }
  }

  Future<void> navigateChapter(int index, {int paragraph = 0}) async {
    await stop();
    state = state.copyWith(
        chapterIndex: index, paragraphIndex: paragraph, highlightedSentence: -1);
    await _saveProgress();
  }

  Future<void> navigateParagraph(int index) async {
    await stop();
    state = state.copyWith(paragraphIndex: index, highlightedSentence: -1);
    await _saveProgress();
  }

  Future<void> _saveProgress() async {
    final book = state.book;
    if (book?.id == null) return;
    await _progressRepo.save(
        book!.id!, state.chapterIndex, state.paragraphIndex);
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
    _pendingSentenceIdx = sentenceIndex;
    await navigateChapter(chapterIndex, paragraph: paragraphIndex);
    await play();
  }

  // Synthesizes all paragraphs of the current chapter and stores them as
  // pinned entries in getApplicationDocumentsDirectory() so the OS never clears them.
  Future<void> downloadChapter() async {
    final book = state.book;
    final chapter = state.currentChapter;
    if (book == null || chapter == null || state.isDownloading) return;

    final settings = _settings;
    final voice =
        resolveVoice(settings.ttsProvider, book.language, settings.gender);
    final speedHash = settings.ttsProvider == 'edge'
        ? settings.edgeRate
        : settings.androidSpeed.toString();
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
          book.id!, state.chapterIndex, para.index, voice, speedHash);
      if (alreadyPinned) {
        state = state.copyWith(downloadDone: state.downloadDone + 1);
        continue;
      }

      try {
        _ttsProvider?.dispose();
        _ttsProvider = getProvider(settings);
        final result = await _ttsProvider!.synthesize(
          text: para.rawText,
          voice: voice,
          rate: settings.edgeRate,
          volume: settings.edgeVolume,
        );

        final dest =
            '${docsDir.path}/dl_${book.id}_${state.chapterIndex}_${para.index}_${voice}_$speedHash.mp3';
        await File(result.filePath).copy(dest);
        await File('$dest.ts.json').writeAsString(jsonEncode(result.timestamps
            .map((t) => {
                  'word': t.word,
                  'offsetMs': t.offsetMs,
                  'durationMs': t.durationMs,
                })
            .toList()));
        final sizeKb = (await File(dest).length() / 1024).ceil();
        await _cacheRepo.savePin(book.id!, state.chapterIndex, para.index,
            voice, speedHash, dest, sizeKb);
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
    _player?.dispose();
    _ttsProvider?.dispose();
  }
}

final readerProvider =
    NotifierProvider<ReaderNotifier, ReaderState>(ReaderNotifier.new);
