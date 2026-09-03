import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'audio/audio_player.dart';
import 'storage/repositories.dart';
import 'tts/tts_endpoint.dart';
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

    unawaited(_stampVersion());
    unawaited(_pruneCache());
    runApp(const ProviderScope(child: VoiceXApp()));
  }, (error, stack) {
    debugPrint('Unhandled error: $error\n$stack');
  });
}

/// Stamps every request to the self-hosted engines with the build that made
/// it, so a report can be tied to the APK a given tester is running. Off the
/// critical path: an empty tag simply omits the header.
Future<void> _stampVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    appVersionTag = '${info.version}+${info.buildNumber}';
  } catch (e) {
    debugPrint('Version tag unavailable: $e');
  }
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
