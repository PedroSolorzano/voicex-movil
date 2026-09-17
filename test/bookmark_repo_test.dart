import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicex_movil/storage/database.dart';
import 'package:voicex_movil/storage/repositories.dart';

/// La columna `note` existía desde el primer esquema y `add` la aceptaba, pero
/// ningún llamador la rellenaba nunca: media función muerta. Esto fija la otra
/// mitad, que es poder escribirla después de guardar el marcador.
void main() {
  late BookmarkRepo repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await useDatabaseAt(inMemoryDatabasePath);
    final db = await getDatabase();
    await db.delete('bookmarks');
    await db.delete('books');
    await db.insert('books', {
      'id': 1,
      'title': 'La Odisea',
      'author': 'Homero',
      'file_path': '/tmp/odisea.epub',
      'language': 'es',
    });
    repo = BookmarkRepo();
  });

  test('un marcador nace sin nota', () async {
    await repo.add(1, 2, 30);

    final guardado = (await repo.listForBook(1)).single;

    expect(guardado['note'], isNull);
  });

  test('la nota se escribe después, contra el id que devolvió add', () async {
    // Guardar sigue siendo una sola pulsación; la nota llega si llega.
    final id = await repo.add(1, 2, 30);

    await repo.updateNote(id, '  aquí Ulises miente por primera vez  ');

    final guardado = (await repo.listForBook(1)).single;
    expect(guardado['note'], 'aquí Ulises miente por primera vez');
  });

  test('vaciarla la borra, en vez de dejar una cadena vacía', () async {
    final id = await repo.add(1, 2, 30, note: 'algo');

    await repo.updateNote(id, null);

    expect((await repo.listForBook(1)).single['note'], isNull);
  });

  test('anotar un marcador no toca a los demás', () async {
    final primero = await repo.add(1, 0, 0);
    await repo.add(1, 1, 5);

    await repo.updateNote(primero, 'solo este');

    final notas = (await repo.listForBook(1))
        .map((b) => b['note'] as String?)
        .toList();
    expect(notas.where((n) => n != null).length, 1);
  });
}
