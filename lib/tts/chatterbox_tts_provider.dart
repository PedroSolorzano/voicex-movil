import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'server_health.dart';
import 'tts_endpoint.dart';
import 'tts_provider.dart';

const _uuid = Uuid();

/// Talks to a self-hosted Chatterbox-TTS-Server (devnen/Chatterbox-TTS-Server)
/// instance, reached directly over Tailscale — this engine runs on a personal
/// laptop with a GPU, not on `voicex-server`, and has no proxy in front.
///
/// Only Spanish is supported: the two voices configured are clones (see
/// `docs/context/TTS_ESPANOL.md`) picked for reading Spanish books, and the
/// multilingual model's language conditioning is unreliable enough with an
/// English-recorded predefined voice that this provider does not attempt to
/// offer English at all — `reader_provider.dart` simply does not select
/// Chatterbox for a book in another language.
///
/// The whole paragraph is sent in a single request: unlike Kokoro/Piper, the
/// server itself chunks long text by sentence (`split_text`, ~120 chars) and
/// stitches the pieces with crossfades, so there is nothing for the client to
/// do — it just needs a long enough timeout (`TtsTimeouts.synthesisChatterbox`).
///
/// No word timings: `voice_mode: clone` gives no phoneme alignment, same
/// accepted trade-off as Piper.
class ChatterboxTtsProvider implements TTSProvider {
  final String baseUrl;

  /// Empty: this server is reached directly, no proxy token involved.
  final String token;

  /// Presupuesto para una síntesis. Mutable porque una descarga lo reajusta
  /// párrafo a párrafo con lo que esta máquina viene tardando de verdad
  /// (`TtsTimeouts.adaptiveSynthesis`); la reproducción interactiva lo deja en
  /// su valor por defecto, porque ahí esperar minutos no sirve de nada.
  Duration synthesisTimeout;

  final HttpClient _client = HttpClient();

  ChatterboxTtsProvider(String baseUrl,
      {this.token = '', this.synthesisTimeout = TtsTimeouts.synthesisChatterbox})
      : baseUrl = normalizeBaseUrl(baseUrl) {
    _client.connectionTimeout = TtsTimeouts.connect;
    _client.idleTimeout = TtsTimeouts.idle;
  }

  /// `/api/model-info` is the cheap endpoint: reports the loaded model
  /// without triggering synthesis, unlike `/api/ui/initial-data`.
  ///
  /// Factored out so [synthesize] marks the exact same key
  /// [markServerBusy] expects — a mismatched URI would silently defeat the
  /// busy short-circuit.
  static Uri _healthUri(String baseUrl) => buildUri(baseUrl, '/api/model-info');

  static Future<ServerHealth> healthOf(String baseUrl, {String token = ''}) =>
      probeServer(_healthUri(baseUrl), token: token, engine: 'chatterbox');

  static Future<bool> isReachable(String baseUrl, {String token = ''}) async =>
      (await healthOf(baseUrl, token: token)).isUsable;

  static void resetHealthCache() => resetServerHealthCache();

  @override
  Future<TTSResult> synthesize({
    required String text,
    required String voice,
    required String rate,
    required String volume,
  }) async {
    final uri = buildUri(baseUrl, '/tts');
    final req = await _client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    applyRequestHeaders(req,
        token: token, engine: 'chatterbox', chars: text.length);
    req.write(jsonEncode({
      'text': text,
      'language': 'es',
      'output_format': 'mp3',
      'voice_mode': 'clone',
      'reference_audio_filename': voice,
      'seed': 0,
    }));

    final HttpClientResponse resp;
    try {
      resp = await req.close().timeout(synthesisTimeout);
    } on TimeoutException {
      // Scoped to the timeout specifically: a 4xx/5xx below means the server
      // answered fine and is free — marking it busy there would be wrong.
      markServerBusy(_healthUri(baseUrl), cooldown: TtsTimeouts.busyCooldown);
      rethrow;
    }
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      throw HttpException('Chatterbox respondió ${resp.statusCode}', uri: uri);
    }

    final audio = await readBodyBytes(resp);
    if (audio.isEmpty) {
      throw const HttpException('Chatterbox no devolvió audio');
    }

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/chatterbox_${_uuid.v4()}.mp3';
    await File(filePath).writeAsBytes(audio);

    dev.log('[Chatterbox] ${audio.length}B → $filePath');
    // Sin marcas por palabra: mismo costo aceptado que Piper.
    return TTSResult(filePath: filePath, timestamps: const []);
  }

  /// Catálogo fijo, no `/get_reference_files`: ese endpoint también lista
  /// `Gianna.wav`/`Robert.wav`, las voces de ejemplo del repo, ajenas a esta
  /// elección.
  @override
  Future<List<Voice>> listVoices() async => [
        Voice(
          id: 'piper-mx-clon.wav',
          name: 'Piper MX (clon)',
          locale: 'es',
          gender: 'female',
        ),
        Voice(
          id: 'voz-propia.mp3',
          name: 'Voz propia',
          locale: 'es',
          gender: 'female',
        ),
      ];

  @override
  Future<void> dispose() async {
    _client.close(force: true);
  }
}
