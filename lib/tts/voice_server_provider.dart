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

/// Talks to the self-hosted voice server (`tools/mlx`): a Mac with Apple
/// Silicon running Qwen3-TTS and Chatterbox over MLX.
///
/// One server, two engines. [engine] picks which of them answers (`qwen3` or
/// `chatterbox2`); the address, the token and the health endpoint are shared,
/// so this is one class and not two.
///
/// Both clone the voice of a recording kept on the server, so [voice] is the
/// bare name of one of its `voices/*.wav`. The app does not choose among
/// models for a voice: it asks the server which voices it has.
///
/// Spanish only: the voices are clones of Spanish speakers, so
/// `reader_provider.dart` does not select these engines for a book in another
/// language.
///
/// The whole paragraph goes in one request. The server owns the chunking of
/// long paragraphs and the MP3 encoding, because the right chunk size depends
/// on the model and not on the client.
///
/// No word timings: both models are autoregressive over audio tokens and give
/// no alignment, the same accepted trade-off as the engines before them.
class VoiceServerTtsProvider implements TTSProvider {
  final String baseUrl;

  /// Which model answers: `qwen3` or `chatterbox2`, the ids `tools/mlx` serves.
  final String engine;

  /// The server's credential. Empty is valid — a server started without a
  /// token asks for nothing — so the header is simply omitted then.
  final String token;

  /// Overridable so a test can force a timeout without waiting the full budget.
  Duration synthesisTimeout;

  final HttpClient _client = HttpClient();

  VoiceServerTtsProvider(String baseUrl,
      {required this.engine,
      this.token = '',
      this.synthesisTimeout = TtsTimeouts.synthesisServer})
      : baseUrl = normalizeBaseUrl(baseUrl) {
    _client.connectionTimeout = TtsTimeouts.connect;
    _client.idleTimeout = TtsTimeouts.idle;
  }

  /// `/health` never touches the GPU, so it keeps answering in milliseconds
  /// even mid-synthesis. That is the reason the server runs its model on its
  /// own thread: an earlier engine shared one thread between synthesis and its
  /// health endpoint, so a long paragraph made it look dead
  /// (`docs/bugs/CHATTERBOX_DESCARGAS.md`).
  ///
  /// Factored out so [synthesize] marks the exact same key [markServerBusy]
  /// expects — a mismatched URI would silently defeat the busy short-circuit.
  static Uri _healthUri(String baseUrl) => buildUri(baseUrl, '/health');

  static Future<ServerHealth> healthOf(String baseUrl,
          {String token = '', String engine = 'qwen3'}) =>
      probeServer(_healthUri(baseUrl), token: token, engine: engine);

  static Future<bool> isReachable(String baseUrl,
          {String token = '', String engine = 'qwen3'}) async =>
      (await healthOf(baseUrl, token: token, engine: engine)).isUsable;

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
    applyRequestHeaders(req, token: token, engine: engine, chars: text.length);
    // `rate` no viaja: la velocidad se aplica al reproducir (just_audio), así
    // que un mismo archivo sirve a todas, y la clave de caché no la lleva.
    req.write(jsonEncode({'text': text, 'voice': voice, 'engine': engine}));

    // El presupuesto sale del largo del texto, no de un número fijo:
    // `synthesisTimeout` solo pone el piso, que una descarga puede subir con
    // lo que viene midiendo en esta máquina.
    final budget =
        TtsTimeouts.synthesisForChars(text.length, floor: synthesisTimeout);
    final HttpClientResponse resp;
    try {
      resp = await req.close().timeout(budget);
    } on TimeoutException {
      // Scoped to the timeout specifically: a 4xx/5xx below means the server
      // answered fine and is free — marking it busy there would be wrong.
      markServerBusy(_healthUri(baseUrl), cooldown: TtsTimeouts.busyCooldown);
      rethrow;
    }
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      throw HttpException('El servidor de voz respondió ${resp.statusCode}',
          uri: uri);
    }

    final audio = await readBodyBytes(resp);
    if (audio.isEmpty) {
      throw const HttpException('El servidor de voz no devolvió audio');
    }

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/${engine}_${_uuid.v4()}.mp3';
    await File(filePath).writeAsBytes(audio);
    dev.log('[$engine] ${audio.length}B → $filePath');

    return TTSResult(filePath: filePath, timestamps: const []);
  }

  /// Catálogo servido por el propio servidor: son las voces clonadas que
  /// tenga en `voices/`, no un catálogo fijo del modelo.
  @override
  Future<List<Voice>> listVoices() async {
    try {
      final req = await _client.getUrl(_healthUri(baseUrl));
      applyRequestHeaders(req, token: token, engine: engine);
      final resp = await req.close().timeout(TtsTimeouts.catalogue);
      final cuerpo = jsonDecode(await readBodyString(resp)) as Map;
      return [
        for (final v in (cuerpo['voices'] as List? ?? []))
          Voice(
            id: v as String,
            name: v,
            locale: 'es',
            gender: 'female',
          ),
      ];
    } catch (e) {
      dev.log('[$engine] no se pudo leer el catálogo de voces: $e');
      return const [];
    }
  }

  @override
  Future<void> dispose() async {
    _client.close(force: true);
  }
}
