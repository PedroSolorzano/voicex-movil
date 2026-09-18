import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/ui/widgets/catalog_card.dart';
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
      testWidgets('muestra título, autor y signatura', (tester) async {
        await pump(tester, skin, build(quijote));
        expect(titulo, findsOneWidget);
        expect(find.textContaining('Miguel de Cervantes', findRichText: true),
            findsOneWidget);
        expect(find.text('ES  ·  1605  ·  Sin empezar'), findsOneWidget);
      });

      testWidgets('sin portada se ve la encuadernación con el título',
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
      expect(find.text('Un hidalgo enloquece leyendo.'), findsOneWidget);
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
