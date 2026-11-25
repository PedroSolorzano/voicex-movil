import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicex_movil/storage/book_exporter.dart';
import 'package:voicex_movil/storage/database.dart';
import 'package:voicex_movil/storage/repositories.dart';

/// The Mac must generate from the very file the phone holds: the audio is found
/// again by the hash of its bytes.
void main() {
  late Directory tmp, out;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await useDatabaseAt(inMemoryDatabasePath);
    tmp = await Directory.systemTemp.createTemp('voicex_export_test');
    out = Directory('${tmp.path}/libros');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<void> addBook(String title, List<int> bytes, {String hash = 'h'}) async {
    final f = File('${tmp.path}/${title.hashCode}-${bytes.length}.epub')
      ..writeAsBytesSync(bytes);
    await LibraryRepo().add(
        title: title,
        author: 'A',
        filePath: f.path,
        language: 'es',
        contentHash: hash);
  }

  test('copies the exact bytes under the title of the book', () async {
    await addBook('Visión ciega', [1, 2, 3, 4]);

    expect(await exportLibraryBooks(out), 1);

    expect(File('${out.path}/Visión ciega.epub').readAsBytesSync(),
        [1, 2, 3, 4]);
  });

  test('two editions with one title do not overwrite each other', () async {
    await addBook('Visión ciega', [1, 2], hash: 'aaaaaaaa11');
    await addBook('Visión ciega', [9, 9, 9], hash: 'bbbbbbbb22');

    expect(await exportLibraryBooks(out), 2);
    expect(out.listSync().length, 2);
  });

  test('a title with characters a path cannot carry is cleaned', () async {
    await addBook('¿Qué: hoy/mañana?', [1]);

    await exportLibraryBooks(out);

    expect(out.listSync().single.path, endsWith('¿Qué hoy mañana.epub'));
  });

  test('a book that left the library leaves the folder too', () async {
    await addBook('Uno', [1]);
    await exportLibraryBooks(out);
    File('${out.path}/Viejo.epub').writeAsBytesSync([5]);

    await exportLibraryBooks(out);

    expect(File('${out.path}/Viejo.epub').existsSync(), isFalse);
    expect(File('${out.path}/Uno.epub').existsSync(), isTrue);
  });

  test('an empty library exports nothing', () async {
    expect(await exportLibraryBooks(out), 0);
  });

  group('inventory of what the phone already has', () {
    Future<Map<String, dynamic>> inventory() async => jsonDecode(
        await File('${out.path}/inventario.json').readAsString())
        as Map<String, dynamic>;

    Future<void> pin(int book, int ch, int para, String voice,
        {bool file = true, String fmt = 'f96'}) async {
      final f = File('${tmp.path}/a_${book}_${ch}_${para}_$voice.mp3');
      if (file) f.writeAsBytesSync(List.filled(1500, 1));
      await AudioCacheRepo().savePin(book, ch, para, voice, fmt, f.path, 2);
    }

    test('lists downloaded paragraphs per book hash, voice and chapter',
        () async {
      await addBook('Visión ciega', [1], hash: 'hashV');
      final id = (await LibraryRepo().all()).single['id'] as int;
      await pin(id, 2, 46, 'chatterbox2-colombiana');
      await pin(id, 2, 45, 'chatterbox2-colombiana');
      await pin(id, 3, 0, 'qwen3-esposa');

      await exportLibraryBooks(out, formatTag: 'f96');

      final voices = (await inventory())['books']['hashV']['voices']
          as Map<String, dynamic>;
      expect(voices['chatterbox2-colombiana']['2'], [45, 46]);
      expect(voices['qwen3-esposa']['3'], [0]);
    });

    test('a row whose file is gone is not claimed as downloaded', () async {
      await addBook('Libro', [1], hash: 'h1');
      final id = (await LibraryRepo().all()).single['id'] as int;
      await pin(id, 0, 0, 'chatterbox2-colombiana', file: false);

      await exportLibraryBooks(out, formatTag: 'f96');

      expect((await inventory())['books'], isEmpty);
    });

    test('another cache format is not listed: the Mac would skip audio the '
        'reader cannot find', () async {
      await addBook('Libro', [1], hash: 'h1');
      final id = (await LibraryRepo().all()).single['id'] as int;
      await pin(id, 0, 0, 'chatterbox2-colombiana', fmt: 'f80');

      await exportLibraryBooks(out, formatTag: 'f96');

      expect((await inventory())['books'], isEmpty);
    });

    test('audio of a book no longer in the library is left out', () async {
      await addBook('Libro', [1], hash: 'h1');
      await pin(999, 0, 0, 'chatterbox2-colombiana');

      await exportLibraryBooks(out, formatTag: 'f96');

      expect((await inventory())['books'], isEmpty);
    });

    test('without a format tag no inventory is written', () async {
      await addBook('Libro', [1], hash: 'h1');

      await exportLibraryBooks(out);

      expect(File('${out.path}/inventario.json').existsSync(), isFalse);
    });
  });
}
