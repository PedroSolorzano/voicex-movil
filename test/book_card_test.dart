import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/ui/widgets/book_card.dart';

/// La tarjeta de la piel moderna: mismos datos y acciones que siempre, con el
/// estado a la vista y los colores sacados de la portada.
void main() {
  const libro = {
    'id': 1,
    'title': 'El talismán',
    'author': 'Stephen King, Peter Straub',
    'language': 'es',
  };

  Future<void> pump(
    WidgetTester tester,
    Map<String, dynamic> book, {
    double progress = 0,
    VoidCallback? onRead,
    VoidCallback? onInfo,
    VoidCallback? onDelete,
    ValueChanged<String>? onLang,
    Brightness brightness = Brightness.dark,
  }) =>
      tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.deepPurple, brightness: brightness)),
        home: Scaffold(
          body: ListView(children: [
            BookCard(
              book: book,
              progress: progress,
              onRead: onRead ?? () {},
              onInfo: onInfo ?? () {},
              onDelete: onDelete ?? () {},
              onLanguageToggle: onLang ?? (_) {},
            ),
          ]),
        ),
      ));

  test('el estado: nuevo, porcentaje, leído', () {
    expect(BookCard.statusOf(libro, 0), 'NUEVO');
    expect(BookCard.statusOf(libro, 0.237), '24 %');
    expect(BookCard.statusOf(libro, 1), 'LEÍDO');
    // Terminado manda sobre la posición: releer no lo "des-termina".
    expect(BookCard.statusOf({...libro, 'finished_at': '2026-09-18'}, 0.1),
        'LEÍDO');
  });

  testWidgets('muestra título, autor y estado', (tester) async {
    await pump(tester, libro);
    expect(find.text('El talismán'), findsOneWidget);
    expect(find.text('Stephen King, Peter Straub'), findsOneWidget);
    expect(find.text('NUEVO'), findsOneWidget);
    // Sin empezar no hay barra que enseñar.
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('en lectura: porcentaje y barra; leído: sin barra',
      (tester) async {
    await pump(tester, libro, progress: 0.237);
    expect(find.text('24 %'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        closeTo(0.237, 1e-9));

    await pump(tester, {...libro, 'finished_at': '2026-09-18'}, progress: 1);
    expect(find.text('LEÍDO'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('tocar la tarjeta o el botón abre el libro', (tester) async {
    var abierto = 0;
    await pump(tester, libro, onRead: () => abierto++);
    await tester.tap(find.text('El talismán'));
    await tester.tap(find.byTooltip('Empezar a leer'));
    expect(abierto, 2);

    await pump(tester, libro, progress: 0.2);
    expect(find.byTooltip('Continuar'), findsOneWidget);
  });

  testWidgets('detalles y eliminar están en el menú', (tester) async {
    var info = false, borrado = false;
    await pump(tester, libro,
        onInfo: () => info = true, onDelete: () => borrado = true);

    await tester.tap(find.byTooltip('Más'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detalles'));
    await tester.pumpAndSettle();
    expect(info, isTrue);

    await tester.tap(find.byTooltip('Más'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar'));
    await tester.pumpAndSettle();
    expect(borrado, isTrue);
  });

  testWidgets('el idioma se cambia con un toque, sin abrir el libro',
      (tester) async {
    String? idioma;
    var abierto = false;
    await pump(tester, libro,
        onLang: (l) => idioma = l, onRead: () => abierto = true);
    await tester.tap(find.text('ES'));
    expect(idioma, 'en');
    expect(abierto, isFalse);
  });

  testWidgets('un título larguísimo no desborda', (tester) async {
    await pump(tester, {
      ...libro,
      'title': 'El ingenioso hidalgo don Quijote de la Mancha, compuesto por '
          'Miguel de Cervantes Saavedra, dirigido al Duque de Béjar, marqués',
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets('una portada que no existe deja los colores de la app',
      (tester) async {
    await pump(tester, {...libro, 'cover_path': '/no/existe.jpg'});
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('El talismán'), findsOneWidget);
  });

  testWidgets('la tarjeta toma el color de su portada', (tester) async {
    // Una portada de verdad, roja entera, escrita a disco.
    late File cover;
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 60, 90),
          Paint()..color = const Color(0xFFD32F2F));
      final image = await recorder.endRecording().toImage(60, 90);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await Directory.systemTemp.createTemp('voicex_cover');
      cover = File('${dir.path}/roja.png');
      await cover.writeAsBytes(png!.buffer.asUint8List());
    });
    addTearDown(() => cover.parent.deleteSync(recursive: true));

    Color playColor() => tester
        .widget<IconButton>(find.widgetWithIcon(
            IconButton, Icons.play_arrow_rounded))
        .style!
        .backgroundColor!
        .resolve({})!;

    await pump(tester, libro);
    final deLaApp = playColor();

    await pump(tester, {...libro, 'cover_path': cover.path});
    // La extracción decodifica la imagen: trabajo real, fuera del reloj falso.
    for (var i = 0; i < 20 && playColor() == deLaApp; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final delLibro = playColor();
    expect(delLibro, isNot(deLaApp));
    // Rojo de portada, botón rojizo: domina el canal rojo.
    expect(delLibro.r, greaterThan(delLibro.b));
    expect(delLibro.r, greaterThan(delLibro.g));
  });
}
