import 'dart:async';
import 'package:just_audio/just_audio.dart' as ja;

enum AudioState { idle, playing, paused }

class VoiceXAudioPlayer {
  final ja.AudioPlayer _player = ja.AudioPlayer();
  Timer? _ticker;
  StreamSubscription? _stateSub;

  AudioState state = AudioState.idle;
  void Function(int elapsedMs)? onTick;
  void Function()? onEnd;

  Future<void> play(String filePath, {int startMs = 0}) async {
    // Cancel previous completion listener before starting a new track.
    await _stateSub?.cancel();
    await _player.setFilePath(filePath);

    if (startMs > 0) {
      await _player.seek(Duration(milliseconds: startMs));
    }

    // Set state and start the ticker BEFORE calling play() because
    // just_audio 0.9.x play() returns a Future that completes when
    // playback ends — awaiting it would block the entire method.
    state = AudioState.playing;
    _startTicker();
    _stateSub = _player.playerStateStream.listen((s) {
      if (s.processingState == ja.ProcessingState.completed) {
        _stopTicker();
        state = AudioState.idle;
        onEnd?.call();
      }
    });

    unawaited(_player.play());
  }

  Future<void> pause() async {
    if (state != AudioState.playing) return;
    await _player.pause();
    _stopTicker();
    state = AudioState.paused;
  }

  Future<void> resume() async {
    if (state != AudioState.paused) return;
    state = AudioState.playing;
    _startTicker();
    unawaited(_player.play());
  }

  Future<void> stop() async {
    await _player.stop();
    _stopTicker();
    state = AudioState.idle;
  }

  // Use just_audio's position for accurate elapsed time instead of wall clock.
  int get elapsedMs =>
      _player.position.inMilliseconds;

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      onTick?.call(elapsedMs);
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  Future<void> dispose() async {
    await _stateSub?.cancel();
    _stopTicker();
    await _player.dispose();
  }
}
