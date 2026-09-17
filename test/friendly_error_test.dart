import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/errors.dart';

/// Lo que ve alguien cuando algo falla. Antes era el objeto de Dart en crudo
/// -`FormatException: Could not find end of central directory`-, que nombra la
/// avería para quien mantiene la librería y no dice nada a quien lee.
void main() {
  group('friendlyError', () {
    test('un mensaje ya escrito para el lector pasa intacto', () {
      const error = ReadableError('El archivo es demasiado grande.');

      expect(friendlyError(error), 'El archivo es demasiado grande.');
    });

    test('un EPUB corrupto se explica como archivo, no como excepción', () {
      final mensaje = friendlyError(
          const FormatException('Could not find end of central directory'));

      expect(mensaje, contains('no parece un EPUB'));
      expect(mensaje, isNot(contains('central directory')));
    });

    test('quedarse sin red no se confunde con un archivo roto', () {
      expect(friendlyError(TimeoutException('x')), contains('conexión'));
      expect(
          friendlyError(const SocketException('x')), contains('conexión'));
    });

    test('un archivo que ya no está dice que se movió o se borró', () {
      final mensaje = friendlyError(
          const PathNotFoundException('/ruta/libro.epub', OSError()));

      expect(mensaje, contains('movido'));
    });

    test('lo desconocido no se calla: dice dónde contarlo', () {
      final mensaje = friendlyError(StateError('algo raro'));

      expect(mensaje, contains('Contar un problema'));
      expect(mensaje, isNot(contains('algo raro')));
    });
  });
}
