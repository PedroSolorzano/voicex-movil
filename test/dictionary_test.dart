import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/services/dictionary.dart';

/// Real extract from es.wiktionary for "bosque", trimmed. The parser is
/// heuristic over prose, so it is worth pinning against actual output.
const _bosque = '''
Español
Etimología
Del provenzal antiguo bosc, y este del latín tardío boscus.
Sustantivo masculino
bosque ¦ plural: bosques
1
Terreno cubierto por árboles y otra vegetación.
2
Por extensión, cuestión o asunto confuso y complejo.
3
Pilosidad que en los varones adultos crece en el pecho.
Ámbito: España.
Uso: jergal.
Sinónimo: barba.
Locuciones
no dejar los árboles ver el bosque: carecer de visión global.
Véase también
selva
''';

const _conOtroIdioma = '''
Español
Sustantivo femenino
1
Edificación destinada a vivienda.
Inglés
Sustantivo
1
A dwelling for people.
''';

void main() {
  group('parseSpanishExtract', () {
    test('extrae las acepciones numeradas', () {
      final entry = DictionaryService.parseSpanishExtract('bosque', _bosque);

      expect(entry.definitions.length, 3);
      expect(entry.definitions.first.meaning,
          'Terreno cubierto por árboles y otra vegetación.');
      expect(entry.definitions.last.meaning,
          'Pilosidad que en los varones adultos crece en el pecho.');
    });

    test('asocia la categoría gramatical', () {
      final entry = DictionaryService.parseSpanishExtract('bosque', _bosque);
      expect(entry.definitions.first.partOfSpeech, 'Sustantivo masculino');
    });

    test('descarta etimología, ámbito, uso y sinónimos', () {
      final entry = DictionaryService.parseSpanishExtract('bosque', _bosque);
      final texts = entry.definitions.map((d) => d.meaning).join(' ');

      expect(texts, isNot(contains('provenzal')));
      expect(texts, isNot(contains('Ámbito')));
      expect(texts, isNot(contains('jergal')));
      expect(texts, isNot(contains('barba')));
    });

    test('se detiene al llegar a otro idioma', () {
      // La misma grafía existe en varios idiomas; mezclarlos daría
      // definiciones en inglés dentro del diccionario español.
      final entry =
          DictionaryService.parseSpanishExtract('casa', _conOtroIdioma);

      expect(entry.definitions.length, 1);
      expect(entry.definitions.single.meaning,
          'Edificación destinada a vivienda.');
    });

    test('informa cuando no hay nada aprovechable', () {
      final entry = DictionaryService.parseSpanishExtract('xyz', 'Español\n');
      expect(entry.definitions, isEmpty);
      expect(entry.error, isNotNull);
    });

    test('no revienta con un extracto vacío', () {
      final entry = DictionaryService.parseSpanishExtract('xyz', '');
      expect(entry.definitions, isEmpty);
    });
  });
}
