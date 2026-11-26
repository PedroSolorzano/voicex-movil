import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicex_movil/storage/audio_importer.dart';
import 'package:voicex_movil/storage/database.dart';
import 'package:voicex_movil/storage/mac_audio_fetcher.dart';
import 'package:voicex_movil/storage/repositories.dart';

/// Audio generated on the Mac reaches the phone over the network and goes
/// through the same import as the cable.
void main() {
  late Directory tmp, inbox, docs;
  late HttpServer server;
  late List<String> requested;
  late int bookId;

  const voice = 'chatterbox2-colombiana';

  Map<String, dynamic> manifest(List<int> paragraphs, {String fmt = 'f96'}) => {
        'version': 1,
        'contentHash': 'hashV',
        'title': 'Visión ciega',
        'voiceId': voice,
        'format': fmt,
        'items': [
          for (final p in paragraphs)
            {'chapter': 3, 'paragraph': p, 'file': 'c3_p$p.mp3'}
        ],
      };

  Future<void> serve(Map<String, dynamic> m,
      {String token = 'tk', Set<String> broken = const {}}) async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requested.add(req.uri.path);
      if (req.headers.value('authorization') != 'Bearer $token') {
        req.response.statusCode = 401;
      } else if (req.uri.path == '/audios') {
        req.response.write(jsonEncode({
          'libros': [
            {'carpeta': 'vision-ciega', 'manifest': m}
          ]
        }));
      } else if (broken.contains(req.uri.pathSegments.last)) {
        req.response.statusCode = 404;
      } else {
        req.response.add(List.filled(2000, 7));
      }
      await req.response.close();
    });
  }

  String url() => 'http://127.0.0.1:${server.port}';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await useDatabaseAt(inMemoryDatabasePath);
    tmp = await Directory.systemTemp.createTemp('voicex_fetch_test');
    inbox = Directory('${tmp.path}/importar');
    docs = await Directory('${tmp.path}/docs').create();
    requested = [];
    final epub = File('${tmp.path}/v.epub')..writeAsBytesSync([1]);
    bookId = await LibraryRepo().add(
        title: 'Visión ciega',
        author: 'Peter Watts',
        filePath: epub.path,
        language: 'es',
        contentHash: 'hashV');
  });

  tearDown(() async {
    await server.close(force: true);
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<FetchResult> fetch({String token = 'tk'}) => fetchMacAudio(
      baseUrl: url(), token: token, inbox: inbox, formatTag: 'f96');

  test('what the Mac generated ends up downloaded, as by cable', () async {
    await serve(manifest([467, 468, 469]));

    final got = await fetch();
    expect(got.fetched, 3);
    expect(got.problems, isEmpty);

    final imported = await importMacAudio(
        inbox: inbox, docsDir: docs, formatTag: 'f96');
    expect(imported.imported, 3);
    expect(imported.problems, isEmpty);
    expect(
        await AudioCacheRepo()
            .isPinnedParagraph(bookId, 3, 468, voice, 'f96'),
        isTrue);
  });

  test('a paragraph already on the phone is not requested again', () async {
    final f = File('${docs.path}/ya.mp3')..writeAsBytesSync(List.filled(900, 1));
    await AudioCacheRepo().savePin(bookId, 3, 467, voice, 'f96', f.path, 1);
    await serve(manifest([467, 468]));

    final got = await fetch();

    expect(got.fetched, 1);
    expect(requested, isNot(contains('/audios/vision-ciega/c3_p467.mp3')));
    expect(requested, contains('/audios/vision-ciega/c3_p468.mp3'));
  });

  test('a file that does not arrive is left out of the manifest and said',
      () async {
    await serve(manifest([1, 2]), broken: {'c3_p2.mp3'});

    final got = await fetch();
    expect(got.fetched, 1);
    expect(got.problems.single, contains('no llegaron'));

    // The importer finds a consistent folder: nothing reported as failed.
    final imported = await importMacAudio(
        inbox: inbox, docsDir: docs, formatTag: 'f96');
    expect(imported.imported, 1);
    expect(imported.problems, isEmpty);
  });

  test('another cache format is not downloaded at all', () async {
    await serve(manifest([1], fmt: 'f80'));

    final got = await fetch();

    expect(got.fetched, 0);
    expect(got.problems.single, contains('otro formato'));
    expect(requested, ['/audios']);
  });

  test('a book that is not in the library is not downloaded', () async {
    await serve({...manifest([1]), 'contentHash': 'otro'});

    final got = await fetch();

    expect(got.fetched, 0);
    expect(got.problems.single, contains('no está en tu biblioteca'));
  });

  test('a Mac out of reach says so instead of failing', () async {
    await serve(manifest([1]));
    final port = server.port;
    await server.close(force: true);

    final got = await fetchMacAudio(
        baseUrl: 'http://127.0.0.1:$port',
        token: 'tk',
        inbox: inbox,
        formatTag: 'f96');

    expect(got.fetched, 0);
    expect(got.problems.single, contains('Tailscale'));
  });

  test('a rejected token is reported, not taken for an empty Mac', () async {
    await serve(manifest([1]));

    final got = await fetch(token: 'mal');

    expect(got.fetched, 0);
    expect(got.problems.single, contains('401'));
  });

  test('without a server address it does nothing', () async {
    await serve(manifest([1]));

    final got = await fetchMacAudio(
        baseUrl: '', token: '', inbox: inbox, formatTag: 'f96');

    expect(got.fetched, 0);
    expect(got.problems, isEmpty);
    expect(requested, isEmpty);
  });
}
