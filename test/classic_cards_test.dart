import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/ui/widgets/catalog_card.dart';
import 'package:voicex_movil/ui/widgets/classic_card_parts.dart';
import 'package:voicex_movil/ui/widgets/classic_shelf_card.dart';
import 'package:voicex_movil/ui/widgets/library_skin.dart';

/// Lo que cada piel tiene que hacer igual que la moderna: mostrar los datos del
/// libro, abrirlo al tocar y ofrecer las mismas tres acciones. Cambia el
/// dibujo, no lo que se puede hacer.
void main() {
  const quijote = {
    'id': 1,
    'title': 'Don Quijote de la Mancha',
    'author': 'Miguel de Cervantes',
    'language': 'es',
    'published_date': '1605',
    'publisher': 'Juan de la Cuesta',
    'description': '<p>Un hidalgo <i>enloquece</i> leyendo.</p>',
  };

  // Un título largo de verdad: los hay, y en la ficha no puede desbordar.
  final larguisimo = {
    ...quijote,
    'title': 'El ingenioso hidalgo don Quijote de la Mancha, compuesto por '
        'Miguel de Cervantes Saavedra, dirigido al Duque de Béjar, marqués',
  };

  // El título sale dos veces si no hay portada: en el texto y en el lomo de la
  // encuadernación. Este es el del texto.
  final titulo = find.byWidgetPredicate((w) =>
      w is Text && w.data == 'Don Quijote de la Mancha' && w.maxLines == 2);

  // La descripción con capitular son tres Text; lo que la hace una sola cosa
  // para un lector de pantalla es la etiqueta de su Semantics.
  Finder etiquetado(String label) => find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == label);

  Future<void> pump(WidgetTester tester, LibrarySkin skin, Widget card) =>
      tester.pumpWidget(MaterialApp(
        theme: libraryThemeData(skin, ThemeData()),
        home: Scaffold(body: ListView(children: [card])),
      ));

  final cases = <String, (LibrarySkin, Widget Function(Map<String, dynamic>,
      {VoidCallback? onRead, ValueChanged<String>? onLang}))>{
    'Fichas': (
      LibrarySkin.catalog,
      (book, {onRead, onLang}) => CatalogCard(
            book: book,
            progress: 0,
            onRead: onRead ?? () {},
            onDelete: () {},
            onInfo: () {},
            onLanguageToggle: onLang ?? (_) {},
          ),
    ),
    'Clásica': (
      LibrarySkin.classic,
      (book, {onRead, onLang}) => ClassicShelfCard(
            book: book,
            progress: 0,
            onRead: onRead ?? () {},
            onDelete: () {},
            onInfo: () {},
            onLanguageToggle: onLang ?? (_) {},
          ),
    ),
  };

  for (final MapEntry(key: name, value: (skin, build)) in cases.entries) {
    group(name, () {
      testWidgets('muestra título y autor', (tester) async {
        await pump(tester, skin, build(quijote));
        expect(titulo, findsOneWidget);
        expect(find.textContaining('Miguel de Cervantes', findRichText: true),
            findsOneWidget);
      });

      testWidgets('sin portada, el título va también donde iría la portada',
          (tester) async {
        await pump(tester, skin, build(quijote));
        // El título aparece dos veces: en el texto y en el lomo.
        expect(find.textContaining('Don Quijote'), findsNWidgets(2));
      });

      testWidgets('un título larguísimo no desborda', (tester) async {
        await pump(tester, skin, build(larguisimo));
        expect(tester.takeException(), isNull);
      });

      testWidgets('tocar la ficha abre el libro', (tester) async {
        var abierto = false;
        await pump(tester, skin, build(quijote, onRead: () => abierto = true));
        await tester.tap(titulo);
        expect(abierto, isTrue);
      });

      testWidgets('el menú ofrece las tres acciones y cambia el idioma',
          (tester) async {
        String? idioma;
        await pump(tester, skin, build(quijote, onLang: (l) => idioma = l));
        await tester.tap(find.byTooltip('Más'));
        await tester.pumpAndSettle();
        expect(find.text('Detalles'), findsOneWidget);
        expect(find.text('Eliminar'), findsOneWidget);
        await tester.tap(find.text('Cambiar idioma a EN'));
        await tester.pumpAndSettle();
        expect(idioma, 'en');
      });
    });
  }

  group('Fichas', () {
    CatalogCard ficha(Map<String, dynamic> book, double progress) =>
        CatalogCard(
          book: book,
          progress: progress,
          onRead: () {},
          onDelete: () {},
          onInfo: () {},
          onLanguageToggle: (_) {},
        );

    testWidgets('signatura en la esquina, pie de imprenta y sello',
        (tester) async {
      await pump(tester, LibrarySkin.catalog, ficha(quijote, 0));
      // "Don Quijote…" no lleva artículo: se archiva por DON.
      expect(find.text('ES\nDON\n1605'), findsOneWidget);
      expect(find.text('Juan de la Cuesta, 1605.'), findsOneWidget);
      expect(find.text('SIN EMPEZAR'), findsOneWidget);
    });

    testWidgets('el sello dice por dónde va y cuándo se terminó',
        (tester) async {
      await pump(tester, LibrarySkin.catalog, ficha(quijote, 0.237));
      expect(find.text('EN LECTURA · 24 %'), findsOneWidget);

      await pump(tester, LibrarySkin.catalog,
          ficha({...quijote, 'finished_at': '2026-09-18T10:00:00'}, 0.4));
      expect(find.text('LEÍDO'), findsOneWidget);
    });

    testWidgets('sin editorial no se escribe el año suelto', (tester) async {
      // El año ya está en la signatura; y hay EPUB que traen un año como
      // editorial, que daba "2021, 2021.".
      for (final publisher in [null, '', '2021']) {
        await pump(tester, LibrarySkin.catalog,
            ficha({...quijote, 'publisher': publisher}, 0));
        expect(find.textContaining('1605.'), findsNothing);
        expect(find.textContaining('2021'), findsNothing);
      }
    });
  });

  group('la signatura', () {
    test('idioma, marca de título y año', () {
      expect(callNumber({'title': 'El talismán', 'published_date': '1984'}),
          ['ES', 'TAL', '1984']);
      expect(callNumber({'title': 'The Martian', 'language': 'en'}),
          ['EN', 'MAR']);
    });

    test('un título que es solo el artículo no se queda sin marca', () {
      expect(callNumber({'title': 'Él'}), ['ES', 'ÉL']);
      expect(callNumber({'title': 'La'}), ['ES', 'LA']);
    });

    test('cifras y signos', () {
      expect(callNumber({'title': '22/11/63'}), ['ES', '221']);
      expect(callNumber({'title': '¿…?'}), ['ES']);
      expect(callNumber({}), ['ES']);
    });
  });

  group('Clásica', () {
    testWidgets('muestra editorial y descripción sin HTML', (tester) async {
      await pump(tester, LibrarySkin.classic, ClassicShelfCard(
        book: quijote,
        progress: 0,
        onRead: () {},
        onDelete: () {},
        onInfo: () {},
        onLanguageToggle: (_) {},
      ));
      expect(find.text('Juan de la Cuesta'), findsOneWidget);
      // La capitular va aparte; para un lector de pantalla es un solo texto.
      expect(find.text('U'), findsOneWidget);
      expect(find.text('n hidalgo enloquece leyendo.'), findsOneWidget);
      expect(etiquetado('Un hidalgo enloquece leyendo.'), findsOneWidget);
      expect(
          find.textContaining('ES  ·  1605', findRichText: true), findsOneWidget);
      expect(find.textContaining('☞ Sin empezar', findRichText: true),
          findsOneWidget);
    });

    ClassicShelfCard lote(Map<String, dynamic> book,
            {double progress = 0, int? number}) =>
        ClassicShelfCard(
          book: book,
          progress: progress,
          number: number,
          onRead: () {},
          onDelete: () {},
          onInfo: () {},
          onLanguageToggle: (_) {},
        );

    testWidgets('los lotes van numerados en romanos', (tester) async {
      await pump(tester, LibrarySkin.classic, lote(quijote, number: 14));
      expect(find.text('N.º XIV'), findsOneWidget);
    });

    testWidgets('el libro en lectura lo dice en rojo y lleva la cinta',
        (tester) async {
      await pump(tester, LibrarySkin.classic, lote(quijote, progress: 0.237));
      expect(find.textContaining('En lectura · 24 %', findRichText: true),
          findsOneWidget);
      expect(tester.widget<FramedCover>(find.byType(FramedCover)).ribbon,
          isTrue);

      await pump(tester, LibrarySkin.classic, lote(quijote));
      expect(tester.widget<FramedCover>(find.byType(FramedCover)).ribbon,
          isFalse);
    });

    testWidgets('una descripción larga se parte sin perder ni repetir nada',
        (tester) async {
      const largo = 'En un lugar de la Mancha, de cuyo nombre no quiero '
          'acordarme, no ha mucho tiempo que vivía un hidalgo de los de lanza '
          'en astillero, adarga antigua, rocín flaco y galgo corredor. Una '
          'olla de algo más vaca que carnero, salpicón las más noches.';
      await pump(tester, LibrarySkin.classic,
          lote({...quijote, 'description': largo}));
      expect(tester.takeException(), isNull);
      // Inicial + lo que va a su lado + lo que sigue debajo. El de al lado
      // lleva el texto entero y se recorta, así que lo de debajo tiene que
      // ser una cola suya que empiece en palabra entera.
      final textos = tester
          .widgetList<Text>(find.descendant(
              of: etiquetado(largo), matching: find.byType(Text)))
          .map((t) => t.data!)
          .toList();
      expect(textos, hasLength(3));
      expect(textos[0], 'E');
      expect(textos[1], largo.substring(1));
      expect(largo.endsWith(textos[2]), isTrue);
      final corte = largo.length - textos[2].length;
      expect(largo[corte - 1], ' ');

      // Y el corte cae donde acaba la segunda línea *dibujada*, no donde la
      // calculó una medición aparte: medir sin el estilo por defecto del tema
      // se comía una palabra ("Aquel día el [mundo] cambió").
      final alLado = tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byWidgetPredicate(
              (w) => w is Text && w.data == largo.substring(1)),
          matching: find.byType(RichText)));
      final finDeLinea = alLado
          .getPositionForOffset(
              Offset(alLado.size.width, alLado.size.height - 2))
          .offset;
      expect(largo.substring(1).substring(finDeLinea).trimLeft(), textos[2]);
    });

    testWidgets('una descripción que no empieza por letra va sin capitular',
        (tester) async {
      await pump(tester, LibrarySkin.classic,
          lote({...quijote, 'description': '—¿Quién anda ahí?'}));
      expect(find.text('—¿Quién anda ahí?'), findsOneWidget);
    });

    testWidgets('sin descripción no reserva el hueco', (tester) async {
      await pump(tester, LibrarySkin.classic, ClassicShelfCard(
        book: {...quijote, 'description': null, 'publisher': null},
        progress: 0,
        onRead: () {},
        onDelete: () {},
        onInfo: () {},
        onLanguageToggle: (_) {},
      ));
      expect(find.textContaining('hidalgo'), findsNothing);
      expect(find.text('Juan de la Cuesta'), findsNothing);
    });
  });
}
