import 'models.dart';

abstract class TTSProvider {
  Future<TTSResult> synthesize({
    required String text,
    required String voice,
    required String rate,
    required String volume,
  });

  Future<List<Voice>> listVoices();

  Future<void> dispose();
}
