import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'server_health.dart';
import 'tts_endpoint.dart';
import 'tts_provider.dart';

const _uuid = Uuid();

/// Long paragraphs are split before synthesis so a single request cannot run
/// past the timeout. Matches the Edge provider's limit; servers before v0.8
/// return timings in a response header, and this also keeps that header sane.
const _maxChunkChars = 1800;

/// Talks to a self-hosted Kokoro-FastAPI instance over the local network.
///
/// Uses `/dev/captioned_speech` rather than `/v1/audio/speech` because only the
/// former returns word timings, which the reader needs for the word-by-word
/// highlight.
///
/// **Language** is the subtle part. The server otherwise infers it from the
/// voice prefix (`af_` → English), which mangles Spanish read by an
/// English-timbre voice: the same paragraph comes out at 17 s instead of 26 s,
/// pronounced with English rules. Sending [langCode] explicitly fixes it.
///
/// Servers from v0.8 accept `lang_code` per request. Older builds ignore
/// unknown fields, so for those the container must instead be started with
/// `DEFAULT_VOICE_CODE=e`. Sending the field regardless is forward-compatible
/// and harmless either way.
/// Converts Kokoro's `{word, start_time, end_time}` entries, whose times are in
/// seconds, into the millisecond form the reader uses.
///
/// Servers before v0.8 emit each word twice; the repeat is harmless because
/// `buildWordMarks` anchors words by searching forward from a cursor and so
/// skips it. Anything unparseable yields an empty list, which makes the reader
/// fall back to estimated sentence marks rather than fail outright.
List<WordTimestamp> parseKokoroTimestamps(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map<String, dynamic>>()
      .map((e) {
        final start = ((e['start_time'] as num?) ?? 0) * 1000;
        final end = ((e['end_time'] as num?) ?? 0) * 1000;
        return WordTimestamp(
          word: (e['word'] as String? ?? '').trim(),
          offsetMs: start.round(),
          durationMs: (end - start).round().clamp(0, 1 << 30),
        );
      })
      .where((t) => t.word.isNotEmpty)
      .toList();
}

/// Maps the app's book language to Kokoro's single-letter language pack.
String kokoroLangCode(String bookLanguage) =>
    bookLanguage.toLowerCase().startsWith('es') ? 'e' : 'a';

class KokoroTtsProvider implements TTSProvider {
  final String baseUrl;

  /// Kokoro language pack: 'a' US English, 'b' UK English, 'e' Spanish,
  /// 'f' French, 'i' Italian, 'p' Brazilian Portuguese, 'j' Japanese, 'z' Chinese.
  final String langCode;

  /// Bearer credential for the proxy that fronts the server. Empty when the
  /// server is reached directly, which is still how it works on the LAN.
  final String token;

  final HttpClient _client = HttpClient();

  KokoroTtsProvider(String baseUrl, {this.langCode = 'a', this.token = ''})
      : baseUrl = normalizeBaseUrl(baseUrl) {
    // Synthesis is CPU-bound on the server: ~5x realtime was measured, so a
    // long paragraph legitimately takes several seconds.
    _client.connectionTimeout = TtsTimeouts.connect;
    _client.idleTimeout = TtsTimeouts.idle;
  }

  /// Full verdict on the server: reachable, refusing the token, or broken.
  static Future<ServerHealth> healthOf(String baseUrl, {String token = ''}) =>
      probeServer(buildUri(baseUrl, '/health'),
          token: token, engine: 'kokoro');

  /// Whether the server answers, for callers that only need a yes or no.
  static Future<bool> isReachable(String baseUrl, {String token = ''}) async =>
      (await healthOf(baseUrl, token: token)).isUsable;

  /// Forgets cached health, so a retry probes the server immediately.
  static void resetHealthCache() => resetServerHealthCache();

  @override
  Future<TTSResult> synthesize({
    required String text,
    required String voice,
    required String rate,
    required String volume,
  }) async {
    final chunks = _splitForSynthesis(text);
    final bytes = BytesBuilder();
    final timestamps = <WordTimestamp>[];
    var offsetMs = 0;

    for (final chunk in chunks) {
      final part = await _synthesizeChunk(chunk, voice);
      bytes.add(part.audio);
      for (final t in part.timestamps) {
        timestamps.add(WordTimestamp(
          word: t.word,
          offsetMs: t.offsetMs + offsetMs,
          durationMs: t.durationMs,
        ));
      }
      if (part.timestamps.isNotEmpty) {
        final last = part.timestamps.last;
        offsetMs += last.offsetMs + last.durationMs;
      }
    }

    final audio = bytes.takeBytes();
    if (audio.isEmpty) {
      throw const HttpException('Kokoro no devolvió audio');
    }

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/kokoro_${_uuid.v4()}.mp3';
    await File(filePath).writeAsBytes(audio);

    dev.log('[Kokoro] ${chunks.length} chunk(s), ${timestamps.length} word marks');
    return TTSResult(filePath: filePath, timestamps: timestamps);
  }

  Future<({List<int> audio, List<WordTimestamp> timestamps})> _synthesizeChunk(
      String text, String voice) async {
    final uri = buildUri(baseUrl, '/dev/captioned_speech');
    final req = await _client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    applyRequestHeaders(req,
        token: token, engine: 'kokoro', chars: text.length);
    req.write(jsonEncode({
      'model': 'kokoro',
      'input': text,
      'voice': voice,
      'response_format': 'mp3',
      // Playback speed is applied by the player so one cached file serves every
      // speed; synthesis stays neutral.
      'speed': 1.0,
      'lang_code': langCode,
      // Streaming is the server default and emits newline-delimited JSON
      // fragments; a single response is far simpler to consume.
      'stream': false,
      'return_timestamps': true,
    }));

    final resp = await req.close().timeout(TtsTimeouts.synthesisKokoro);
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      throw HttpException('Kokoro respondió ${resp.statusCode}', uri: uri);
    }

    final isJson =
        resp.headers.contentType?.mimeType.contains('json') ?? false;

    if (isJson) {
      // v0.8+: {"audio": base64, "audio_format": "mp3", "timestamps": [...]}.
      // Carrying the timings in the body removes the header size ceiling.
      final body = await readBodyString(resp);
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (
        audio: base64Decode(json['audio'] as String? ?? ''),
        timestamps: parseKokoroTimestamps(json['timestamps']),
      );
    }

    // Older servers: raw audio in the body, timings in a header.
    final audio = await readBodyBytes(resp);
    final header = resp.headers.value('x-word-timestamps');
    return (
      audio: audio,
      timestamps: header == null || header.isEmpty
          ? const <WordTimestamp>[]
          : parseKokoroTimestamps(_tryDecode(header)),
    );
  }

  Object? _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (e) {
      dev.log('[Kokoro] timestamp header unusable (${raw.length}B): $e');
      return null;
    }
  }

  /// Splits on sentence boundaries so no request exceeds [_maxChunkChars].
  List<String> _splitForSynthesis(String text) {
    final trimmed = text.trim();
    if (trimmed.length <= _maxChunkChars) return [trimmed];

    final sentences = trimmed.split(RegExp(r'(?<=[.!?…])\s+'));
    final chunks = <String>[];
    final buffer = StringBuffer();

    for (final sentence in sentences) {
      final s = sentence.trim();
      if (s.isEmpty) continue;
      if (buffer.isEmpty) {
        buffer.write(s);
      } else if (buffer.length + 1 + s.length <= _maxChunkChars) {
        buffer.write(' ');
        buffer.write(s);
      } else {
        chunks.add(buffer.toString());
        buffer.clear();
        buffer.write(s);
      }
    }
    if (buffer.isNotEmpty) chunks.add(buffer.toString());
    return chunks.isEmpty ? [trimmed] : chunks;
  }

  @override
  Future<List<Voice>> listVoices() async {
    try {
      final uri = buildUri(baseUrl, '/v1/audio/voices');
      final req = await _client.getUrl(uri);
      applyRequestHeaders(req, token: token, engine: 'kokoro');
      final resp = await req.close().timeout(TtsTimeouts.catalogue);
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return const [];
      }
      final body = await readBodyString(resp, timeout: TtsTimeouts.catalogue);
      final ids = (jsonDecode(body)['voices'] as List?) ?? const [];

      return ids
          .whereType<String>()
          // v0 entries are superseded duplicates of the current packs.
          .where((id) => !id.contains('v0'))
          .map((id) => Voice(
                id: id,
                name: _friendlyName(id),
                locale: _localeFor(id),
                gender: _genderFor(id),
              ))
          .toList();
    } catch (e) {
      dev.log('[Kokoro] listVoices failed: $e');
      return const [];
    }
  }

  /// "af_bella" -> "Bella (US, femenina)".
  String _friendlyName(String id) {
    final parts = id.split('_');
    final name = parts.length > 1 ? parts.last : id;
    final capitalised =
        name.isEmpty ? name : name[0].toUpperCase() + name.substring(1);
    final region = _regionLabel(id);
    final gender = _genderFor(id) == 'male' ? 'masculina' : 'femenina';
    return '$capitalised ($region, $gender)';
  }

  // Kokoro encodes language and gender in the two-letter prefix: the first
  // letter is the language pack, the second the gender.
  String _localeFor(String id) => switch (id.isEmpty ? '' : id[0]) {
        'a' => 'en-US',
        'b' => 'en-GB',
        'e' => 'es',
        'f' => 'fr-FR',
        'h' => 'hi',
        'i' => 'it',
        'j' => 'ja',
        'p' => 'pt-BR',
        'z' => 'zh',
        _ => '',
      };

  String _regionLabel(String id) => switch (id.isEmpty ? '' : id[0]) {
        'a' => 'US',
        'b' => 'UK',
        'e' => 'ES',
        'f' => 'FR',
        'h' => 'HI',
        'i' => 'IT',
        'j' => 'JA',
        'p' => 'BR',
        'z' => 'ZH',
        _ => '?',
      };

  String _genderFor(String id) =>
      id.length > 1 && id[1] == 'm' ? 'male' : 'female';

  @override
  Future<void> dispose() async {
    _client.close(force: true);
  }
}
