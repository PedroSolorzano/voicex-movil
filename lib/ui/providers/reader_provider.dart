import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../audio/audio_player.dart';
import '../../config/settings.dart';
import '../../epub/models.dart';
import '../../epub/parser.dart';
import '../../storage/repositories.dart';
import '../../tts/tts_factory.dart';
import '../../tts/tts_provider.dart';
import 'settings_provider.dart';

enum ReaderStatus { idle, synthesizing, playing, paused, error }

class ReaderState {
  final Book? book;
  final int chapterIndex;
  final int paragraphIndex;
  final int highlightedSentence;
  final ReaderStatus status;
  final String statusMessage;

  const ReaderState({
    this.book,
    this.chapterIndex = 0,
    this.paragraphIndex = 0,
    this.highlightedSentence = -1,
    this.status = ReaderStatus.idle,
    this.statusMessage = '',
  });

  ReaderState copyWith({
    Book? book,
    int? chapterIndex,
    int? paragraphIndex,
    int? highlightedSentence,
    ReaderStatus? status,
    String? statusMessage,
  }) =>
      ReaderState(
        book: book ?? this.book,
        chapterIndex: chapterIndex ?? this.chapterIndex,
        paragraphIndex: paragraphIndex ?? this.paragraphIndex,
        highlightedSentence: highlightedSentence ?? this.highlightedSentence,
        status: status ?? this.status,
        statusMessage: statusMessage ?? this.statusMessage,
      );

  Chapter? get currentChapter => book?.chapters[chapterIndex];
  Paragraph? get currentParagraph =>
      currentChapter?.paragraphs[paragraphIndex];
}

class ReaderNotifier extends Notifier<ReaderState> {
  final _progressRepo = ProgressRepo();
  final _bookmarkRepo = BookmarkRepo();
  final _cacheRepo = AudioCacheRepo();
  VoiceXAudioPlayer? _player;
  TTSProvider? _ttsProvider;
  bool _synthesizing = false;

  @override
  ReaderState build() {
    ref.onDispose(cleanup);
    return const ReaderState();
  }

  Future<void> loadBook(int bookId, String filePath) async {
    final book = await parseEpub(filePath);
    final progress = await _progressRepo.get(bookId);
    final bookWithId = book.copyWith(id: bookId);
    state = state.copyWith(
      book: bookWithId,
      chapterIndex: progress.chapter,
      paragraphIndex: progress.paragraph,
      status: ReaderStatus.idle,
    );
    await _initPlayer();
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
    final para = state.currentParagraph;
    if (para == null || !_settings.highlightSentences) return;
    final sentences = para.sentences;
    // Find sentence active at elapsedMs using word timestamps
    // (simplified: linear scan by approximate time per sentence)
    final totalMs = sentences.length * 2000;
    final idx =
        ((elapsedMs / totalMs) * sentences.length).floor().clamp(0, sentences.length - 1);
    if (idx != state.highlightedSentence) {
      state = state.copyWith(highlightedSentence: idx);
    }
  }

  void _onEnd() {
    state = state.copyWith(
        status: ReaderStatus.idle, highlightedSentence: -1);
    _advanceParagraph();
  }

  Future<void> play() async {
    if (_synthesizing) return;
    final book = state.book;
    final para = state.currentParagraph;
    if (book == null || para == null) return;

    final settings = _settings;
    final voice =
        resolveVoice(settings.ttsProvider, book.language, settings.gender);
    final speedHash = settings.androidSpeed.toString();

    state = state.copyWith(
        status: ReaderStatus.synthesizing, statusMessage: 'Sintetizando…');
    _synthesizing = true;

    try {
      // Check cache
      String? filePath = await _cacheRepo.get(
          book.id!, state.chapterIndex, para.index, voice, speedHash);

      if (filePath == null) {
        // Estimate size and evict if needed
        await _cacheRepo.evictLruUntilFit(300, settings.cacheMaxMb);

        _ttsProvider?.dispose();
        _ttsProvider = getProvider(settings);
        final result = await _ttsProvider!.synthesize(
          text: para.rawText,
          voice: voice,
          rate: settings.edgeRate,
          volume: settings.edgeVolume,
        );

        // Move to cache dir
        final cacheDir = await getTemporaryDirectory();
        final dest =
            '${cacheDir.path}/${book.id}_${state.chapterIndex}_${para.index}_${voice}_$speedHash.mp3';
        await File(result.filePath).copy(dest);
        final sizeKb = (await File(dest).length() / 1024).ceil();
        await _cacheRepo.save(book.id!, state.chapterIndex, para.index, voice,
            speedHash, dest, sizeKb);
        filePath = dest;
      }

      state = state.copyWith(
          status: ReaderStatus.playing, statusMessage: 'Reproduciendo…');
      await _player!.play(filePath);
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
        status: ReaderStatus.idle, highlightedSentence: -1);
  }

  void _advanceParagraph() {
    final chapter = state.currentChapter;
    if (chapter == null) return;
    if (state.paragraphIndex < chapter.paragraphs.length - 1) {
      navigateParagraph(state.paragraphIndex + 1);
    } else if (state.chapterIndex < (state.book?.chapters.length ?? 1) - 1) {
      navigateChapter(state.chapterIndex + 1, paragraph: 0);
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
    await _bookmarkRepo.add(
        book!.id!, state.chapterIndex, state.paragraphIndex);
  }

  Future<List<Map<String, dynamic>>> getBookmarks() async {
    final book = state.book;
    if (book?.id == null) return [];
    return _bookmarkRepo.listForBook(book!.id!);
  }

  Future<void> deleteBookmark(int id) async {
    await _bookmarkRepo.delete(id);
  }

  Future<void> jumpToBookmark(int chapterIndex, int paragraphIndex) async {
    await navigateChapter(chapterIndex, paragraph: paragraphIndex);
  }

  void cleanup() {
    _player?.dispose();
    _ttsProvider?.dispose();
  }
}

final readerProvider =
    NotifierProvider<ReaderNotifier, ReaderState>(ReaderNotifier.new);
