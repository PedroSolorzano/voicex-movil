import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

  // A real book (Blindsight, from a public EPUB site) was refused with "the
  // file doesn't look like an EPUB". Its prose is valid UTF-8; what broke the
  // import was a Latin-1 "ñ" in a CSS comment, which epubx decodes strictly.
  group('an EPUB with a text file that is not valid UTF-8', () {
    // `/* Añadido por el editor */` with the ñ as the single Latin-1 byte 0xF1.
    final latin1Css = Uint8List.fromList([
      ...ascii.encode('p { margin: 0 }\n/* A'),
      0xF1,
      ...ascii.encode('adido por el editor */\n'),
    ]);

    late File archivo;

    setUp(() {
      archivo = File(
          '${Directory.systemTemp.createTempSync('voicex').path}/libro.epub')
        ..writeAsBytesSync(_buildEpub(css: latin1Css));
    });

    test('imports, because the stylesheet is not part of the book', () async {
      final book = await parseEpub(archivo.path);

      expect(book.title, 'Libro de prueba');
      expect(book.chapters, isNotEmpty);
    });

    test('keeps the prose untouched', () async {
      final book = await parseEpub(archivo.path);
      final text = book.chapters
          .expand((c) => c.paragraphs)
          .map((p) => p.rawText)
          .join(' ');

      expect(text, contains('El niño miró la montaña'));
      expect(text, isNot(contains('�')));
    });

    test('the cover and metadata pass reads it too', () async {
      final extras = await extractEpubExtras(archivo.path);

      expect(extras, isNotNull);
    });

    test('a file that is not a ZIP is still reported as a FormatException',
        () async {
      final basura = File(
          '${Directory.systemTemp.createTempSync('voicex').path}/basura.epub')
        ..writeAsBytesSync(List.filled(2048, 7));

      await expectLater(
          parseEpub(basura.path), throwsA(isA<FormatException>()));
    });
  });

  group('utf8WithLatin1Fallback', () {
    test('turns a stray Latin-1 byte into its UTF-8 character', () {
      final out = utf8WithLatin1Fallback(Uint8List.fromList([0x41, 0xF1, 0x61]));

      expect(utf8.decode(out), 'Aña');
    });

    test('leaves valid UTF-8 byte for byte as it was', () {
      final entrada = Uint8List.fromList(utf8.encode('canción ñandú — “hola”'));

      expect(utf8WithLatin1Fallback(entrada), entrada);
    });

    test('reads the 0x80-0x9F range as Windows-1252, not as control codes', () {
      // 0x93 / 0x94 are the curly quotes in a Windows-1252 file.
      final out = utf8WithLatin1Fallback(Uint8List.fromList([0x93, 0x68, 0x94]));

      expect(utf8.decode(out), '“h”');
    });

    test('does not swallow a valid sequence that follows a bad byte', () {
      final entrada = Uint8List.fromList([0xF1, ...utf8.encode('ñ')]);

      expect(utf8.decode(utf8WithLatin1Fallback(entrada)), 'ññ');
    });

    test('a truncated multi-byte sequence at the end does not throw', () {
      final out = utf8WithLatin1Fallback(Uint8List.fromList([0x61, 0xC3]));

      expect(() => utf8.decode(out), returnsNormally);
    });
  });
}

/// A minimal EPUB 2 in memory. [css] goes in as raw bytes so a test can put a
/// byte in it that no UTF-8 string could hold.
Uint8List _buildEpub({required Uint8List css}) {
  const container = '<?xml version="1.0"?>\n'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
      '<rootfiles><rootfile full-path="OPS/content.opf" '
      'media-type="application/oebps-package+xml"/></rootfiles></container>';
  const opf = '<?xml version="1.0" encoding="utf-8"?>\n'
      '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" '
      'unique-identifier="id"><metadata '
      'xmlns:dc="http://purl.org/dc/elements/1.1/">'
      '<dc:title>Libro de prueba</dc:title>'
      '<dc:creator>Autora de prueba</dc:creator>'
      '<dc:language>es</dc:language>'
      '<dc:identifier id="id">urn:test:1</dc:identifier></metadata>'
      '<manifest>'
      '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
      '<item id="c1" href="c1.xhtml" media-type="application/xhtml+xml"/>'
      '<item id="css" href="style.css" media-type="text/css"/>'
      '</manifest><spine toc="ncx"><itemref idref="c1"/></spine></package>';
  const ncx = '<?xml version="1.0" encoding="utf-8"?>\n'
      '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
      '<head/><docTitle><text>Libro de prueba</text></docTitle><navMap>'
      '<navPoint id="n1" playOrder="1"><navLabel><text>Capítulo 1</text>'
      '</navLabel><content src="c1.xhtml"/></navPoint></navMap></ncx>';
  const capitulo = '<?xml version="1.0" encoding="utf-8"?>\n'
      '<html xmlns="http://www.w3.org/1999/xhtml"><head><title>c1</title>'
      '<link rel="stylesheet" type="text/css" href="style.css"/></head><body>'
      '<h1>Capítulo 1</h1>'
      '<p>El niño miró la montaña y dijo que mañana volvería al campo con su '
      'compañero. Después guardó la linterna en la mochila y esperó a que '
      'terminara la lluvia.</p>'
      '<p>Nadie contestó desde la casa, así que cruzó el patio despacio, '
      'contando los escalones hasta la puerta de madera.</p>'
      '</body></html>';

  List<int> utf8Bytes(String s) => utf8.encode(s);
  final archive = Archive()
    ..addFile(ArchiveFile('mimetype', 20, utf8Bytes('application/epub+zip')))
    ..addFile(ArchiveFile('META-INF/container.xml', utf8Bytes(container).length,
        utf8Bytes(container)))
    ..addFile(
        ArchiveFile('OPS/content.opf', utf8Bytes(opf).length, utf8Bytes(opf)))
    ..addFile(
        ArchiveFile('OPS/toc.ncx', utf8Bytes(ncx).length, utf8Bytes(ncx)))
    ..addFile(ArchiveFile(
        'OPS/c1.xhtml', utf8Bytes(capitulo).length, utf8Bytes(capitulo)))
    ..addFile(ArchiveFile('OPS/style.css', css.length, css));
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}
