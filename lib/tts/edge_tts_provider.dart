import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'models.dart';
import 'tts_provider.dart';

const _token = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';
const _uuid = Uuid();

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
    final uri = Uri.parse(
      'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1'
      '?TrustedClientToken=$_token&ConnectionId=$connectionId',
    );

    final channel = WebSocketChannel.connect(
      uri,
      protocols: const ['wss'],
    );

    // Send config
    channel.sink.add(_configMessage(requestId));
    // Send SSML
    channel.sink.add(_ssmlMessage(requestId, text, voice, rate, volume));

    final audioChunks = <Uint8List>[];
    final timestamps = <WordTimestamp>[];
    final completer = Completer<void>();

    channel.stream.listen(
      (data) {
        if (data is String) {
          _parseTextMessage(data, timestamps);
          if (data.contains('turn.end')) completer.complete();
        } else if (data is List<int>) {
          final bytes = Uint8List.fromList(data);
          final chunk = _extractAudioChunk(bytes);
          if (chunk != null) audioChunks.add(chunk);
        }
      },
      onError: (e) => completer.completeError(e),
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
    );

    await completer.future.timeout(const Duration(seconds: 30));
    await channel.sink.close();

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/edge_${_uuid.v4()}.mp3';
    final combined = Uint8List.fromList(audioChunks.expand((b) => b).toList());
    await File(filePath).writeAsBytes(combined);

    return TTSResult(filePath: filePath, timestamps: timestamps);
  }

  String _configMessage(String requestId) {
    final timestamp = _timestamp();
    return 'X-Timestamp:$timestamp\r\n'
        'Content-Type:application/json; charset=utf-8\r\n'
        'Path:speech.config\r\n\r\n'
        '{"context":{"synthesis":{"audio":{"metadataoptions":{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"true"},"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}';
  }

  String _ssmlMessage(String requestId, String text, String voice, String rate,
      String volume) {
    final timestamp = _timestamp();
    final ssml =
        '<speak version=\'1.0\' xmlns=\'http://www.w3.org/2001/10/synthesis\' xml:lang=\'en-US\'>'
        '<voice name=\'$voice\'>'
        '<prosody rate=\'$rate\' volume=\'$volume\'>'
        '${_escapeXml(text)}'
        '</prosody></voice></speak>';
    return 'X-RequestId:$requestId\r\n'
        'Content-Type:application/ssml+xml\r\n'
        'X-Timestamp:$timestamp\r\n'
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
    // Edge TTS binary messages have a header ending with \r\n\r\n (0d 0a 0d 0a)
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
