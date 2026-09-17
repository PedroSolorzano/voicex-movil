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

  group('huella del contenido', () {
    // La restricción UNIQUE de file_path nunca podía saltar: cada importación
    // copia el EPUB con un UUID nuevo, así que dos copias del mismo libro
    // tenían rutas distintas y entraban las dos.
    late LibraryRepo libros;

    setUp(() => libros = LibraryRepo());

    test('encuentra un libro ya importado por su huella', () async {
      await libros.add(
        title: 'La Odisea',
        author: 'Homero',
        language: 'es',
        filePath: '/tmp/copia-1.epub',
        contentHash: 'abc123',
      );

      final encontrado = await libros.findByContentHash('abc123');

      expect(encontrado?['title'], 'La Odisea');
    });

    test('una huella distinta no coincide', () async {
      await libros.add(
        title: 'La Odisea',
        author: 'Homero',
        language: 'es',
        filePath: '/tmp/copia-1.epub',
        contentHash: 'abc123',
      );

      expect(await libros.findByContentHash('otra'), isNull);
    });

    test('los libros de antes de la columna no coinciden con nada', () async {
      // Quedan con NULL y no se rellenan: hacerlo exigiría leer entero cada
      // libro ya importado al arrancar. Tratar "no sé" como "igual" habría
      // impedido importar cualquier cosa después del primero.
      await libros.add(
        title: 'Viejo',
        author: 'Nadie',
        language: 'es',
        filePath: '/tmp/viejo.epub',
      );

      expect(await libros.findByContentHash('lo que sea'), isNull);
    });
  });
}
