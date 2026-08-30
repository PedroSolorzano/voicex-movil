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
      debugPrint('Audio service init failed: $e\n$st');
    }

    unawaited(_pruneCache());
    runApp(const ProviderScope(child: VoiceXApp()));
  }, (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
  });
}

Future<void> _pruneCache() async {
  try {
    await AudioCacheRepo().pruneExpired();
  } catch (_) {}
}
