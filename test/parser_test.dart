import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/epub/parser.dart';
import 'package:voicex_movil/errors.dart';

void main() {
  group('splitSentences', () {
    test('splits on sentence-final punctuation', () {
      final s = splitSentences('Hola mundo. Otro día. Y ya.');
      expect(s.map((e) => e.text).toList(),
          ['Hola mundo.', 'Otro día.', 'Y ya.']);
    });

    test('indexes sentences from zero', () {
      final s = splitSentences('Uno. Dos.');
      expect(s.map((e) => e.index).toList(), [0, 1]);
    });

    test('does not split after common Spanish abbreviations', () {
      final s = splitSentences('Llamó al Sr. Pérez por la mañana.');
      expect(s.length, 1);
    });

    test('does not split on initials', () {
      final s = splitSentences('Leyó a J. R. R. Tolkien anoche.');
      expect(s.length, 1);
    });

    test('does not split when the next word is lowercase', () {
      // Em-dash dialogue attribution keeps the sentence together.
      final s = splitSentences('—No lo sé. dijo en voz baja.');
      expect(s.length, 1);
    });

    test('keeps question and exclamation marks as boundaries', () {
      final s = splitSentences('¿Quién anda ahí? Nadie respondió.');
      expect(s.length, 2);
    });

    test('returns empty for empty input', () {
      expect(splitSentences('   '), isEmpty);
    });

    test('handles text with no terminal punctuation', () {
      final s = splitSentences('Una frase sin punto final');
      expect(s.length, 1);
      expect(s.first.text, 'Una frase sin punto final');
    });
  });

  group('isMeaningfulShortBlock', () {
    test('keeps short dialogue that would otherwise be dropped', () {
      // These are the lines the old 20-char filter silently discarded.
      expect(isMeaningfulShortBlock('—¿Qué?'), isTrue);
      expect(isMeaningfulShortBlock('—No lo sé.'), isTrue);
      expect(isMeaningfulShortBlock('«Vale».'), isTrue);
    });

    test('keeps short prose that ends a sentence', () {
      expect(isMeaningfulShortBlock('Se fue.'), isTrue);
      expect(isMeaningfulShortBlock('¡Corre!'), isTrue);
    });

    test('rejects page numbers and ornaments', () {
      expect(isMeaningfulShortBlock('42'), isFalse);
      expect(isMeaningfulShortBlock('* * *'), isFalse);
      expect(isMeaningfulShortBlock('---'), isFalse);
    });

    test('rejects fragments that neither open nor close a sentence', () {
      expect(isMeaningfulShortBlock('capitulo uno'), isFalse);
    });

    test('rejects text below the minimum length', () {
      expect(isMeaningfulShortBlock('a.'), isFalse);
    });
  });

  group('readEpubBytes', () {
    // Cualquier app del teléfono puede mandar un "EPUB" por el intent de
    // compartir, y el archivo se lee entero a memoria antes de descomprimirlo.
    // El tope es lo único que separa un archivo malformado de que el sistema
    // mate la app.
    late File archivo;

    setUp(() {
      archivo = File(
          '${Directory.systemTemp.createTempSync('voicex').path}/libro.epub')
        ..writeAsBytesSync(List.filled(1024, 0));
    });

    test('refuses a file larger than the ceiling', () {
      expect(
        () => readEpubBytes(archivo.path, maxBytes: 100),
        throwsA(isA<ReadableError>()),
      );
    });

    test('the refusal is already written for the reader', () async {
      try {
        await readEpubBytes(archivo.path, maxBytes: 100);
        fail('debería haber lanzado');
      } on ReadableError catch (e) {
        expect(e.message, contains('demasiado grande'));
        // Y llega intacto a la pantalla, sin que friendlyError lo reemplace
        // por el mensaje genérico.
        expect(friendlyError(e), e.message);
      }
    });

    test('a file under the ceiling is read whole', () async {
      final bytes = await readEpubBytes(archivo.path, maxBytes: 4096);

      expect(bytes.length, 1024);
    });
  });
}
