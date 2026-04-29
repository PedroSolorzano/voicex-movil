import 'dart:async';
import 'package:just_audio/just_audio.dart' as ja;

enum AudioState { idle, playing, paused }

class VoiceXAudioPlayer {
  final ja.AudioPlayer _player = ja.AudioPlayer();
  Timer? _ticker;

  AudioState state = AudioState.idle;
  void Function(int elapsedMs)? onTick;
  void Function()? onEnd;

  int _startMs = 0;
  int _pausedMs = 0;

  Future<void> play(String filePath) async {
    await _player.setFilePath(filePath);
    await _player.play();
    state = AudioState.playing;
    _startMs = DateTime.now().millisecondsSinceEpoch;
    _startTicker();

    _player.playerStateStream.listen((s) {
      if (s.processingState == ja.ProcessingState.completed) {
        _stopTicker();
        state = AudioState.idle;
        onEnd?.call();
      }
    });
  }

  Future<void> pause() async {
    if (state != AudioState.playing) return;
    await _player.pause();
    _pausedMs = DateTime.now().millisecondsSinceEpoch - _startMs;
    _stopTicker();
    state = AudioState.paused;
  }

  Future<void> resume() async {
    if (state != AudioState.paused) return;
    await _player.play();
    _startMs = DateTime.now().millisecondsSinceEpoch - _pausedMs;
    _startTicker();
    state = AudioState.playing;
  }

  Future<void> stop() async {
    await _player.stop();
    _stopTicker();
    state = AudioState.idle;
    _pausedMs = 0;
  }

  int get elapsedMs {
    if (state == AudioState.paused) return _pausedMs;
    if (state == AudioState.playing) {
      return DateTime.now().millisecondsSinceEpoch - _startMs;
    }
    return 0;
  }

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
    _stopTicker();
    await _player.dispose();
  }
}
