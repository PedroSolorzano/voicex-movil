import '../config/settings.dart';
import 'tts_provider.dart';
import 'edge_tts_provider.dart';
import 'android_tts_provider.dart';

TTSProvider getProvider(AppSettings settings) {
  switch (settings.ttsProvider) {
    case 'android':
      return AndroidTtsProvider();
    case 'edge':
    default:
      return EdgeTtsProvider();
  }
}
