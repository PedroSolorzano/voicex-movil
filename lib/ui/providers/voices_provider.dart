import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../tts/models.dart';
import '../../tts/tts_factory.dart';
import '../../config/settings.dart';

/// Live voice catalogue for a given engine. Edge returns 300+ entries (cached
/// locally for 7 days); Android returns whatever the device engine reports.
/// An empty list means "fall back to the hardcoded voiceMap".
final voicesProvider =
    FutureProvider.family<List<Voice>, String>((ref, providerKind) async {
  final tts = getProvider(AppSettings(ttsProvider: providerKind));
  try {
    final voices = await tts.listVoices();
    voices.sort((a, b) {
      final byLocale = a.locale.compareTo(b.locale);
      return byLocale != 0 ? byLocale : a.name.compareTo(b.name);
    });
    return voices;
  } finally {
    await tts.dispose();
  }
});

/// Voices narrowed to one language prefix ("es", "en", …).
List<Voice> voicesForLanguage(List<Voice> all, String lang) =>
    all.where((v) => v.locale.toLowerCase().startsWith(lang)).toList();
