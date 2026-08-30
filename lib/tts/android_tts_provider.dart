import 'dart:async';
import 'dart:io';
import 'dart:developer' as dev;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'tts_provider.dart';

const _uuid = Uuid();

/// Offline fallback built on the device's own TTS engine.
///
/// Synthesis is always done at neutral rate/volume: playback speed is applied
/// downstream by the audio player, so one cached file serves every speed.
class AndroidTtsProvider implements TTSProvider {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    // Makes synthesizeToFile() resolve when synthesis actually finishes instead
    // of returning immediately — otherwise a half-written file reaches the player.
    await _tts.awaitSynthCompletion(true);
    _initialized = true;
  }

  @override
  Future<TTSResult> synthesize({
    required String text,
    required String voice,
    required String rate,
    required String volume,
  }) async {
    await _init();

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/android_${_uuid.v4()}.wav';

    await _tts.setLanguage(voice);
    await _tts.setSpeechRate(1.0);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    await _tts.synthesizeToFile(text, filePath);

    final file = File(filePath);
    if (!await file.exists() || await file.length() == 0) {
      throw Exception(
          'El motor TTS de Android no generó audio. Revisa que haya un motor '
          'de voz instalado y con el idioma $voice descargado.');
    }

    dev.log('[AndroidTTS] ${await file.length()}B → $filePath');
    // The platform engine exposes no word boundaries, so sentence highlighting
    // is unavailable offline. ReaderNotifier falls back to a duration estimate.
    return TTSResult(filePath: filePath, timestamps: []);
  }

  @override
  Future<List<Voice>> listVoices() async {
    await _init();
    final voices = await _tts.getVoices as List?;
    if (voices == null) return [];
    return voices
        .whereType<Map>()
        .map((v) => Voice(
              id: v['name']?.toString() ?? '',
              name: v['name']?.toString() ?? '',
              locale: v['locale']?.toString() ?? '',
              gender: 'unknown',
            ))
        .where((v) => v.id.isNotEmpty)
        .toList();
  }

  @override
  Future<void> dispose() async {
    await _tts.stop();
  }
}
