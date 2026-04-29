import 'dart:async';
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'tts_provider.dart';

const _uuid = Uuid();

class AndroidTtsProvider implements TTSProvider {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    await _tts.setSharedInstance(true);
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

    final completer = Completer<void>();
    await _tts.synthesizeToFile(text, filePath);

    // synthesizeToFile is synchronous in flutter_tts — wait for file
    int retries = 0;
    while (!File(filePath).existsSync() && retries < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      retries++;
    }

    if (!completer.isCompleted) completer.complete();

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
        .toList();
  }

  @override
  Future<void> dispose() async {
    await _tts.stop();
  }
}
