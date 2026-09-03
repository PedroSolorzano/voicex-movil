import '../config/settings.dart';
import 'tts_provider.dart';
import 'android_tts_provider.dart';
import 'edge_tts_provider.dart';
import 'kokoro_tts_provider.dart';
import 'piper_tts_provider.dart';

/// Builds the engine for [settings], for a book in [lang] ('es' / 'en').
///
/// The language matters for Kokoro: without an explicit code it infers one from
/// the voice prefix and reads Spanish with English pronunciation.
TTSProvider getProvider(AppSettings settings, {String lang = 'es'}) {
  switch (settings.ttsProvider) {
    case 'android':
      return AndroidTtsProvider(
          langCode: lang == 'es' ? 'es-ES' : 'en-US');
    case 'kokoro':
      return KokoroTtsProvider(settings.kokoroBaseUrl,
          langCode: kokoroLangCode(lang), token: settings.serverToken);
    case 'piper':
      return PiperTtsProvider(settings.piperBaseUrl,
          lengthScale: settings.piperLengthScale, token: settings.serverToken);
    case 'edge':
    default:
      return EdgeTtsProvider();
  }
}

/// Human label for the engine actually in use, shown in the reader status bar
/// so a silent fallback is never invisible.
String providerLabel(String kind) => switch (kind) {
      'kokoro' => 'Kokoro',
      'piper' => 'Piper',
      'android' => 'Teléfono',
      _ => 'Edge',
    };
