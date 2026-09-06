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

/// Talks to the self-hosted F5-TTS server (`tools/f5`), reached directly over
/// Tailscale — it needs a GPU, so it runs on a personal laptop rather than on
/// `voicex-server`, and has no proxy in front.
///
/// Replaces Chatterbox, which sounded as good but was unusable for an
/// audiobook: 0.089x real time against F5's better-than-real-time on the same
/// card. F5 is not autoregressive, which is where the difference comes from.
///
/// Spanish only, same as Chatterbox: the checkpoint is a Spanish finetune
/// (`jpgallegoar/F5-Spanish`), so `reader_provider.dart` does not select this
/// engine for a book in another language.
///
/// The whole paragraph goes in one request. The server owns the chunking, the
/// pronunciation fixes and the MP3 encoding — see `tools/f5/README.md` for why
/// each of those lives there rather than here.
///
/// No word timings: flow-matching gives no phoneme alignment, the same
/// accepted trade-off as Piper and Chatterbox.
class F5TtsProvider implements TTSProvider {
  final String baseUrl;

  /// Empty: this server is reached directly, no proxy token involved.
  final String token;

  /// Overridable so a test can force a timeout without waiting the full budget.
  Duration synthesisTimeout;

  final HttpClient _client = HttpClient();

  F5TtsProvider(String baseUrl,
      {this.token = '', this.synthesisTimeout = TtsTimeouts.synthesisF5})
      : baseUrl = normalizeBaseUrl(baseUrl) {
    _client.connectionTimeout = TtsTimeouts.connect;
    _client.idleTimeout = TtsTimeouts.idle;
  }

  /// `/health` never touches the GPU, so it keeps answering in milliseconds
  /// even mid-synthesis. That is the whole reason this server exists in the
  /// shape it does: Chatterbox shared one thread between synthesis and its own
  /// health endpoint, so a long paragraph made it look dead
  /// (`docs/bugs/CHATTERBOX_DESCARGAS.md`).
  ///
  /// Factored out so [synthesize] marks the exact same key [markServerBusy]
  /// expects — a mismatched URI would silently defeat the busy short-circuit.
  static Uri _healthUri(String baseUrl) => buildUri(baseUrl, '/health');

  static Future<ServerHealth> healthOf(String baseUrl, {String token = ''}) =>
      probeServer(_healthUri(baseUrl), token: token, engine: 'f5');

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
    applyRequestHeaders(req, token: token, engine: 'f5', chars: text.length);
    req.write(jsonEncode({
      'text': text,
      'voice': voice,
      // `rate` viaja como `speed`: F5 lo aplica estirando la duración, no
      // repitiendo la síntesis, así que no cuesta tiempo extra.
      'speed': _speedFrom(rate),
    }));

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
      throw HttpException('F5 respondió ${resp.statusCode}', uri: uri);
    }

    final audio = await readBodyBytes(resp);
    if (audio.isEmpty) {
      throw const HttpException('F5 no devolvió audio');
    }

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/f5_${_uuid.v4()}.mp3';
    await File(filePath).writeAsBytes(audio);

    dev.log('[F5] ${audio.length}B → $filePath');
    // Sin marcas por palabra: mismo costo aceptado que Piper y Chatterbox.
    return TTSResult(filePath: filePath, timestamps: const []);
  }

  /// Edge expresses rate as '+0%' / '-10%'; F5 wants a multiplier.
  static double _speedFrom(String rate) {
    final m = RegExp(r'([+-]?\d+)%').firstMatch(rate);
    if (m == null) return 1.0;
    final pct = int.tryParse(m.group(1)!) ?? 0;
    return (1 + pct / 100).clamp(0.5, 2.0);
  }

  /// Catálogo servido por el propio servidor: son las voces clonadas que
  /// tenga en `voices/`, no un catálogo fijo del modelo.
  @override
  Future<List<Voice>> listVoices() async {
    try {
      final req = await _client.getUrl(_healthUri(baseUrl));
      applyRequestHeaders(req, token: token, engine: 'f5');
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
      dev.log('[F5] no se pudo leer el catálogo de voces: $e');
      return const [];
    }
  }

  @override
  Future<void> dispose() async {
    _client.close(force: true);
  }
}
