import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/settings.dart';
import '../../tts/models.dart';
import '../../tts/tts_factory.dart';

/// Lo único que decide qué catálogo de voces se pide.
///
/// Antes la familia iba indexada por el objeto `AppSettings` entero, y como
/// `AppSettings` no implementa `==`, la clave acababa siendo la identidad del
/// objeto: cada cambio de cualquier ajuste creaba una entrada nueva y una
/// petición nueva al servidor. Subir el tamaño de letra volvía a pedir las
/// trescientas voces de Edge.
///
/// Implementar `==` en `AppSettings` no habría bastado, porque seguiría
/// invalidando el catálogo al cambiar el tamaño de letra. Lo que importa son
/// estos tres campos y nada más.
class VoiceCatalogKey {
  final String engine;
  final String baseUrl;
  final String token;

  const VoiceCatalogKey({
    required this.engine,
    required this.baseUrl,
    required this.token,
  });

  factory VoiceCatalogKey.of(AppSettings s) => VoiceCatalogKey(
        engine: s.ttsProvider,
        baseUrl: s.selfHostedUrl,
        token: s.serverToken,
      );

  /// Reconstruye unos ajustes mínimos para poder construir el proveedor.
  AppSettings get settings => AppSettings(
        ttsProvider: engine,
        kokoroBaseUrl: engine == 'kokoro' ? baseUrl : '',
        piperBaseUrl: engine == 'piper' ? baseUrl : '',
      );

  @override
  bool operator ==(Object other) =>
      other is VoiceCatalogKey &&
      other.engine == engine &&
      other.baseUrl == baseUrl &&
      other.token == token;

  @override
  int get hashCode => Object.hash(engine, baseUrl, token);
}

/// Catálogo de voces del motor seleccionado.
///
/// Edge devuelve 300+ entradas y las cachea siete días en disco; Kokoro y Piper
/// devuelven lo que tenga cargado su servidor. Una lista vacía significa "tira
/// del `voiceMap` fijo".
///
/// `autoDispose` porque el catálogo solo hace falta con Ajustes abierto: sin
/// él, cada entrada se retenía para siempre.
final voicesProvider =
    FutureProvider.autoDispose.family<List<Voice>, VoiceCatalogKey>(
        (ref, key) async {
  final tts = getProvider(key.settings);
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
