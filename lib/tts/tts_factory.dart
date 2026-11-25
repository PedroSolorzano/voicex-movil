import '../config/settings.dart';
import 'tts_provider.dart';
import 'android_tts_provider.dart';
import 'edge_tts_provider.dart';
import 'voice_server_provider.dart';

/// Builds the engine for [settings], for a book in [lang] ('es' / 'en').
///
/// [lang] only matters for the phone's own engine. The two server engines read
/// Spanish only, and `reader_provider.dart` keeps a book in another language
/// from ever getting here with them.
TTSProvider getProvider(AppSettings settings, {String lang = 'es'}) {
  switch (settings.ttsProvider) {
    case 'android':
      return AndroidTtsProvider(
          langCode: lang == 'es' ? 'es-ES' : 'en-US');
    case 'qwen3':
    case 'chatterbox2':
      return VoiceServerTtsProvider(settings.serverBaseUrl,
          engine: settings.ttsProvider, token: settings.serverToken);
    case 'edge':
    default:
      return EdgeTtsProvider();
  }
}

/// Human label for the engine actually in use, shown in the reader status bar
/// so a silent fallback is never invisible.
String providerLabel(String kind) => switch (kind) {
      'qwen3' => 'Qwen3',
      'chatterbox2' => 'Chatterbox',
      'android' => 'Teléfono',
      _ => 'Edge',
    };
