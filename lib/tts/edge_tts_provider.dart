import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer' as dev;
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'tts_provider.dart';

// Source of truth: github.com/rany2/edge-tts/blob/master/src/edge_tts/constants.py
const _token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
const _chromiumFullVersion = '143.0.3650.75';
const _chromiumMajorVersion = '143';
const _uuid = Uuid();
final _rng = Random.secure();

// Persistent clock skew (mirrors Python DRM.clock_skew_seconds).
// Non-zero when the device clock differs from Microsoft's server clock.
double _clockSkewSeconds = 0.0;

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
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
          ' (KHTML, like Gecko) Chrome/$_chromiumMajorVersion.0.0.0 Safari/537.36'
          ' Edg/$_chromiumMajorVersion.0.0.0',
      'Cookie': 'muid=$muid;',
    };

class EdgeTtsProvider implements TTSProvider {
  // Calibrate _clockSkewSeconds by reading the Date header from a Microsoft endpoint.
  // Mirrors Python DRM.handle_client_response_error() but uses a separate HTTP request
  // because dart:io WebSocket.connect() does not expose 403 response headers.
  Future<void> _adjustClockSkew() async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(
        'https://speech.platform.bing.com/consumer/speech/synthesize/'
        'readaloud/voices/list?trustedclienttoken=$_token',
      );
      final req = await client.getUrl(uri);
      req.headers.set(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        ' (KHTML, like Gecko) Chrome/$_chromiumMajorVersion.0.0.0 Safari/537.36'
        ' Edg/$_chromiumMajorVersion.0.0.0',
      );
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

    dev.log('[EdgeTTS] Sec-MS-GEC: $secMsGec (skew=${_clockSkewSeconds.toStringAsFixed(1)}s)');
    dev.log('[EdgeTTS] Connecting…');

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

    int _binaryCount = 0;
    ws.listen(
      (data) {
        if (data is String) {
          final pathMatch = RegExp(r'Path:(\S+)').firstMatch(data);
          dev.log('[EdgeTTS] TEXT path=${pathMatch?.group(1) ?? "?"} len=${data.length}');
          _parseTextMessage(data, timestamps);
          if (data.contains('turn.end') && !completer.isCompleted) {
            dev.log('[EdgeTTS] turn.end → completing');
            completer.complete();
          }
        } else if (data is List<int>) {
          _binaryCount++;
          final chunk = _extractAudioChunk(Uint8List.fromList(data));
          if (chunk != null) audioChunks.add(chunk);
          if (_binaryCount <= 3 || _binaryCount % 20 == 0) {
            final cumulative = audioChunks.fold(0, (s, c) => s + c.length);
            dev.log('[EdgeTTS] BINARY #$_binaryCount total=${data.length}B chunk=${chunk?.length ?? 0}B cumulative=${cumulative}B');
          }
        }
      },
      onError: (e) {
        dev.log('[EdgeTTS] WS error: $e');
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        final cumulative = audioChunks.fold(0, (s, c) => s + c.length);
        dev.log('[EdgeTTS] WS closed — binary=$_binaryCount audio=${cumulative}B completed=${completer.isCompleted}');
        if (!completer.isCompleted) completer.complete();
      },
    );

    ws.add(_configMessage());
    ws.add(_ssmlMessage(requestId, text, voice, rate, volume));

    await completer.future.timeout(const Duration(seconds: 30));
    await ws.close();

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/edge_${_uuid.v4()}.mp3';
    final combined = Uint8List.fromList(audioChunks.expand((b) => b).toList());
    await File(filePath).writeAsBytes(combined);

    dev.log('[EdgeTTS] Wrote ${combined.length} bytes → $filePath');
    return TTSResult(filePath: filePath, timestamps: timestamps);
  }

  String _configMessage() {
    final ts = _timestamp();
    return 'X-Timestamp:$ts\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"true"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';
  }

  String _ssmlMessage(
      String requestId, String text, String voice, String rate, String volume) {
    final ts = _timestamp();
    final ssml =
        "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
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

  @override
  Future<List<Voice>> listVoices() async => [];

  @override
  Future<void> dispose() async {}
}
