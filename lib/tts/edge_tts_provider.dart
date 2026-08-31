import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as dev;
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'tts_provider.dart';

// Source of truth: github.com/rany2/edge-tts/blob/master/src/edge_tts/constants.py
const _token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
const _chromiumFullVersion = '143.0.3650.75';
const _chromiumMajorVersion = '143';
const _uuid = Uuid();
final _rng = Random.secure();

// 96 kbit/s is the highest the free readaloud endpoint accepts. Verified against
// the live service: 48k and 96k return audio, 160k and 192k return zero bytes.
const _outputFormat = 'audio-24khz-96kbitrate-mono-mp3';

// Paragraphs longer than this are split before synthesis so a single request
// cannot outrun the 30 s timeout below.
const _maxChunkChars = 1800;

const _voicesUrl =
    'https://speech.platform.bing.com/consumer/speech/synthesize/'
    'readaloud/voices/list?trustedclienttoken=$_token';

const _voicesCacheKey = 'edgeVoicesCacheJson';
const _voicesCachedAtKey = 'edgeVoicesCachedAtMs';
const _voicesTtlMs = 7 * 24 * 60 * 60 * 1000; // 7 days

// Persistent clock skew (mirrors Python DRM.clock_skew_seconds).
// Non-zero when the device clock differs from Microsoft's server clock.
double _clockSkewSeconds = 0.0;

String _userAgent() =>
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    ' (KHTML, like Gecko) Chrome/$_chromiumMajorVersion.0.0.0 Safari/537.36'
    ' Edg/$_chromiumMajorVersion.0.0.0';

// Mirrors Python: secrets.token_hex(16).upper() — truly random 32 hex chars.
String _generateMuid() {
  final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
}

// Mirrors Python DRM.generate_sec_ms_gec():
//   ticks = get_unix_timestamp() + WIN_EPOCH
//   ticks -= ticks % 300
//   ticks *= S_TO_NS / 100  (= 1e7)
//   SHA256(f"{ticks:.0f}{token}").upper()
String _generateSecMsGec() {
  final unixSec =
      DateTime.now().toUtc().millisecondsSinceEpoch / 1000.0 + _clockSkewSeconds;
  var ticks = unixSec + 11644473600;
  ticks -= ticks % 300;
  ticks *= 10000000;
  final payload = '${ticks.toStringAsFixed(0)}$_token';
  return sha256.convert(ascii.encode(payload)).toString().toUpperCase();
}

// Mirrors Python DRM.headers_with_muid(WSS_HEADERS).
// NOTE: Sec-WebSocket-Version is intentionally omitted — dart:io adds it automatically.
// Including it here would produce a duplicate "Sec-WebSocket-Version: 13, 13" header
// because WebSocket.connect() uses headers.add() (not set()) for custom headers,
// and the server rejects duplicates with 403.
Map<String, String> _buildHeaders(String muid) => {
      'Pragma': 'no-cache',
      'Cache-Control': 'no-cache',
      'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
      'Accept-Encoding': 'gzip, deflate, br, zstd',
      'Accept-Language': 'en-US,en;q=0.9',
      'User-Agent': _userAgent(),
      'Cookie': 'muid=$muid;',
    };

/// "es-MX-DaliaNeural" -> "es-MX". Falls back to es-MX for malformed names.
///
/// The SSML previously hardcoded xml:lang='en-US' for every voice, including
/// Spanish ones. Matching the locale to the voice keeps prosody consistent.
String voiceLocale(String voice) {
  final parts = voice.split('-');
  if (parts.length >= 2) return '${parts[0]}-${parts[1]}';
  return 'es-MX';
}

/// Splits text on sentence boundaries so no single synthesis request exceeds
/// [_maxChunkChars]. A sentence longer than the limit is emitted on its own
/// rather than cut mid-word.
List<String> splitForSynthesis(String text, {int maxChars = _maxChunkChars}) {
  final trimmed = text.trim();
  if (trimmed.length <= maxChars) return [trimmed];

  final sentences = trimmed.split(RegExp(r'(?<=[.!?…])\s+'));
  final chunks = <String>[];
  final buffer = StringBuffer();

  for (final sentence in sentences) {
    final s = sentence.trim();
    if (s.isEmpty) continue;
    if (buffer.isEmpty) {
      buffer.write(s);
    } else if (buffer.length + 1 + s.length <= maxChars) {
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

class EdgeTtsProvider implements TTSProvider {
  // Calibrate _clockSkewSeconds by reading the Date header from a Microsoft endpoint.
  // Mirrors Python DRM.handle_client_response_error() but uses a separate HTTP request
  // because dart:io WebSocket.connect() does not expose 403 response headers.
  Future<void> _adjustClockSkew() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(_voicesUrl));
      req.headers.set('User-Agent', _userAgent());
      req.headers.set('Accept', 'application/json');
      final resp = await req.close();
      final dateStr = resp.headers.value('date');
      if (dateStr != null) {
        final serverMs = HttpDate.parse(dateStr).millisecondsSinceEpoch;
        final localMs = DateTime.now().toUtc().millisecondsSinceEpoch;
        _clockSkewSeconds = (serverMs - localMs) / 1000.0;
        dev.log('[EdgeTTS] Clock skew: ${_clockSkewSeconds.toStringAsFixed(2)}s');
      }
      await resp.drain<void>();
    } catch (e) {
      dev.log('[EdgeTTS] Clock skew calibration failed: $e');
    } finally {
      client.close();
    }
  }

  @override
  Future<TTSResult> synthesize({
    required String text,
    required String voice,
    required String rate,
    required String volume,
  }) async {
    final chunks = splitForSynthesis(text);
    if (chunks.length == 1) {
      return _synthesizeWithRetry(
          text: chunks.first, voice: voice, rate: rate, volume: volume);
    }

    // Long paragraph: synthesize each chunk, then concatenate the MP3 frames and
    // shift each chunk's word timestamps by the running duration.
    dev.log('[EdgeTTS] Splitting ${text.length} chars into ${chunks.length} chunks');
    final bytes = BytesBuilder();
    final timestamps = <WordTimestamp>[];
    var offsetMs = 0;

    for (final chunk in chunks) {
      final part = await _synthesizeWithRetry(
          text: chunk, voice: voice, rate: rate, volume: volume);
      final file = File(part.filePath);
      bytes.add(await file.readAsBytes());
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
      // The per-chunk temp file has been folded into the combined output.
      try {
        await file.delete();
      } catch (_) {}
    }

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/edge_${_uuid.v4()}.mp3';
    await File(filePath).writeAsBytes(bytes.takeBytes());
    return TTSResult(filePath: filePath, timestamps: timestamps);
  }

  Future<TTSResult> _synthesizeWithRetry({
    required String text,
    required String voice,
    required String rate,
    required String volume,
  }) async {
    // Retry once on 403 with clock skew correction (mirrors Python's DRM retry loop).
    for (var attempt = 0; attempt <= 1; attempt++) {
      try {
        return await _synthesizeOnce(
            text: text, voice: voice, rate: rate, volume: volume);
      } on WebSocketException catch (e) {
        if (attempt == 0 && e.message.contains('403')) {
          dev.log('[EdgeTTS] 403 → calibrating clock skew and retrying…');
          await _adjustClockSkew();
          continue;
        }
        rethrow;
      }
    }
    throw const WebSocketException('Edge TTS failed after clock skew correction');
  }

  Future<TTSResult> _synthesizeOnce({
    required String text,
    required String voice,
    required String rate,
    required String volume,
  }) async {
    final connectionId = _uuid.v4().replaceAll('-', '');
    final requestId = _uuid.v4().replaceAll('-', '');
    final muid = _generateMuid();
    final secMsGec = _generateSecMsGec();

    // Parameter order matches Python:
    //   WSS_URL?TrustedClientToken=...&ConnectionId=...&Sec-MS-GEC=...&Sec-MS-GEC-Version=...
    final wsUrl =
        'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1'
        '?TrustedClientToken=$_token'
        '&ConnectionId=$connectionId'
        '&Sec-MS-GEC=$secMsGec'
        '&Sec-MS-GEC-Version=1-$_chromiumFullVersion';

    dev.log('[EdgeTTS] Connecting… (skew=${_clockSkewSeconds.toStringAsFixed(1)}s)');

    // customClient with userAgent=null prevents dart:io from adding "Dart/3.x (dart:io)"
    // as a second User-Agent. WebSocket.connect() uses headers.add() (not set()) for
    // custom headers, so without this the server receives two conflicting User-Agent
    // values and rejects the WebSocket upgrade with 403.
    final httpClient = HttpClient()..userAgent = null;
    final ws = await WebSocket.connect(
      wsUrl,
      headers: _buildHeaders(muid),
      customClient: httpClient,
    );

    final audioChunks = <Uint8List>[];
    final timestamps = <WordTimestamp>[];
    final completer = Completer<void>();

    var binaryCount = 0;
    ws.listen(
      (data) {
        if (data is String) {
          _parseTextMessage(data, timestamps);
          if (data.contains('turn.end') && !completer.isCompleted) {
            completer.complete();
          }
        } else if (data is List<int>) {
          binaryCount++;
          final chunk = _extractAudioChunk(Uint8List.fromList(data));
          if (chunk != null) audioChunks.add(chunk);
        }
      },
      onError: (e) {
        dev.log('[EdgeTTS] WS error: $e');
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
    );

    ws.add(_configMessage());
    ws.add(_ssmlMessage(requestId, text, voice, rate, volume));

    try {
      await completer.future.timeout(const Duration(seconds: 30));
    } finally {
      await ws.close();
      httpClient.close(force: true);
    }

    final combined = Uint8List.fromList(audioChunks.expand((b) => b).toList());

    // A timeout or a dropped connection leaves zero chunks. Writing that out
    // produces a file the player cannot open — and worse, the caller caches it,
    // so the paragraph stays broken for good. Fail loudly instead.
    if (combined.isEmpty) {
      throw const WebSocketException(
          'Edge TTS no devolvió audio (conexión interrumpida o texto rechazado)');
    }

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/edge_${_uuid.v4()}.mp3';
    await File(filePath).writeAsBytes(combined);

    dev.log('[EdgeTTS] ${combined.length}B in $binaryCount frames, '
        '${timestamps.length} word marks');
    return TTSResult(filePath: filePath, timestamps: timestamps);
  }

  String _configMessage() {
    final ts = _timestamp();
    return 'X-Timestamp:$ts\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":'
        '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"true"},'
        '"outputFormat":"$_outputFormat"}}}}';
  }

  String _ssmlMessage(
      String requestId, String text, String voice, String rate, String volume) {
    final ts = _timestamp();
    final lang = voiceLocale(voice);
    final ssml =
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='$lang'>"
        "<voice name='$voice'>"
        "<prosody rate='$rate' volume='$volume'>"
        '${_escapeXml(text)}'
        '</prosody></voice></speak>';
    return 'X-RequestId:$requestId\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:$ts\r\n'
        'Path:ssml\r\n\r\n'
        '$ssml';
  }

  void _parseTextMessage(String data, List<WordTimestamp> timestamps) {
    if (!data.contains('WordBoundary')) return;
    try {
      final bodyStart = data.indexOf('\r\n\r\n');
      if (bodyStart == -1) return;
      final body = data.substring(bodyStart + 4);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final metadata = json['Metadata'] as List?;
      if (metadata == null) return;
      for (final item in metadata) {
        if (item['Type'] != 'WordBoundary') continue;
        final d = item['Data'] as Map<String, dynamic>;
        final offset = ((d['Offset'] as num) / 10000).round();
        final duration = ((d['Duration'] as num) / 10000).round();
        timestamps.add(WordTimestamp(
          word: d['text']?['Text'] as String? ?? '',
          offsetMs: offset,
          durationMs: duration,
        ));
      }
    } catch (_) {}
  }

  // Binary message format: [uint16 big-endian header length][header bytes][audio bytes]
  // WebSocket text frame uses \r\n\r\n but binary frames use a 2-byte length prefix.
  Uint8List? _extractAudioChunk(Uint8List bytes) {
    if (bytes.length < 2) return null;
    final headerLen = (bytes[0] << 8) | bytes[1];
    final audioStart = 2 + headerLen;
    if (bytes.length <= audioStart) return null;
    return bytes.sublist(audioStart);
  }

  String _timestamp() => DateTime.now().toUtc().toIso8601String();

  String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// Full Edge catalogue (300+ voices), cached in SharedPreferences for 7 days.
  /// Falls back to the stale cache, then to an empty list, if the network fails —
  /// callers treat empty as "use the hardcoded voiceMap".
  @override
  Future<List<Voice>> listVoices() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_voicesCacheKey);
    final cachedAt = prefs.getInt(_voicesCachedAtKey) ?? 0;
    final fresh =
        DateTime.now().millisecondsSinceEpoch - cachedAt < _voicesTtlMs;

    if (cached != null && fresh) {
      final parsed = _decodeVoices(cached);
      if (parsed.isNotEmpty) return parsed;
    }

    try {
      final raw = await _fetchVoicesJson();
      final parsed = _decodeVoices(raw);
      if (parsed.isNotEmpty) {
        await prefs.setString(_voicesCacheKey, raw);
        await prefs.setInt(
            _voicesCachedAtKey, DateTime.now().millisecondsSinceEpoch);
      }
      return parsed;
    } catch (e) {
      dev.log('[EdgeTTS] listVoices failed: $e');
      return cached != null ? _decodeVoices(cached) : <Voice>[];
    }
  }

  Future<String> _fetchVoicesJson() async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(_voicesUrl));
      req.headers.set('User-Agent', _userAgent());
      req.headers.set('Accept', 'application/json');
      final resp = await req.close();
      if (resp.statusCode != 200) {
        throw HttpException('voices list returned ${resp.statusCode}');
      }
      return await resp.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  List<Voice> _decodeVoices(String raw) {
    try {
      final list = jsonDecode(raw) as List;
      return list
          .whereType<Map<String, dynamic>>()
          .map((v) => Voice(
                id: v['ShortName'] as String? ?? '',
                name: v['FriendlyName'] as String? ??
                    v['ShortName'] as String? ??
                    '',
                locale: v['Locale'] as String? ?? '',
                gender: (v['Gender'] as String? ?? '').toLowerCase(),
              ))
          .where((v) => v.id.isNotEmpty)
          .toList();
    } catch (e) {
      dev.log('[EdgeTTS] voice cache decode failed: $e');
      return <Voice>[];
    }
  }

  @override
  Future<void> dispose() async {}
}
