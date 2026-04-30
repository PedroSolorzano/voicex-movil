import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'tts_provider.dart';

const _token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
const _chromiumVersion = '130.0.2849.68';
const _uuid = Uuid();

// Sec-MS-GEC: SHA256 of rounded Windows-epoch ticks + token, uppercased.
// Windows FILETIME = (Unix seconds + 11644473600) * 10^7  (100-ns intervals since 1601-01-01)
String _generateSecMsGec() {
  const windowsEpochOffset = 11644473600;
  final unixSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final ticks = BigInt.from(unixSec + windowsEpochOffset) * BigInt.from(10000000);
  final interval = BigInt.from(3000000000);
  final rounded = ticks - (ticks % interval);
  final payload = '$rounded$_token';
  return sha256.convert(utf8.encode(payload)).toString().toUpperCase();
}

const _headers = {
  'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
  'Cache-Control': 'no-cache',
  'Pragma': 'no-cache',
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/$_chromiumVersion Safari/537.36 Edg/$_chromiumVersion',
  'Accept-Encoding': 'gzip, deflate, br',
  'Accept-Language': 'en-US,en;q=0.9',
};

class EdgeTtsProvider implements TTSProvider {
  @override
  Future<TTSResult> synthesize({
    required String text,
    required String voice,
    required String rate,
    required String volume,
  }) async {
    final connectionId = _uuid.v4().replaceAll('-', '');
    final requestId = _uuid.v4().replaceAll('-', '');
    final secMsGec = _generateSecMsGec();

    final wsUrl =
        'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1'
        '?TrustedClientToken=$_token'
        '&Sec-MS-GEC=$secMsGec'
        '&Sec-MS-GEC-Version=1-$_chromiumVersion'
        '&ConnectionId=$connectionId';

    final ws = await WebSocket.connect(wsUrl, headers: _headers);

    final audioChunks = <Uint8List>[];
    final timestamps = <WordTimestamp>[];
    final completer = Completer<void>();

    ws.listen(
      (data) {
        if (data is String) {
          _parseTextMessage(data, timestamps);
          if (data.contains('turn.end') && !completer.isCompleted) {
            completer.complete();
          }
        } else if (data is List<int>) {
          final chunk = _extractAudioChunk(Uint8List.fromList(data));
          if (chunk != null) audioChunks.add(chunk);
        }
      },
      onError: (e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
    );

    ws.add(_configMessage(requestId));
    ws.add(_ssmlMessage(requestId, text, voice, rate, volume));

    await completer.future.timeout(const Duration(seconds: 30));
    await ws.close();

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/edge_${_uuid.v4()}.mp3';
    final combined = Uint8List.fromList(audioChunks.expand((b) => b).toList());
    await File(filePath).writeAsBytes(combined);

    return TTSResult(filePath: filePath, timestamps: timestamps);
  }

  String _configMessage(String requestId) {
    final ts = _timestamp();
    return 'X-Timestamp:$ts\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"true"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';
  }

  String _ssmlMessage(String requestId, String text, String voice, String rate,
      String volume) {
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

  Uint8List? _extractAudioChunk(Uint8List bytes) {
    for (int i = 0; i < bytes.length - 3; i++) {
      if (bytes[i] == 0x0d &&
          bytes[i + 1] == 0x0a &&
          bytes[i + 2] == 0x0d &&
          bytes[i + 3] == 0x0a) {
        return bytes.sublist(i + 4);
      }
    }
    return null;
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
