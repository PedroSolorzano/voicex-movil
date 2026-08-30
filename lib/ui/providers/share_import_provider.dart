import 'dart:developer' as dev;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'library_provider.dart';

/// Bridges the native side of "Abrir con VoiceX" / share-to-app.
///
/// MainActivity copies the incoming content:// URI into the cache directory and
/// hands over a plain path; LibraryNotifier.addBook then moves it into
/// permanent app storage, so the temporary copy going away is harmless.
const _channel = MethodChannel('voicex/shared_epub');

class ShareImportNotifier extends Notifier<String?> {
  bool _started = false;

  @override
  String? build() => null;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Intents arriving while the app is already running.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onFile' && call.arguments is String) {
        await _import(call.arguments as String);
      }
    });

    // The intent that launched the app, if any.
    try {
      final path = await _channel.invokeMethod<String>('getInitialFile');
      if (path != null) await _import(path);
    } on PlatformException catch (e) {
      dev.log('[Share] initial file failed: $e');
    } on MissingPluginException {
      // Non-Android platform or engine without the channel: nothing to do.
    }
  }

  Future<void> _import(String path) async {
    if (!path.toLowerCase().endsWith('.epub')) return;
    try {
      await ref.read(libraryProvider.notifier).addBook(path);
      state = 'Libro agregado a la biblioteca';
    } catch (e) {
      dev.log('[Share] import failed: $e');
      state = 'No se pudo agregar el libro: $e';
    }
  }

  void clearMessage() => state = null;
}

final shareImportProvider =
    NotifierProvider<ShareImportNotifier, String?>(ShareImportNotifier.new);
