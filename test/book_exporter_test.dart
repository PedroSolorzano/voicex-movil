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
}
