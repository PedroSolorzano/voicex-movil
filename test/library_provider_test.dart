import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicex_movil/storage/database.dart';
import 'package:voicex_movil/ui/providers/library_provider.dart';

/// `getApplicationDocumentsDirectory`/`getTemporaryDirectory` no tienen
/// implementación de plataforma bajo `flutter test`; todo lo que
/// `LibraryNotifier` copia a "almacenamiento de la app" va aquí en su lugar.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String root;
  _FakePathProvider(this.root);

  @override
  Future<String?> getApplicationDocumentsPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// La primera pantalla que ve un tester nunca debe estar vacía: estos tests
/// existen para que la siembra de los dos libros de muestra no se rompa en
/// silencio, y para que borrar uno no lo resucite en el próximo arranque.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await useDatabaseAt(inMemoryDatabasePath);
    final db = await getDatabase();
    await db.delete('books');
    SharedPreferences.setMockInitialValues({});

    final tmp = await Directory.systemTemp.createTemp('voicex_test_');
    addTearDown(() => tmp.delete(recursive: true));
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  test('una biblioteca vacía se siembra con los dos libros de muestra',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final books = await container.read(libraryProvider.future);

    expect(books, hasLength(2));
    expect(books.map((b) => b['language']), containsAll(['es', 'en']));
  });

  test('una biblioteca con libros no se siembra', () async {
    final db = await getDatabase();
    await db.insert('books', {
      'title': 'Ya hay algo',
      'author': 'Quien sea',
      'language': 'es',
      'file_path': '/no/existe.epub',
    });

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final books = await container.read(libraryProvider.future);

    expect(books, hasLength(1));
    expect(books.single['title'], 'Ya hay algo');
  });

  test('borrar los libros de muestra no los vuelve a sembrar', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final seeded = await container.read(libraryProvider.future);
    for (final book in seeded) {
      await container
          .read(libraryProvider.notifier)
          .deleteBook(book['id'] as int);
    }

    // Un contenedor nuevo simula el siguiente arranque de la app; la marca
    // de sembrado vive en SharedPreferences, no en el contenedor.
    final second = ProviderContainer();
    addTearDown(second.dispose);
    final books = await second.read(libraryProvider.future);

    expect(books, isEmpty);
  });
}
