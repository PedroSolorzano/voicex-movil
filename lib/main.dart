import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'audio/audio_player.dart';
import 'storage/repositories.dart';
import 'ui/app.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Must complete before the first playback request: it starts the media
    // service that owns the notification and lock-screen controls.
    try {
      await initAudioHandler();
    } catch (e, st) {
      // initAudioHandler still leaves a usable player behind; only the media
      // notification and lock-screen controls are lost.
      debugPrint('Audio service init failed, degraded playback: $e\n$st');
    }

    unawaited(_pruneCache());
    runApp(const ProviderScope(child: VoiceXApp()));
  }, (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
  });
}

Future<void> _pruneCache() async {
  try {
    final repo = AudioCacheRepo();
    // Before pruning: keys written by earlier builds must be renamed, or every
    // download made with them would look missing and be synthesized again.
    await repo.migrateCacheKeys();
    await repo.pruneExpired();
  } catch (e, st) {
    debugPrint('Cache maintenance failed: $e\n$st');
  }
}
