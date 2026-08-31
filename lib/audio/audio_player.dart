import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as ja;

enum AudioState { idle, playing, paused }

/// Global handler, created once by [initAudioHandler] during app startup.
late VoiceXAudioHandler _audioHandler;

VoiceXAudioHandler get audioHandler => _audioHandler;
set audioHandler(VoiceXAudioHandler h) {
  _audioHandler = h;
  _handlerInitialised = true;
}

/// Starts the media service. If that fails — an unsupported platform, a denied
/// notification channel — the app degrades to a plain player rather than
/// crashing: [audioHandler] is always assigned, so callers never hit a
/// LateInitializationError. Playback still works; only the notification and
/// lock-screen controls are missing.
Future<void> initAudioHandler() async {
  try {
    audioHandler = await AudioService.init(
      builder: () => VoiceXAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.pedrosolorzano.voicex_movil.playback',
        androidNotificationChannelName: 'Reproducción',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: true,
      ),
    );
  } catch (e) {
    audioHandler = VoiceXAudioHandler();
    rethrow;
  }
}

/// True once [initAudioHandler] has produced a handler of any kind.
bool get isAudioHandlerReady => _handlerInitialised;
bool _handlerInitialised = false;

/// Wraps just_audio in an audio_service handler so playback survives in a
/// foreground service and is controllable from the lock screen, the
/// notification shade, headset buttons and Bluetooth car controls.
///
/// Paragraph audio is synthesized one file at a time, so there is no playlist:
/// skipToNext/skipToPrevious delegate to [onNext]/[onPrevious], which
/// ReaderNotifier wires to its paragraph navigation.
class VoiceXAudioHandler extends BaseAudioHandler with SeekHandler {
  final ja.AudioPlayer _player = ja.AudioPlayer();
  Timer? _ticker;
  StreamSubscription<ja.PlayerState>? _stateSub;

  AudioState state = AudioState.idle;

  /// Fired every 50 ms while playing — drives sentence highlighting.
  void Function(int elapsedMs)? onTick;

  /// Fired when the current paragraph's audio reaches its end.
  void Function()? onEnd;

  /// Lock-screen / headset navigation, wired by ReaderNotifier.
  Future<void> Function()? onNext;
  Future<void> Function()? onPrevious;

  bool _completionHandled = false;

  VoiceXAudioHandler() {
    _configureSession();
    _stateSub = _player.playerStateStream.listen(_onPlayerState);
  }

  Future<void> _configureSession() async {
    final session = await AudioSession.instance;
    // Speech profile: ducks other audio politely and requests transient loss
    // handling so an incoming call pauses us instead of talking over us.
    await session.configure(const AudioSessionConfiguration.speech());
  }

  void _onPlayerState(ja.PlayerState s) {
    if (s.processingState == ja.ProcessingState.completed) {
      // playerStateStream can emit `completed` more than once for one file.
      if (_completionHandled) return;
      _completionHandled = true;
      _stopTicker();
      state = AudioState.idle;
      _broadcast();
      onEnd?.call();
      return;
    }
    _broadcast();
  }

  void _broadcast() {
    final playing = state == AudioState.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 3],
      processingState: switch (_player.processingState) {
        ja.ProcessingState.idle => AudioProcessingState.idle,
        ja.ProcessingState.loading => AudioProcessingState.loading,
        ja.ProcessingState.buffering => AudioProcessingState.buffering,
        ja.ProcessingState.ready => AudioProcessingState.ready,
        ja.ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: _player.position,
      speed: _player.speed,
    ));
  }

  /// Publishes what is showing on the lock screen.
  void setNowPlaying({
    required String id,
    required String title,
    String? album,
    String? artist,
    Uri? artUri,
  }) {
    mediaItem.add(MediaItem(
      id: id,
      title: title,
      album: album,
      artist: artist,
      artUri: artUri,
      duration: _player.duration,
    ));
  }

  /// Loads a freshly synthesized paragraph and starts playing it.
  Future<void> playFile(String filePath, {int startMs = 0, double speed = 1.0}) async {
    _completionHandled = false;
    await _player.setFilePath(filePath);
    await _player.setSpeed(speed);
    if (startMs > 0) {
      await _player.seek(Duration(milliseconds: startMs));
    }

    // State and ticker are set BEFORE play() because just_audio 0.9.x returns a
    // Future that only completes when playback ends — awaiting it would block.
    state = AudioState.playing;
    _startTicker();
    _broadcast();

    // Refresh the duration now that the file is decoded: without it the system
    // draws no progress bar on the lock screen.
    final item = mediaItem.value;
    if (item != null && _player.duration != null) {
      mediaItem.add(item.copyWith(duration: _player.duration));
    }
    _broadcast();

    unawaited(_player.play());
  }

  @override
  Future<void> play() async {
    if (state != AudioState.paused) return;
    state = AudioState.playing;
    _startTicker();
    _broadcast();
    unawaited(_player.play());
  }

  @override
  Future<void> pause() async {
    if (state != AudioState.playing) return;
    await _player.pause();
    _stopTicker();
    state = AudioState.paused;
    _broadcast();
  }

  @override
  Future<void> stop() async {
    await _player.stop();
    _stopTicker();
    state = AudioState.idle;
    _broadcast();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    _broadcast();
  }

  @override
  Future<void> skipToNext() async => onNext?.call();

  @override
  Future<void> skipToPrevious() async => onPrevious?.call();

  @override
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed);
    _broadcast();
  }

  int get elapsedMs => _player.position.inMilliseconds;

  /// Length of the loaded clip, once just_audio has decoded its header.
  Duration? get duration => _player.duration;

  void _startTicker() {
    _ticker?.cancel();
    var sinceBroadcast = 0;
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      onTick?.call(elapsedMs);
      // Republish the position about once a second so the lock-screen progress
      // bar advances; every tick would be needless churn.
      if (++sinceBroadcast >= 20) {
        sinceBroadcast = 0;
        _broadcast();
      }
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Detaches the per-book callbacks without tearing down the service — the
  /// handler outlives any single reader screen.
  void detach() {
    onTick = null;
    onEnd = null;
    onNext = null;
    onPrevious = null;
  }

  Future<void> dispose() async {
    await _stateSub?.cancel();
    _stopTicker();
    await _player.dispose();
  }
}
