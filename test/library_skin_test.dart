import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicex_movil/config/settings.dart';
import 'package:voicex_movil/ui/widgets/catalog_card.dart';
import 'package:voicex_movil/ui/widgets/classic_card_parts.dart';
import 'package:voicex_movil/ui/widgets/library_skin.dart';

/// WCAG 2.x contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  group('el ajuste de piel', () {
    test('sin nada guardado es la moderna', () async {
      SharedPreferences.setMockInitialValues({});
      expect((await AppSettings.load()).librarySkin, 'modern');
    });

    test('se guarda y se vuelve a leer', () async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings().copyWith(librarySkin: 'catalog').save();
      expect((await AppSettings.load()).librarySkin, 'catalog');
    });

    test('las tres pieles del selector existen en el modelo', () {
      for (final name in librarySkins) {
        expect(LibrarySkin.of(name).name, name);
      }
    });

    test('un valor desconocido vuelve a la moderna', () {
      // Lo que guardaría una versión posterior con una cuarta piel.
      expect(LibrarySkin.of('estanteria').name, 'modern');
      expect(LibrarySkin.of('').name, 'modern');
    });
  });

  test('la piel moderna no toca el tema de la app', () {
    // Elegirla tiene que verse exactamente como la biblioteca antes de que
    // existieran las pieles.
    final app = ThemeData(brightness: Brightness.dark);
    expect(identical(libraryThemeData(LibrarySkin.modern, app), app), isTrue);
  });

  test('la tinta roja de la clásica se lee sobre el pergamino', () {
      // Lleva el estado de lectura: es texto, no adorno.
      expect(contrast(LibrarySkin.rubric, LibrarySkin.classic.paper!),
          greaterThanOrEqualTo(4.5));
  });

  test('las tintas de los sellos de las fichas se leen (WCAG AA)', () {
    // El sello es el único sitio donde la ficha dice si el libro está
    // empezado: es texto, no adorno.
    for (final ink in catalogStampInks) {
      expect(contrast(ink, LibrarySkin.catalog.paper!),
          greaterThanOrEqualTo(4.5));
    }
  });

  for (final skin in [LibrarySkin.catalog, LibrarySkin.classic]) {
    group('piel ${skin.name}', () {
      test('es papel aunque la app esté en modo oscuro', () {
        final theme =
            libraryThemeData(skin, ThemeData(brightness: Brightness.dark));
        expect(theme.brightness, Brightness.light);
        expect(theme.colorScheme.surface, skin.paper);
        // Lo que pinta el fondo de Detalles y del diálogo de eliminar.
        expect(theme.dialogTheme.backgroundColor, skin.paper);
        expect(theme.bottomSheetTheme.modalBackgroundColor, skin.paper);
      });

      test('la tinta se lee sobre el papel (WCAG AA, 4.5:1)', () {
        expect(contrast(skin.ink!, skin.paper!), greaterThanOrEqualTo(4.5));
        expect(contrast(skin.inkMuted!, skin.paper!),
            greaterThanOrEqualTo(4.5));
      });

      test('el texto de la barra se lee sobre la madera', () {
        expect(contrast(LibrarySkin.onWood, skin.frame!),
            greaterThanOrEqualTo(4.5));
        // La veta clara de wood.png (generar_texturas.py, base #5C3A24).
        expect(contrast(LibrarySkin.onWood, const Color(0xFF5C3A24)),
            greaterThanOrEqualTo(4.5));
      });
    });
  }

  test('la línea de catálogo de la Clásica se lee en la mancha más oscura', () {
    // Esa línea va en `accent` a 11.5 px, directamente sobre parchment.png.
    // Lo más oscuro del azulejo es el papel oscurecido un 15 % hacia
    // #B89A6A (0.10 * manchas + 0.05 * grano en generar_texturas.py).
    const darkest = Color(0xFFE8D9B8);
    expect(contrast(LibrarySkin.classic.accent!, LibrarySkin.classic.paper!),
        greaterThanOrEqualTo(4.5));
    expect(contrast(LibrarySkin.classic.accent!, darkest),
        greaterThanOrEqualTo(4.5));
    expect(contrast(LibrarySkin.classic.inkMuted!, darkest),
        greaterThanOrEqualTo(4.5));
  });

  group('metadata de las fichas', () {
    test('el año sale de lo que el EPUB haya puesto en la fecha', () {
      expect(yearOf('1925'), '1925');
      expect(yearOf('2015-03-01'), '2015');
      expect(yearOf('March 1851'), '1851');
      expect(yearOf('s.f.'), isNull);
      expect(yearOf(null), isNull);
    });

    test('la descripción llega sin HTML, y vacía cuenta como ausente', () {
      expect(plainDescription('<p>Un  libro\n<b>bueno</b></p>'),
          'Un libro bueno');
      // Un cambio de párrafo es un espacio, no nada.
      expect(plainDescription('<p>deshabitado.</p><p>Encuentran</p>'),
          'deshabitado. Encuentran');
      expect(plainDescription('Fin<b>.</b>'), 'Fin.');
      // Lo que ya está pegado en la base, de antes de arreglar el parser.
      expect(plainDescription('planeta deshabitado.Encuentran un agujero'),
          'planeta deshabitado. Encuentran un agujero');
      expect(plainDescription('¿lo harías?El 22'), '¿lo harías? El 22');
      expect(plainDescription('dijo.»Luego'), 'dijo.» Luego');
      // Siglas e iniciales no son fin de frase.
      expect(plainDescription('J.R.R. Tolkien en EE.UU.'),
          'J.R.R. Tolkien en EE.UU.');
      expect(plainDescription('<p> </p>'), isNull);
      expect(plainDescription(null), isNull);
    });

    test('el pie de la clásica dice idioma y año', () {
      final book = {'language': 'es', 'published_date': '1984-01-01'};
      expect(classicImprint(book), 'ES  ·  1984');
      // Sin fecha no queda un separador colgando.
      expect(classicImprint({'language': 'en'}), 'EN');
    });

    test('el estado de la clásica: sin empezar, en lectura, leído', () {
      const book = <String, dynamic>{};
      expect(classicStatus(book, 0), 'Sin empezar');
      expect(classicStatus(book, 0.223), 'En lectura · 22 %');
      expect(classicStatus(book, 1), 'Leído');
      // Terminado manda sobre la posición: releer no lo "des-termina".
      expect(classicStatus({'finished_at': '2026-09-18'}, 0.1), 'Leído');
    });
  });
}
