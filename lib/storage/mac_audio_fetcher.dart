import 'dart:convert';
import 'dart:io';

import '../tts/tts_endpoint.dart';
import 'repositories.dart';

/// What a network fetch did before the import runs.
class FetchResult {
  /// Files brought from the Mac into the inbox, ready for [importMacAudio].
  final int fetched;

  /// Why something was not brought: the Mac was unreachable, a book is not in
  /// the library, a file failed. Shown together with the import's own.
  final List<String> problems;

  const FetchResult(this.fetched, this.problems);
}

final _folderName = RegExp(r'^[a-z0-9][a-z0-9-]{0,99}$');
final _itemFile = RegExp(r'^c\d+_p\d+\.(mp3|m4a|wav)$');

/// Brings the audio that `tools/audios/bajar.dart` generated on the Mac over
/// the network — Tailscale, the same way the voice server is reached — instead
/// of the USB cable.
///
/// It only *fetches*: each book lands in [inbox] as `red-<folder>/` with a
/// manifest of what came, exactly what `tools/audios/pasar.sh` would have left,
/// and [importMacAudio] does the rest. One import path, two ways in. The
/// `red-` prefix keeps it apart from a cable push of the same book, whose
/// manifest would otherwise be overwritten.
///
/// Paragraphs already downloaded are not requested: the Mac keeps every book it
/// generated, as a backup, so its list grows and most of it is already here.
/// Nothing is deleted on the Mac.
Future<FetchResult> fetchMacAudio({
  required String baseUrl,
  required String token,
  required Directory inbox,
  required String formatTag,
  LibraryRepo? library,
  AudioCacheRepo? cache,
  void Function(int done, int total)? onProgress,
}) async {
  if (baseUrl.trim().isEmpty) return const FetchResult(0, []);
  final books = library ?? LibraryRepo();
  final repo = cache ?? AudioCacheRepo();
  final client = HttpClient()..connectionTimeout = TtsTimeouts.connect;
  final problems = <String>[];
  var fetched = 0;

  Future<HttpClientResponse> get(String path) async {
    final req = await client.getUrl(buildUri(baseUrl, path));
    authHeaders(token).forEach(req.headers.set);
    return req.close();
  }

  try {
    final List<dynamic> listed;
    try {
      final resp = await get('/audios').timeout(TtsTimeouts.probeRetry);
      final body = await utf8.decodeStream(resp);
      if (resp.statusCode != 200) {
        return FetchResult(0, [
          resp.statusCode == 404
              ? 'El servidor del Mac no sabe dar audios todavía: reinícialo '
                    'con la versión nueva de tools/mlx.'
              : 'El Mac respondió ${resp.statusCode} al pedir los audios.',
        ]);
      }
      listed = (jsonDecode(body) as Map<String, dynamic>)['libros'] as List;
    } catch (_) {
      return const FetchResult(0, [
        'No se pudo llegar al Mac por la red. Revisa que Tailscale esté '
            'activo y el servidor encendido, o pásalos por cable.',
      ]);
    }

    // Work out everything missing first, so progress has a real total.
    final plan =
        <({String folder, Map<String, dynamic> manifest, List<Map> items})>[];
    for (final entry in listed) {
      if (entry is! Map) continue;
      final folder = entry['carpeta'];
      final manifest = entry['manifest'];
      if (folder is! String ||
          !_folderName.hasMatch(folder) ||
          manifest is! Map) {
        continue;
      }
      final m = manifest.cast<String, dynamic>();
      final title = m['title'] ?? folder;
      // Another format would not play: the importer would refuse it anyway,
      // after a download for nothing.
      if (m['format'] != formatTag) {
        problems.add(
          '$title: el audio del Mac es de otro formato; vuelve a '
          'generarlo con esta versión de la app.',
        );
        continue;
      }
      final hash = m['contentHash'];
      final voiceId = m['voiceId'];
      final items = m['items'];
      if (hash is! String || voiceId is! String || items is! List) continue;
      final book = await books.findByContentHash(hash);
      if (book == null) {
        problems.add(
          '$title: ese libro no está en tu biblioteca. Impórtalo '
          '(el mismo EPUB con el que se generó el audio).',
        );
        continue;
      }
      final bookId = book['id'] as int;
      final missing = <Map>[];
      for (final raw in items) {
        if (raw is! Map) continue;
        final ch = raw['chapter'], p = raw['paragraph'], f = raw['file'];
        if (ch is! int || p is! int || f is! String || !_itemFile.hasMatch(f)) {
          continue;
        }
        if (await repo.isPinnedParagraph(bookId, ch, p, voiceId, formatTag)) {
          continue;
        }
        missing.add(raw);
      }
      if (missing.isNotEmpty) {
        plan.add((folder: folder, manifest: m, items: missing));
      }
    }

    final total = plan.fold<int>(0, (n, b) => n + b.items.length);
    var done = 0, failed = 0;
    onProgress?.call(0, total);
    for (final book in plan) {
      final dir = Directory('${inbox.path}/red-${book.folder}');
      await dir.create(recursive: true);
      final got = <Map>[];
      for (final item in book.items) {
        final file = item['file'] as String;
        try {
          final resp = await get(
            '/audios/${book.folder}/$file',
          ).timeout(const Duration(seconds: 30));
          if (resp.statusCode != 200) {
            await resp.drain<void>();
            failed++;
          } else {
            final out = File('${dir.path}/$file');
            await resp.pipe(out.openWrite());
            if (await out.length() > 0) {
              got.add(item);
              fetched++;
            } else {
              await out.delete();
              failed++;
            }
          }
        } catch (_) {
          failed++;
        }
        onProgress?.call(++done, total);
      }
      if (got.isEmpty) {
        await dir.delete(recursive: true);
        continue;
      }
      // Only what actually arrived: a manifest naming a missing file would
      // make the importer report it as failed and keep the folder.
      await File(
        '${dir.path}/manifest.json',
      ).writeAsString(jsonEncode({...book.manifest, 'items': got}));
    }
    if (failed > 0) {
      problems.add(
        '$failed audios no llegaron del Mac (¿se cortó la red?). '
        'Vuelve a intentarlo: solo pedirá los que faltan.',
      );
    }
  } finally {
    client.close(force: true);
  }
  return FetchResult(fetched, problems);
}
