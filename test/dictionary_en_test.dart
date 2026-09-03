import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/services/dictionary.dart';

/// El extracto real de Wikcionario para `waterbag`, la palabra con la que se
/// reportó el fallo. dictionaryapi.dev devolvía 522 tras 19,6 s buscándola;
/// Wikcionario la sirve en medio segundo.
const _waterbag = '''

== English ==


=== Alternative forms ===
water-bag, water bag


=== Etymology ===
From water +‎ bag.


=== Noun ===
waterbag (plural waterbags)

A bag for carrying water.

(historical) The bag-like compartment in a camel's hump in which the animal was once believed to store water; in fact it is fatty tissue.
Coordinate term: water cell''';

/// Recorte de `house`: dos categorías en inglés, y después el mismo término en
/// otros idiomas, donde casi todo habla de música house.
const _house = '''

== English ==

=== Etymology 1 ===
From Middle English hous, hus, from Old English hūs.

==== Pronunciation ====
(Received Pronunciation, General American) IPA(key): /haʊs/, [haʊs]

==== Noun ====
house (countable and uncountable, plural houses)

A structure built or serving as an abode of human beings.
A container; a thing which houses another.

==== Verb ====
house (third-person singular simple present houses)

(transitive) To keep within a structure or container.
(transitive) To admit to residence; to harbor.

== Dutch ==

=== Noun ===
house m (uncountable, no diminutive)

house music, house (a genre of music)
Synonym: housemuziek''';

void main() {
  group('parseEnglishExtract', () {
    test('saca las acepciones de la palabra que destapó el fallo', () {
      final entry = DictionaryService.parseEnglishExtract('waterbag', _waterbag);

      expect(entry.error, isNull);
      expect(entry.definitions, hasLength(2));
      expect(entry.definitions.first.meaning, 'A bag for carrying water.');
      expect(entry.definitions.first.partOfSpeech, 'Noun');
    });

    test('descarta la línea del lema con sus flexiones', () {
      // "waterbag (plural waterbags)" va justo debajo de la categoría y no es
      // una acepción; sin esta regla saldría como la primera definición.
      final entry = DictionaryService.parseEnglishExtract('waterbag', _waterbag);

      expect(entry.definitions.map((d) => d.meaning),
          isNot(contains(contains('plural waterbags'))));
    });

    test('descarta las referencias cruzadas', () {
      // "Coordinate term: water cell" se lee como una definición y no lo es.
      final entry = DictionaryService.parseEnglishExtract('waterbag', _waterbag);

      expect(entry.definitions.map((d) => d.meaning),
          isNot(contains(startsWith('Coordinate term'))));
    });

    test('se detiene al llegar a otro idioma', () {
      // La misma grafía existe en una docena de idiomas. Para "house", casi
      // todas esas secciones hablan de música house.
      final entry = DictionaryService.parseEnglishExtract('house', _house);

      expect(entry.definitions.map((d) => d.meaning).join(' '),
          isNot(contains('genre of music')));
    });

    test('distingue las categorías dentro del inglés', () {
      final entry = DictionaryService.parseEnglishExtract('house', _house);
      final categorias = entry.definitions.map((d) => d.partOfSpeech).toSet();

      expect(categorias, {'Noun', 'Verb'});
      expect(entry.definitions, hasLength(4));
    });

    test('ignora etimología y pronunciación, y guarda la fonética', () {
      final entry = DictionaryService.parseEnglishExtract('house', _house);

      expect(entry.definitions.map((d) => d.meaning).join(' '),
          isNot(contains('Middle English')));
      expect(entry.phonetic, '/haʊs/');
    });

    test('un extracto vacío informa en vez de reventar', () {
      final entry = DictionaryService.parseEnglishExtract('xyzzy', '');

      expect(entry.definitions, isEmpty);
      expect(entry.error, isNotNull);
    });

    test('una palabra que solo existe en otro idioma no devuelve nada', () {
      const soloDanes = '''
== Danish ==

=== Noun ===
hus n

house, building''';

      final entry = DictionaryService.parseEnglishExtract('hus', soloDanes);

      expect(entry.definitions, isEmpty);
    });
  });
}
