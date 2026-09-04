import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../audio/audio_player.dart';
import '../../config/settings.dart';
import '../../epub/models.dart';
import '../../epub/parser.dart';
import '../../epub/text_align.dart';
import '../../services/reporter.dart';
import '../../storage/repositories.dart';
import '../../tts/models.dart';
import '../../tts/tts_factory.dart';
import '../../tts/tts_provider.dart';
import '../../tts/chatterbox_tts_provider.dart';
import '../../tts/kokoro_tts_provider.dart';
import '../../tts/piper_tts_provider.dart';
import '../../tts/server_health.dart';
import 'settings_provider.dart';

enum ReaderStatus { idle, synthesizing, playing, paused, error }

// Start time of each sentence in the current paragraph (from WordTimestamp data).
typedef SentenceMark = ({int startMs, int sentenceIdx});

/// Marks the audio encoding generation in the cache key. Bumping it retires
/// every previously cached file — used when the output format changed from
/// 48 kbit/s to 96 kbit/s. Playback speed is deliberately NOT part of the key:
/// speed is applied at playback time, so one file serves every speed.
///
/// **Deliberately not bumped when Kokoro moved from MP3 to AAC.** The old files
/// still play, and AAC-LC at 94 kbit/s is not a downgrade from MP3 at 130, so
/// there is nothing to retire — while bumping would have orphaned every
/// download already on the phone, which is the one thing this cache must never
/// do. The two codecs coexist: the extension is stored per file.
const _cacheFormatTag = 'f96';

/// How often progress is persisted while audio is playing.
const _progressSaveInterval = Duration(seconds: 5);

/// Whether a connection is one the user pays for by the megabyte.
///
/// Phrased as a deny list rather than "is it WiFi", which is what it used to
/// be. On Android a VPN takes over the reported transport, so a phone running
/// one can answer `[vpn]` and nothing else — and the old test then switched off
/// prefetching while sitting on the home WiFi, purely as a side effect of
/// having installed a VPN client. The deny list is also the honest reading of
/// what the setting promises on screen: "nunca usa datos móviles".
///
/// **Known gap, deliberately left open:** a VPN over mobile data can likewise
/// report `[vpn]` alone and hide the metered transport underneath, so this can
/// let a prefetch through on a metered link. Closing it properly means asking
/// Android for `NET_CAPABILITY_NOT_METERED` over a platform channel. Until
/// then, the exposure is bounded — prefetch only runs with a self-hosted server
/// configured.
@visibleForTesting
bool isLikelyMetered(List<ConnectivityResult> connection) =>
    connection.contains(ConnectivityResult.mobile) ||
    connection.contains(ConnectivityResult.none) ||
    connection.isEmpty;

class ReaderState {
  final Book? book;
  final int chapterIndex;
  final int paragraphIndex;
  final int highlightedSentence;
  final ReaderStatus status;
  final String statusMessage;
  final List<SentenceMark> sentenceMarks;
  final List<WordMark> wordMarks;
  final List<SentenceRange> sentenceRanges;
  /// Character range of the word being spoken, or null.
  final (int, int)? activeWord;
  final int sessionDataKb;
  /// Engine actually used for the last synthesis, so a fallback is visible.
  final String engineLabel;

  /// On-disk audio backing the current paragraph. Lets a single word be replayed
  /// from the clip already downloaded, with no network round trip.
  final String? currentAudioPath;

  /// Repeats the active sentence instead of moving on — the shadowing loop.
  final bool sentenceLoop;

  /// Chapters fully downloaded **for the engine currently selected**. Caches
  /// are deliberately separate per engine, so a count that ignored the engine
  /// would promise audio that will not be used.
  final int downloadedChapters;
  final bool isDownloading;
  final int downloadDone;
  final int downloadTotal;

  /// Paragraphs that failed during the current download. A silent failure used
  /// to let the bar reach 100 % having written nothing.
  final int downloadFailed;

  /// Seconds per paragraph observed so far, for the time estimate.
  final double downloadSecondsPerParagraph;

  const ReaderState({
    this.book,
    this.chapterIndex = 0,
    this.paragraphIndex = 0,
    this.highlightedSentence = -1,
    this.status = ReaderStatus.idle,
    this.statusMessage = '',
    this.sentenceMarks = const [],
    this.wordMarks = const [],
    this.sentenceRanges = const [],
    this.activeWord,
    this.sessionDataKb = 0,
    this.engineLabel = '',
    this.currentAudioPath,
    this.sentenceLoop = false,
    this.downloadedChapters = 0,
    this.isDownloading = false,
    this.downloadDone = 0,
    this.downloadTotal = 0,
    this.downloadFailed = 0,
    this.downloadSecondsPerParagraph = 0,
  });

  ReaderState copyWith({
    Book? book,
    int? chapterIndex,
    int? paragraphIndex,
    int? highlightedSentence,
    ReaderStatus? status,
    String? statusMessage,
    List<SentenceMark>? sentenceMarks,
    List<WordMark>? wordMarks,
    List<SentenceRange>? sentenceRanges,
    (int, int)? activeWord,
    bool clearActiveWord = false,
    int? sessionDataKb,
    String? engineLabel,
    String? currentAudioPath,
    bool? sentenceLoop,
    int? downloadedChapters,
    bool? isDownloading,
    int? downloadDone,
    int? downloadTotal,
    int? downloadFailed,
    double? downloadSecondsPerParagraph,
  }) =>
      ReaderState(
        book: book ?? this.book,
        chapterIndex: chapterIndex ?? this.chapterIndex,
        paragraphIndex: paragraphIndex ?? this.paragraphIndex,
        highlightedSentence: highlightedSentence ?? this.highlightedSentence,
        status: status ?? this.status,
        statusMessage: statusMessage ?? this.statusMessage,
        sentenceMarks: sentenceMarks ?? this.sentenceMarks,
        wordMarks: wordMarks ?? this.wordMarks,
        sentenceRanges: sentenceRanges ?? this.sentenceRanges,
        activeWord: clearActiveWord ? null : (activeWord ?? this.activeWord),
        sessionDataKb: sessionDataKb ?? this.sessionDataKb,
        engineLabel: engineLabel ?? this.engineLabel,
        currentAudioPath: currentAudioPath ?? this.currentAudioPath,
        sentenceLoop: sentenceLoop ?? this.sentenceLoop,
        downloadedChapters: downloadedChapters ?? this.downloadedChapters,
        isDownloading: isDownloading ?? this.isDownloading,
        downloadDone: downloadDone ?? this.downloadDone,
        downloadTotal: downloadTotal ?? this.downloadTotal,
        downloadFailed: downloadFailed ?? this.downloadFailed,
        downloadSecondsPerParagraph:
            downloadSecondsPerParagraph ?? this.downloadSecondsPerParagraph,
      );

  /// Estimated seconds left in the current download.
  int get downloadSecondsLeft {
    if (!isDownloading || downloadSecondsPerParagraph <= 0) return 0;
    final left = downloadTotal - downloadDone;
    return (left * downloadSecondsPerParagraph).round();
  }

  Chapter? get currentChapter => book?.chapters.elementAtOrNull(chapterIndex);
  Paragraph? get currentParagraph =>
      currentChapter?.paragraphs.elementAtOrNull(paragraphIndex);

  bool get isBusy =>
      status == ReaderStatus.playing || status == ReaderStatus.synthesizing;

  /// True whenever a clip is loaded and the reader is sitting on it — playing,
  /// about to play, or paused part-way through.
  ///
  /// Distinct from [isBusy] because *paused* matters here: pausing and then
  /// scrolling used to move the reading position, and resuming carried on with
  /// the old clip, so the highlight ended up on one paragraph while the audio
  /// was reading another.
  bool get isOnAudio =>
      isBusy || status == ReaderStatus.paused;

  /// Fraction of the book already consumed, counting paragraphs across chapters.
  /// Párrafos del libro entero, y en cuál va la lectura. Los necesita la barra
  /// de progreso para poder arrastrarse.
  int get totalParagraphs =>
      book?.chapters.fold<int>(0, (sum, c) => sum + c.paragraphs.length) ?? 0;

  int get globalParagraph {
    final b = book;
    if (b == null) return 0;
    var done = 0;
    for (var c = 0; c < chapterIndex && c < b.chapters.length; c++) {
      done += b.chapters[c].paragraphs.length;
    }
    return done + paragraphIndex;
  }

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

  /// The engine used by interactive playback ([play], previews). Never
  /// shared with a download: `downloadChapters` keeps its own local
  /// instance, because switching engine here disposes the old one
  /// (`_provider`), and a download mid-`synthesize()` on that old instance
  /// would have its connection pulled out from under it -- that used to
  /// make "download with Kokoro, then try another engine" fail with no
  /// clear reason.
  TTSProvider? _ttsProvider;
  String? _ttsProviderKind;

  bool _synthesizing = false;
  bool _downloadCancelled = false;

  /// True from the first play until the reader presses Stop or leaves the book.
  ///
  /// Advancing between paragraphs passes through a brief "stopped" state, and
  /// judging by status alone left a window there in which a stray scroll event
  /// could rewrite the reading position. A session outlives those transitions.
  bool _listening = false;

  /// Where the clip currently in the player came from. Resuming checks against
  /// this so the highlight can never end up on a different paragraph than the
  /// one being spoken.
  int _loadedChapter = -1;
  int _loadedParagraph = -1;

  /// Cover art path, for the lock-screen player. Lives in the books table, not
  /// in the parsed Book, so it is fetched separately on load.
  String? _coverPath;

  /// When jumping to a bookmark or resuming, the sentence to seek to.
  int _pendingSentenceIdx = -1;
  int _pendingOffsetMs = 0;

  /// Guards against two prefetches racing, and lets navigation invalidate one
  /// that is already in flight.
  int _prefetchToken = 0;

  DateTime _lastProgressSave = DateTime.fromMillisecondsSinceEpoch(0);

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  ReaderState build() {
    ref.onDispose(cleanup);
    // Nothing used to invalidate the health verdict when the network changed:
    // resetHealthCache had a single caller, the button in Ajustes. So walking
    // out of the house, or back into coverage, dragged a stale verdict along
    // until it aged out. A change of network is the one moment where the old
    // answer is guaranteed to be worthless.
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((_) {
      resetServerHealthCache();
      unawaited(maybePrefetchAhead());
      // Los reportes encolados esperan exactamente a este momento: se generan
      // cuando no hay servidor y salen cuando vuelve a haberlo.
      unawaited(Reporter.flush());
    });
    return const ReaderState();
  }

  Future<void> loadBook(int bookId, String? filePath) async {
    try {
      // A deep link arrives without the path — look it up before parsing.
      final row = await LibraryRepo().get(bookId);
      _coverPath = row?['cover_path'] as String?;
      final path = filePath ?? (row?['file_path'] as String?);
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

      // Backfill the book length so the library can draw a progress bar
      // without opening the EPUB again.
      unawaited(LibraryRepo()
          .updateTotalParagraphs(bookId, _totalParagraphs(bookWithId)));

      unawaited(refreshDownloadedCount());

      // Fire-and-forget: fills the offline cache while at home, and quietly
      // does nothing when the conditions are not met.
      unawaited(maybePrefetchAhead());
    } catch (e) {
      state = state.copyWith(
        status: ReaderStatus.error,
        statusMessage: 'Error al cargar el libro: $e',
      );
    }
  }

  static int _totalParagraphs(Book book) =>
      book.chapters.fold<int>(0, (sum, c) => sum + c.paragraphs.length);

  /// Absolute paragraph index across the whole book.
  int _globalIndex() {
    final book = state.book;
    if (book == null) return 0;
    var total = 0;
    for (var c = 0; c < state.chapterIndex && c < book.chapters.length; c++) {
      total += book.chapters[c].paragraphs.length;
    }
    return total + state.paragraphIndex;
  }

  /// Moves to an absolute paragraph position in the book.
  ///
  /// The inverse of [_globalIndex]: walks the chapters accumulating lengths
  /// until the index falls inside one. It is what makes the progress bar a
  /// control instead of an indicator.
  Future<void> jumpToGlobalIndex(int target) async {
    final book = state.book;
    if (book == null) return;
    var remaining = target.clamp(0, _totalParagraphs(book) - 1);
    for (var c = 0; c < book.chapters.length; c++) {
      final length = book.chapters[c].paragraphs.length;
      if (remaining < length) {
        await navigateChapter(c, paragraph: remaining);
        return;
      }
      remaining -= length;
    }
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
    final settings = _settings;

    if (state.wordMarks.isNotEmpty) {
      // Word boundaries anchored to character offsets: the sentence follows
      // from where the current word sits, so a dropped token cannot shift
      // every later sentence.
      final wordIdx = activeWordIndex(state.wordMarks, elapsedMs);
      if (wordIdx >= 0) {
        final mark = state.wordMarks[wordIdx];
        final sentIdx = settings.highlightSentences
            ? sentenceAtOffset(state.sentenceRanges, mark.start)
            : state.highlightedSentence;
        final word = settings.highlightWords ? (mark.start, mark.end) : null;

        final wordChanged = word?.$1 != state.activeWord?.$1 ||
            word?.$2 != state.activeWord?.$2;
        if (sentIdx != state.highlightedSentence || wordChanged) {
          state = state.copyWith(
            highlightedSentence: sentIdx,
            activeWord: word,
            clearActiveWord: word == null,
          );
        }
      }
    } else if (state.sentenceMarks.isNotEmpty && settings.highlightSentences) {
      // No word boundaries (offline engine): fall back to estimated sentence
      // start times.
      final marks = state.sentenceMarks;
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

    // Shadowing loop: jump back as soon as the sentence finishes, so the same
    // line can be heard over and over without touching the controls.
    if (state.sentenceLoop) {
      final range = _activeSentenceMs();
      if (range != null && elapsedMs >= range.end) {
        unawaited(audioHandler.seek(Duration(milliseconds: range.start)));
        return;
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
      wordMarks: [],
      sentenceRanges: [],
      clearActiveWord: true,
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

  /// Fallback for engines that report no word boundaries (Piper): spread
  /// sentences across the clip proportionally to their length. Approximate, but
  /// enough to keep the highlight moving instead of frozen.
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

  /// Cache key component identifying *what produced* the audio.
  ///
  /// It has to name the engine, not just the voice: when the home server is
  /// unreachable the app falls back to Edge, and storing that under the
  /// server's key would later serve Edge audio while claiming to be Kokoro.
  ///
  /// Piper additionally folds in the pace, because `length_scale` is baked into
  /// the samples — changing it must invalidate what was downloaded.
  static String _cacheKeyFor(String engine, AppSettings settings, Book book) {
    // Kokoro y Piper llevan el idioma en la clave; Edge no lo necesita porque
    // el nombre de sus voces ya trae el locale (es-MX-DaliaNeural).
    //
    // Sin él, un libro en inglés y otro en español compartían audio cuando la
    // misma voz servía para ambos, que es justo el caso por defecto de Kokoro:
    // af_bella para los dos idiomas, y el idioma solo llega al servidor como
    // `lang_code`. Misma clave, audio distinto, y el que sonaba era el que se
    // hubiera descargado primero.
    final lang = cacheLangTag(book.language);
    final raw = switch (engine) {
      'piper' => 'piper-$lang-${settings.voiceForEngine('piper', book.language)}'
          '${piperPaceSuffix(settings.piperLengthScale)}',
      'kokoro' =>
        'kokoro-$lang-${settings.voiceForEngine('kokoro', book.language)}',
      // Sin idioma en la clave: este motor solo sirve español (ver
      // ChatterboxTtsProvider), así que no hay ambigüedad que resolver.
      'chatterbox' =>
        'chatterbox-${settings.voiceForEngine('chatterbox', book.language)}',
      // La voz del teléfono entra en la clave porque cambiarla cambia el audio,
      // y el idioma porque una voz puede servir a los dos.
      'android' =>
        'android-$lang-${settings.voiceForEngine('android', book.language)}',
      _ => 'edge-${settings.voiceForEngine('edge', book.language)}',
    };
    return sanitizeCacheKey(raw);
  }

  @visibleForTesting
  static String cacheKeyFor(String engine, AppSettings settings, Book book) =>
      _cacheKeyFor(engine, settings, book);

  /// Tail of a Piper cache key: the pace is baked into the samples, so audio
  /// downloaded at one `length_scale` cannot serve another.
  /// Etiqueta de idioma de la clave de caché: dos letras y nada más.
  ///
  /// Se queda en 'es' o 'en' porque son los dos idiomas que la app resuelve, y
  /// porque la migración de las filas antiguas tiene que poder reproducirla en
  /// SQL sin recorrer la tabla desde Dart.
  @visibleForTesting
  static String cacheLangTag(String bookLanguage) =>
      bookLanguage.toLowerCase().startsWith('es') ? 'es' : 'en';

  static String piperPaceSuffix(double lengthScale) =>
      sanitizeCacheKey('-${lengthScale.toStringAsFixed(2)}');

  /// The key is embedded in the cache filename, so it must survive as a path
  /// segment. An earlier version used ':' and '@' here, which made every file
  /// write fail while the progress bar still marched to 100 %.
  static String sanitizeCacheKey(String raw) =>
      raw.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  /// Key for the engine the user has selected.
  String _cacheKeyVoice(AppSettings settings, Book book) =>
      _cacheKeyFor(settings.ttsProvider, settings, book);

  /// Reuses one provider instance instead of building a new one per paragraph.
  ///
  /// Kokoro lives on a machine that is often off or out of reach, so it is
  /// probed first and quietly replaced by Edge when unavailable — the reader
  /// must never go silent just because the home server is down. The engine in
  /// use is surfaced in [ReaderState.engineLabel] so the swap is visible.
  /// Decides which engine to actually use right now -- the self-hosted health
  /// check and its fallback to Edge -- without touching any provider
  /// *instance*. Shared by interactive playback ([_provider]) and downloads
  /// ([downloadChapters]), which must each own their instance: see the note
  /// on [_ttsProvider] for why sharing one caused downloads and playback to
  /// dispose each other's connection mid-request.
  Future<String> _resolveEngineKind(AppSettings settings, String lang) async {
    var kind = settings.ttsProvider;

    // Chatterbox solo sirve español: sus dos voces son clones pensados para
    // eso, y el modelo no se probó (ni se confía) para inglés. Ni se hace el
    // health check -- directo a Edge, igual que un servidor no configurado.
    if (kind == 'chatterbox' && !lang.toLowerCase().startsWith('es')) {
      return 'edge';
    }

    if (settings.usesSelfHostedServer) {
      final url = settings.selfHostedUrl;
      _lastHealth = url.trim().isEmpty
          ? ServerHealth.unreachable
          : switch (kind) {
              'kokoro' => await KokoroTtsProvider.healthOf(url,
                  token: settings.serverToken),
              'piper' => await PiperTtsProvider.healthOf(url,
                  token: settings.serverToken),
              'chatterbox' => await ChatterboxTtsProvider.healthOf(url,
                  token: settings.serverToken),
              _ => ServerHealth.ok,
            };
      if (!_lastHealth.isUsable) {
        dev.log('[Reader] $kind ${_lastHealth.name} → falling back to Edge');
        kind = 'edge';
      }
    }
    return kind;
  }

  Future<TTSProvider> _provider(AppSettings settings, String lang) async {
    final kind = await _resolveEngineKind(settings, lang);
    final key = '$kind/$lang';
    if (_ttsProvider == null || _ttsProviderKind != key) {
      final old = _ttsProvider;
      _ttsProvider =
          getProvider(settings.copyWith(ttsProvider: kind), lang: lang);
      _ttsProviderKind = key;
      if (old != null) unawaited(old.dispose());
    }

    _activeEngineKind = kind;
    // The label used to be written only on the happy path of play(), so a whole
    // chapter could download through Edge with the bar still claiming Kokoro.
    // Every caller of _provider goes through here, so this is the one place
    // that always knows.
    if (state.book != null && _engineLabel(settings) != state.engineLabel) {
      state = state.copyWith(engineLabel: _engineLabel(settings));
    }
    return _ttsProvider!;
  }

  String _activeEngineKind = 'edge';

  /// Why the self-hosted engine was last set aside, if it was.
  ServerHealth _lastHealth = ServerHealth.ok;

  /// Label for the status bar: names the engine, and says so explicitly when it
  /// is not the one configured.
  ///
  /// A rejected key gets its own wording. For a tester it is the only signal
  /// that the problem is their build and not the developer's machine being off,
  /// and the two need different actions.
  String _engineLabel(AppSettings settings) {
    final label = providerLabel(_activeEngineKind);
    if (_activeEngineKind == settings.ttsProvider) return label;
    final reason = _lastHealth == ServerHealth.unauthorized
        ? 'clave rechazada'
        : '${providerLabel(settings.ttsProvider)} no disponible';
    return '$label ($reason)';
  }

  /// Returns the on-disk audio for [para], synthesizing and caching it on a miss.
  Future<_Audio> _ensureAudio(
      Book book, int chapterIdx, Paragraph para, AppSettings settings) async {
    Future<_Audio?> lookup(String key) async {
      final cached = await _cacheRepo.get(
          book.id!, chapterIdx, para.index, key, _cacheFormatTag);
      if (cached == null) return null;
      return (
        path: cached,
        timestamps: await _readSidecar(cached),
        freshKb: 0
      );
    }

    // Only the engine the reader chose. Consulting Edge's key here as well —
    // which an earlier version did, to reuse whatever a fallback had left
    // behind — made switching engines do nothing: any paragraph already heard
    // with Edge kept playing Edge's audio no matter what was selected.
    final chosen = await lookup(_cacheKeyVoice(settings, book));
    if (chosen != null) return chosen;

    await _cacheRepo.evictLruUntilFit(300, settings.cacheMaxMb);
    final provider = await _provider(settings, book.language);

    // Resolved after _provider, so a fallback is stored under the engine that
    // actually produced the audio.
    final voice = _cacheKeyFor(_activeEngineKind, settings, book);

    // The fallback to Edge did happen: now it is worth reusing what Edge left
    // cached rather than going back out to the network.
    if (_activeEngineKind != settings.ttsProvider) {
      final fallback = await lookup(voice);
      if (fallback != null) return fallback;
    }
    final result = await provider.synthesize(
      text: para.rawText,
      // The engine that is about to run, not the one selected. Asking Edge for
      // 'af_bella' or 'es_AR-daniela-high' — names from Kokoro's and Piper's
      // catalogues — made every fallback come back empty, which is exactly the
      // moment the fallback exists to cover.
      voice: settings.voiceForEngine(_activeEngineKind, book.language),
      rate: settings.edgeRate,
      volume: settings.edgeVolume,
    );

    // Keep the real extension: Piper emits WAV, Edge MP3, Kokoro AAC.
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

    final bytes = await File(dest).length();
    // Never register an unplayable file: it would be served from cache on every
    // later attempt, leaving that paragraph permanently silent.
    if (bytes < 512) {
      try {
        await File(dest).delete();
      } catch (_) {}
      throw Exception('El audio generado salió vacío ($bytes bytes)');
    }

    final sizeKb = (bytes / 1024).ceil();
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
    _listening = true;
    state = state.copyWith(
        status: ReaderStatus.synthesizing, statusMessage: 'Sintetizando…');
    _synthesizing = true;

    try {
      final audio = await _ensureAudio(book, state.chapterIndex, para, settings);

      final wordMarks = buildWordMarks(audio.timestamps, para.rawText);
      final sentenceRanges = buildSentenceRanges(para);
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
        engineLabel: _engineLabel(settings),
        sentenceMarks: marks,
        wordMarks: wordMarks,
        sentenceRanges: sentenceRanges,
        clearActiveWord: true,
        highlightedSentence: seekSentenceIdx > 0 ? seekSentenceIdx : -1,
        currentAudioPath: audio.path,
      );

      _publishNowPlaying(book, para);
      _loadedChapter = state.chapterIndex;
      _loadedParagraph = para.index;
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
      return 'Sin conexión. Descarga los capítulos por adelantado para '
          'escucharlos sin red.';
    }
    if (s.contains('Source error') || s.contains('PlatformException')) {
      return 'El audio de este párrafo está dañado. Se regenerará al reintentar.';
    }
    if (s.contains('no devolvió audio') || s.contains('salió vacío')) {
      return 'El motor no devolvió audio. Reintenta o cambia de motor.';
    }
    return 'Error: $s';
  }

  void _publishNowPlaying(Book book, Paragraph para) {
    final chapter = state.currentChapter;
    final percent = (state.progressFraction * 100).round();

    audioHandler.setNowPlaying(
      id: '${book.id}_${state.chapterIndex}_${para.index}',
      title: chapter?.title.isNotEmpty == true ? chapter!.title : book.title,
      // The lock screen offers no other context, so the subtitle carries the
      // position in the book rather than repeating the author alone.
      album: '${book.title} · $percent%',
      artist: book.author,
      artUri: _coverUri(),
    );
  }

  /// file:// URI of the cover, when there is one on disk.
  Uri? _coverUri() {
    final path = _coverPath;
    if (path == null || path.isEmpty) return null;
    try {
      if (!File(path).existsSync()) return null;
      return Uri.file(path);
    } catch (_) {
      return null;
    }
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
    // Safety net: if anything moved the position while paused, snap back to the
    // paragraph the loaded clip actually belongs to. Resuming into a mismatch
    // leaves the highlight on one paragraph while another is read aloud.
    if (_loadedParagraph >= 0 &&
        (state.paragraphIndex != _loadedParagraph ||
            state.chapterIndex != _loadedChapter)) {
      dev.log('[Reader] Resume re-synced to ch$_loadedChapter/$_loadedParagraph');
      state = state.copyWith(
        chapterIndex: _loadedChapter,
        paragraphIndex: _loadedParagraph,
      );
    }
    await audioHandler.play();
    state = state.copyWith(status: ReaderStatus.playing);
  }

  /// The Stop button: ends the listening session, so scrolling drives the
  /// position again for silent reading.
  Future<void> stop() => _stopPlayback(endSession: true);

  /// Used between paragraphs, where the session must survive.
  Future<void> _stopPlayback({required bool endSession}) async {
    if (endSession) _listening = false;
    await _saveProgress(offsetMs: audioHandler.elapsedMs);
    await audioHandler.stop();
    // The sentence highlight stays: it is the "you were here" marker. Only the
    // word underline goes, since nothing is being spoken any more.
    state = state.copyWith(
      status: ReaderStatus.idle,
      clearActiveWord: true,
    );
  }

  /// Millisecond span of the sentence being spoken, derived from the word marks
  /// that fall inside its character range.
  ({int start, int end})? _activeSentenceMs() {
    final sentenceIdx = state.highlightedSentence;
    if (sentenceIdx < 0 || state.wordMarks.isEmpty) return null;

    final range = state.sentenceRanges
        .where((r) => r.index == sentenceIdx)
        .firstOrNull;
    if (range == null) return null;

    final inside = state.wordMarks
        .where((m) => m.start >= range.start && m.start < range.end)
        .toList();
    if (inside.isEmpty) return null;

    return (start: inside.first.startMs, end: inside.last.endMs);
  }

  /// Restarts the current sentence. The core of practising pronunciation:
  /// listen, repeat aloud, compare.
  Future<void> repeatSentence() async {
    final range = _activeSentenceMs();
    if (range == null) return;
    await audioHandler.seek(Duration(milliseconds: range.start));
    if (state.status == ReaderStatus.paused) await resume();
  }

  void toggleSentenceLoop() =>
      state = state.copyWith(sentenceLoop: !state.sentenceLoop);

  /// Audio clip for the word at [charOffset] in the active paragraph.
  ///
  /// Returns null when that paragraph has no timings yet, or the offset falls
  /// outside every word — the caller then falls back to synthesizing the word.
  ({String path, int startMs, int endMs})? wordClipAt(int charOffset) {
    final path = state.currentAudioPath;
    if (path == null || state.wordMarks.isEmpty) return null;

    for (final mark in state.wordMarks) {
      if (charOffset >= mark.start && charOffset < mark.end) {
        // A little padding on each side: word boundaries land mid-transition,
        // and a bare cut swallows the first consonant.
        return (
          path: path,
          startMs: (mark.startMs - 60).clamp(0, 1 << 30),
          endMs: mark.endMs + 120,
        );
      }
    }
    return null;
  }

  /// Synthesizes a single word, for taps on paragraphs with no audio yet.
  Future<String?> synthesizeWord(String word) async {
    final book = state.book;
    if (book == null || word.trim().isEmpty) return null;
    try {
      final settings = _settings;
      final provider = await _provider(settings, book.language);
      final result = await provider.synthesize(
        text: word.trim(),
        // As in _ensureAudio: the engine that will run, not the one selected.
        // Asking Edge for Kokoro's voice returned nothing, and the catch below
        // swallowed it — long-pressing a word simply did nothing.
        voice: settings.voiceForEngine(_activeEngineKind, book.language),
        rate: settings.edgeRate,
        volume: settings.edgeVolume,
      );
      return result.filePath;
    } catch (e) {
      dev.log('[Reader] Word synthesis failed: $e');
      return null;
    }
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

  /// Salta directamente al capítulo siguiente, sin pasar por sus párrafos uno
  /// a uno. A diferencia de [nextParagraph], que solo cruza el límite al
  /// llegar al último párrafo, este es el control que corresponde a un botón
  /// dedicado -- el símil es el "siguiente pista" de un audiolibro, no un
  /// paso de más de `nextParagraph`.
  Future<void> nextChapter() async {
    final wasPlaying = state.isBusy;
    final total = state.book?.chapters.length ?? 1;
    if (state.chapterIndex >= total - 1) return;
    await navigateChapter(state.chapterIndex + 1, paragraph: 0);
    if (wasPlaying) await play();
  }

  /// Salta al **inicio** del capítulo anterior. A diferencia de
  /// [previousParagraph], que va al último párrafo del capítulo anterior
  /// cuando ya está en el primero de este, "capítulo anterior" siempre
  /// empieza desde el principio.
  Future<void> previousChapter() async {
    final wasPlaying = state.isBusy;
    if (state.chapterIndex <= 0) return;
    await navigateChapter(state.chapterIndex - 1, paragraph: 0);
    if (wasPlaying) await play();
  }

  Future<void> navigateChapter(int index, {int paragraph = 0}) async {
    _prefetchToken++;
    await _stopPlayback(endSession: false);
    state = state.copyWith(
      chapterIndex: index,
      paragraphIndex: paragraph,
      highlightedSentence: -1,
      // Marks belong to the paragraph that produced them; carrying them over
      // would highlight the wrong text once the new one starts.
      sentenceMarks: const [],
      wordMarks: const [],
      sentenceRanges: const [],
      clearActiveWord: true,
    );
    await _saveProgress();
  }

  Future<void> navigateParagraph(int index) async {
    _prefetchToken++;
    await _stopPlayback(endSession: false);
    state = state.copyWith(
      paragraphIndex: index,
      highlightedSentence: -1,
      sentenceMarks: const [],
      wordMarks: const [],
      sentenceRanges: const [],
      clearActiveWord: true,
    );
    await _saveProgress();
  }

  /// Called while the user scrolls in silent reading mode. Updates the shared
  /// position without touching playback, so picking up the audio later resumes
  /// exactly where the eyes stopped.
  Future<void> updateReadingPosition(int paragraphIndex) async {
    // Only genuine silent reading moves the position: while a listening session
    // is open the audio decides where the reader is, even between paragraphs.
    if (_listening || state.isOnAudio) return;
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
      globalIndex: _globalIndex(),
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

  /// Lleva la lectura a un marcador.
  ///
  /// **Sin arrancar el audio.** Antes llamaba a `play()` sin condición, así que
  /// consultar un pasaje marcado mientras se leía en silencio ponía el TTS a
  /// sonar de golpe. Si ya estaba sonando, sigue sonando desde el marcador, que
  /// es lo que se espera.
  Future<void> jumpToBookmark(
      int chapterIndex, int paragraphIndex, int sentenceIndex) async {
    final sonaba = state.isBusy;
    await navigateChapter(chapterIndex, paragraph: paragraphIndex);
    _pendingSentenceIdx = sentenceIndex;
    if (sonaba) await play();
  }

  /// Downloads just the chapter being read. Kept as the manual button.
  Future<void> downloadChapter() => downloadChapters(state.chapterIndex, 1);

  /// Synthesizes [count] chapters starting at [from] and pins them in
  /// getApplicationDocumentsDirectory(), where the OS will not clear them and
  /// the LRU eviction skips them.
  ///
  /// This is what makes Kokoro usable away from home: the audio is produced
  /// while the phone can still reach the server, then played back offline with
  /// its word timings intact.
  Future<void> downloadChapters(int from, int count,
      {bool silent = false}) async {
    final book = state.book;
    if (book == null || state.isDownloading) return;

    final chapters = book.chapters;
    final last = (from + count).clamp(0, chapters.length);
    if (from >= chapters.length || from < 0) return;

    final settings = _settings;
    // Its own instance, never `_provider`/`_ttsProvider`: those belong to
    // interactive playback, and switching *that* engine mid-download used to
    // dispose the instance this loop was still awaiting a response from --
    // see the note on `_ttsProvider`. A download keeps the engine it started
    // with even if the person changes engine in Ajustes while it runs; only
    // the server dropping out mid-download falls it back to Edge below.
    var dlKind = await _resolveEngineKind(settings, book.language);
    var dlProvider =
        getProvider(settings.copyWith(ttsProvider: dlKind), lang: book.language);
    // Resolve the engine up front: a download must be stored under whatever
    // actually synthesizes it, not under what was selected. This first reading
    // only decides what to skip; each paragraph re-derives its own key below.
    final skipKey = _cacheKeyFor(dlKind, settings, book);
    final docsDir = await getApplicationDocumentsDirectory();

    final totalParagraphs = [
      for (var c = from; c < last; c++) chapters[c].paragraphs.length
    ].fold<int>(0, (a, b) => a + b);

    _downloadCancelled = false;
    state = state.copyWith(
      isDownloading: true,
      downloadDone: 0,
      downloadTotal: totalParagraphs,
      downloadFailed: 0,
      downloadSecondsPerParagraph: estimatedSecondsPerParagraph(settings),
    );

    final startedAt = DateTime.now();
    var synthesized = 0;

    for (var chapterIdx = from; chapterIdx < last; chapterIdx++) {
      for (final para in chapters[chapterIdx].paragraphs) {
        if (_downloadCancelled) break;

        final alreadyPinned = await _cacheRepo.isPinnedParagraph(
            book.id!, chapterIdx, para.index, skipKey, _cacheFormatTag);
        if (alreadyPinned) {
          state = state.copyWith(downloadDone: state.downloadDone + 1);
          continue;
        }

        try {
          // Re-resolved per paragraph: the server can drop out mid-download,
          // and the key fixed before the loop would then file Edge's audio
          // under Kokoro's name — audio that plays with the wrong voice and
          // never gets regenerated because the row looks correct. Only the
          // *kind* is re-checked here; the settings snapshot stays the one
          // taken when the download started (see above).
          final nuevoKind = await _resolveEngineKind(settings, book.language);
          if (nuevoKind != dlKind) {
            unawaited(dlProvider.dispose());
            dlKind = nuevoKind;
            dlProvider = getProvider(settings.copyWith(ttsProvider: dlKind),
                lang: book.language);
          }
          final voice = _cacheKeyFor(dlKind, settings, book);
          final result = await dlProvider.synthesize(
            text: para.rawText,
            voice: settings.voiceForEngine(dlKind, book.language),
            rate: settings.edgeRate,
            volume: settings.edgeVolume,
          );

          final ext = result.filePath.split('.').last;
          final dest = '${docsDir.path}/dl_${book.id}_${chapterIdx}_'
              '${para.index}_${voice}_$_cacheFormatTag.$ext';
          await File(result.filePath).copy(dest);
          try {
            await File(result.filePath).delete();
          } catch (_) {}

          await _writeSidecar(dest, result.timestamps);
          final sizeKb = (await File(dest).length() / 1024).ceil();
          await _cacheRepo.savePin(book.id!, chapterIdx, para.index, voice,
              _cacheFormatTag, dest, sizeKb);
          synthesized++;
          // Refine the estimate from real timings instead of the static guess.
          final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
          state = state.copyWith(
              downloadSecondsPerParagraph: elapsed / 1000 / synthesized);
        } catch (e) {
          dev.log('[Reader] Download ch$chapterIdx para ${para.index}: $e');
          state = state.copyWith(downloadFailed: state.downloadFailed + 1);
          // A background prefetch that hits a dead server should give up
          // rather than grind through every remaining paragraph.
          if (silent) {
            _downloadCancelled = true;
          }
        }

        state = state.copyWith(downloadDone: state.downloadDone + 1);
      }
      if (_downloadCancelled) break;
    }

    unawaited(dlProvider.dispose());

    final failed = state.downloadFailed;
    state = state.copyWith(
      isDownloading: false,
      statusMessage: failed > 0
          ? 'Descarga incompleta: $failed párrafos fallaron'
          : state.statusMessage,
    );
    if (failed > 0) {
      dev.log('[Reader] Download finished with $failed failures');
    }
    await refreshDownloadedCount();
  }

  /// Rough synthesis cost per paragraph, measured on this project's servers.
  /// Only seeds the estimate; it is refined from real timings as the download
  /// progresses.
  static double estimatedSecondsPerParagraph(AppSettings settings) =>
      switch (settings.ttsProvider) {
        'piper' => 2.0,
        'kokoro' => 5.0,
        // Autoregresivo en GPU: ~55-75 s medidos para un párrafo de ~25 s de
        // audio, más lento que tiempo real -- no confundir con Kokoro/Piper.
        'chatterbox' => 65.0,
        'android' => 1.5, // en el propio teléfono, sin red de por medio
        _ => 3.0, // Edge, dominated by the network
      };

  /// Fills the cache ahead while on WiFi with the server in reach.
  ///
  /// Deliberately silent and cancellable: it must never interrupt reading, and
  /// it never runs on mobile data — synthesizing a chapter is megabytes.
  Future<void> maybePrefetchAhead() async {
    final settings = _settings;
    final book = state.book;
    if (book == null || !settings.prefetchOnWifi || state.isDownloading) return;

    // Only worth doing for a home server; Edge already streams on demand and
    // its audio is cached paragraph by paragraph as it plays. Chatterbox solo
    // vale la pena si el libro está en español -- mismo criterio que
    // _resolveEngineKind.
    final hasServer = switch (settings.ttsProvider) {
      'kokoro' => settings.hasKokoroServer,
      'piper' => settings.hasPiperServer,
      'chatterbox' => settings.hasChatterboxServer &&
          book.language.toLowerCase().startsWith('es'),
      _ => false,
    };
    if (!settings.usesSelfHostedServer || !hasServer) {
      return;
    }

    final connection = await Connectivity().checkConnectivity();
    if (isLikelyMetered(connection)) {
      dev.log('[Reader] Prefetch skipped: metered connection');
      return;
    }
    final reachable = switch (settings.ttsProvider) {
      'kokoro' => await KokoroTtsProvider.isReachable(settings.selfHostedUrl,
          token: settings.serverToken),
      'piper' => await PiperTtsProvider.isReachable(settings.selfHostedUrl,
          token: settings.serverToken),
      'chatterbox' => await ChatterboxTtsProvider.isReachable(
          settings.selfHostedUrl,
          token: settings.serverToken),
      _ => false,
    };
    if (!reachable) {
      dev.log('[Reader] Prefetch skipped: server unreachable');
      return;
    }

    await downloadChapters(
        state.chapterIndex, settings.prefetchChapters, silent: true);
  }

  /// Recomputes [ReaderState.downloadedChapters] for the selected engine.
  Future<void> refreshDownloadedCount() async {
    final count = await downloadedChapterCount();
    state = state.copyWith(downloadedChapters: count);
  }

  /// How many chapters of this book are fully pinned, for the download screen.
  Future<int> downloadedChapterCount() async {
    final book = state.book;
    if (book?.id == null) return 0;
    final voice = _cacheKeyVoice(_settings, book!);
    var complete = 0;
    for (var c = 0; c < book.chapters.length; c++) {
      final total = book.chapters[c].paragraphs.length;
      if (total == 0) continue;
      final pinned = await _cacheRepo.countPinned(
          book.id!, c, voice, _cacheFormatTag);
      if (pinned >= total) complete++;
    }
    return complete;
  }

  void cancelDownload() {
    _downloadCancelled = true;
    state = state.copyWith(isDownloading: false);
  }

  void cleanup() {
    // Leaving the book must not lose the last few seconds of progress.
    unawaited(_saveProgress(offsetMs: audioHandler.elapsedMs));
    unawaited(_connectivitySub?.cancel());
    _connectivitySub = null;
    _listening = false;
    _loadedChapter = -1;
    _loadedParagraph = -1;
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
