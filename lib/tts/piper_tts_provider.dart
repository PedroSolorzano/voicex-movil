import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'tts_provider.dart';

const _uuid = Uuid();

/// Piper is fast — around 1.7 s for 26 s of audio — but a whole chapter in one
/// request would still tie up the connection, so paragraphs are split like the
/// other engines.
const _maxChunkChars = 1800;

const _healthTtl = Duration(seconds: 30);

/// Talks to a Piper HTTP server (`python -m piper.http_server`) on the local
/// network.
///
/// Piper's voices are trained per language, so unlike Kokoro there is no
/// language parameter to get wrong: the model on the server *is* the language.
/// The trade-off is that **Piper reports no word timings**. Its API exposes
/// phoneme alignments, but the Spanish models return an empty list, so the
/// reader falls back to estimated sentence marks. That is a deliberate,
/// accepted cost: it buys a natively Spanish voice for listening, where
/// word-level highlighting matters least.
class PiperTtsProvider implements TTSProvider {
  final String baseUrl;

  /// Phoneme length. Above 1.0 slows the voice down; the Argentine model in
  /// particular reads fast at its default pace.
  final double lengthScale;

  final HttpClient _client = HttpClient();

  PiperTtsProvider(String baseUrl, {this.lengthScale = 1.0})
      : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl {
    _client.connectionTimeout = const Duration(seconds: 5);
  }

  static final Map<String, ({DateTime at, bool ok})> _healthCache = {};

  static Future<bool> isReachable(String baseUrl) async {
    final cached = _healthCache[baseUrl];
    if (cached != null && DateTime.now().difference(cached.at) < _healthTtl) {
      return cached.ok;
    }

    var ok = false;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      // /info is the server's cheapest endpoint; there is no /health.
      final req = await client.getUrl(Uri.parse('$baseUrl/info'));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      ok = resp.statusCode == 200;
      await resp.drain<void>();
    } catch (e) {
      dev.log('[Piper] $baseUrl unreachable: $e');
    } finally {
      client.close(force: true);
    }

    _healthCache[baseUrl] = (at: DateTime.now(), ok: ok);
    return ok;
  }

  static void resetHealthCache() => _healthCache.clear();

  @override
  Future<TTSResult> synthesize({
    required String text,
    required String voice,
    required String rate,
    required String volume,
  }) async {
    final chunks = _split(text);
    final wavs = <List<int>>[];

    for (final chunk in chunks) {
      wavs.add(await _synthesizeChunk(chunk, voice));
    }

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/piper_${_uuid.v4()}.wav';
    await File(filePath).writeAsBytes(_concatWav(wavs));

    dev.log('[Piper] ${chunks.length} chunk(s) → $filePath');
    // No timings: ReaderNotifier estimates sentence marks from the duration.
    return TTSResult(filePath: filePath, timestamps: const []);
  }

  Future<List<int>> _synthesizeChunk(String text, String voice) async {
    final uri = Uri.parse('$baseUrl/synthesize');
    final req = await _client.postUrl(uri);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({
      'text': text,
      // Empty means "whatever model the server was started with".
      if (voice.isNotEmpty) 'voice': voice,
      'length_scale': lengthScale,
    }));

    final resp = await req.close().timeout(const Duration(seconds: 120));
    if (resp.statusCode != 200) {
      await resp.drain<void>();
      throw HttpException('Piper respondió ${resp.statusCode}', uri: uri);
    }

    final bytes = <int>[];
    await for (final part in resp) {
      bytes.addAll(part);
    }
    return bytes;
  }

  /// Joins WAV chunks by keeping the first header and appending only the sample
  /// data of the rest, then correcting the two length fields.
  ///
  /// Concatenating the files as-is would embed a 44-byte header mid-stream,
  /// which players render as a click.
  List<int> _concatWav(List<List<int>> wavs) {
    if (wavs.isEmpty) return const [];
    if (wavs.length == 1) return wavs.first;

    const headerLength = 44;
    final out = <int>[...wavs.first];

    for (final wav in wavs.skip(1)) {
      if (wav.length <= headerLength) continue;
      out.addAll(wav.sublist(headerLength));
    }

    final dataLength = out.length - headerLength;
    _writeUint32(out, 4, out.length - 8); // RIFF chunk size
    _writeUint32(out, 40, dataLength); // data chunk size
    return out;
  }

  void _writeUint32(List<int> bytes, int offset, int value) {
    bytes[offset] = value & 0xFF;
    bytes[offset + 1] = (value >> 8) & 0xFF;
    bytes[offset + 2] = (value >> 16) & 0xFF;
    bytes[offset + 3] = (value >> 24) & 0xFF;
  }

  List<String> _split(String text) {
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
      final req = await _client.getUrl(Uri.parse('$baseUrl/voices'));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return const [];
      }
      final body = await resp.transform(utf8.decoder).join();
      final map = jsonDecode(body) as Map<String, dynamic>;

      return map.entries.map((e) {
        final info = e.value is Map ? e.value as Map : const {};
        final language = info['language'];
        final code = language is Map
            ? (language['code'] as String? ?? '')
            : (language as String? ?? '');
        return Voice(
          id: e.key,
          name: info['name'] as String? ?? e.key,
          locale: code,
          gender: 'unknown',
        );
      }).toList();
    } catch (e) {
      dev.log('[Piper] listVoices failed: $e');
      return const [];
    }
  }

  @override
  Future<void> dispose() async {
    _client.close(force: true);
  }
}
