import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:voicex_movil/services/reporter.dart';
import 'package:voicex_movil/storage/database.dart';

/// El reportero envía solo, así que lo que decide qué sale del teléfono es el
/// saneo. Estos tests existen para que ese filtro no se afloje sin que nadie
/// se entere.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await useDatabaseAt(inMemoryDatabasePath);
    final db = await getDatabase();
    await db.delete('reports');
    Reporter.crashReportsEnabled = true;
  });

  group('saneo', () {
    test('una excepción con un párrafo dentro no viaja con el párrafo', () {
      // El caso real: la síntesis falla y el mensaje arrastra el texto que se
      // estaba mandando. Es lectura de alguien, y esto se envía solo.
      const parrafo = 'Y entonces Jack gritó de susto y terror porque la mujer '
          'que yacía en la cama era su madre.';
      final error = HttpException('Kokoro respondió 500 para "$parrafo"',
          uri: Uri.parse('https://servidor/kokoro/dev/captioned_speech'));

      final descrito = Reporter.describe(error);

      expect(descrito, isNot(contains('Jack')));
      expect(descrito, isNot(contains('madre')));
      // Y sí queda lo que sirve para diagnosticar.
      expect(descrito, contains('HttpException'));
      expect(descrito, contains('/kokoro/dev/captioned_speech'));
    });

    test('un error corriente se identifica por su tipo', () {
      expect(Reporter.describe(TimeoutException('lo que sea')),
          'TimeoutException');
      expect(Reporter.describe(const SocketException('detalle')),
          'SocketException');
    });

    test('el truncado es la segunda red, por si algo se cuela', () {
      final largo = 'texto ' * 200;

      final saneado = Reporter.sanitize(largo);

      expect(saneado.length, lessThan(340));
      expect(saneado, endsWith('(recortado)'));
    });

    test('los saltos de línea se aplanan, para que una línea sea un reporte',
        () {
      expect(Reporter.sanitize('uno\n\ndos\t tres'), 'uno dos tres');
    });

    test('un valor ausente no revienta', () {
      expect(Reporter.sanitize(null), '');
    });
  });

  group('cola', () {
    test('un fallo sin servidor accesible queda encolado, no se pierde', () async {
      // Es el caso que justifica la cola entera: los fallos que interesan
      // ocurren justo cuando no se puede enviar nada.
      await Reporter.recordCrash(
          TimeoutException('sondeo'), StackTrace.current);

      final db = await getDatabase();
      final filas = await db.query('reports');

      expect(filas, hasLength(1));
      final cuerpo =
          jsonDecode(filas.single['body'] as String) as Map<String, dynamic>;
      expect(cuerpo['tipo'], 'crash');
      expect(cuerpo['error'], 'TimeoutException');
    });

    test('el reporte de un probador guarda su texto y el contexto', () async {
      await Reporter.recordFeedback(
        tipo: 'mejora',
        texto: 'me gustaría poder subrayar',
        contexto: const {'capitulo': 6, 'motor': 'kokoro'},
      );

      final db = await getDatabase();
      final cuerpo = jsonDecode(
          (await db.query('reports')).single['body'] as String) as Map;

      expect(cuerpo['texto'], 'me gustaría poder subrayar');
      expect(cuerpo['capitulo'], 6);
      expect(cuerpo['motor'], 'kokoro');
      expect(cuerpo['diagnostico'], isA<List<dynamic>>());
    });

    test('la nota de voz viaja como su nombre, nunca la ruta del teléfono',
        () async {
      await Reporter.recordFeedback(
        tipo: 'bug',
        texto: 'no suena el capítulo 3',
        audioPath: '/data/user/0/com.example/cache/un-uuid.m4a',
      );

      final db = await getDatabase();
      final cuerpo = jsonDecode(
          (await db.query('reports')).single['body'] as String) as Map;

      expect(cuerpo['nota'], 'un-uuid.m4a');
    });

    test('la cola tiene tope, para que nada se acumule sin que nadie mire',
        () async {
      for (var i = 0; i < 55; i++) {
        await Reporter.recordCrash(TimeoutException('$i'), null);
      }

      final db = await getDatabase();
      final total = (await db.query('reports')).length;

      expect(total, 50);
    });

    test('apagado, un fallo no se encola siquiera', () async {
      Reporter.crashReportsEnabled = false;

      await Reporter.recordCrash(TimeoutException('x'), null);

      final db = await getDatabase();
      expect((await db.query('reports')), isEmpty);
    });

    test('apagarlo no silencia lo que una persona escribió a propósito',
        () async {
      // Son dos cosas distintas: el interruptor es sobre lo que la app manda
      // sola, no sobre el formulario de "Contar un problema".
      Reporter.crashReportsEnabled = false;

      await Reporter.recordFeedback(tipo: 'mejora', texto: 'una idea');

      final db = await getDatabase();
      expect((await db.query('reports')).length, 1);
    });

    test('un reporte descartado por cola llena no deja la nota de voz tirada',
        () async {
      // El archivo lo escribe la pantalla de reportes y lo borra quien lo
      // sube. Si el reporte nunca se encola, no queda nadie que lo limpie.
      for (var i = 0; i < 50; i++) {
        await Reporter.recordCrash(TimeoutException('$i'), null);
      }
      final nota = File(
          '${Directory.systemTemp.createTempSync('voicex').path}/nota.m4a')
        ..writeAsBytesSync([0, 1, 2]);

      await Reporter.recordFeedback(
          tipo: 'bug', texto: 'no sonaba', audioPath: nota.path);

      expect(nota.existsSync(), isFalse);
    });
  });
}
