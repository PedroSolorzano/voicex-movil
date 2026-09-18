import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/ui/providers/reader_provider.dart';
import 'package:voicex_movil/ui/widgets/reader_theme.dart';
import 'package:voicex_movil/ui/widgets/reader_transport.dart';

/// La barra de escucha: cada botón de navegación dice qué unidad mueve, y los
/// de capítulo se apagan en los extremos del libro.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    ReaderState reader = const ReaderState(),
    double speed = 1.0,
    bool firstChapter = false,
    bool lastChapter = false,
    VoidCallback? onPreviousChapter,
    VoidCallback? onNextChapter,
    VoidCallback? onPreviousParagraph,
    VoidCallback? onNextParagraph,
    VoidCallback? onPlay,
    VoidCallback? onPause,
    VoidCallback? onResume,
    ValueChanged<double>? onSpeedChanged,
    ValueChanged<Duration?>? onSleepChanged,
  }) =>
      tester.pumpWidget(MaterialApp(
        theme: readerThemeData(ReaderPalette.sepia),
        home: Scaffold(
          body: ReaderTransport(
            reader: reader,
            palette: ReaderPalette.sepia,
            speed: speed,
            onPreviousChapter:
                firstChapter ? null : (onPreviousChapter ?? () {}),
            onNextChapter: lastChapter ? null : (onNextChapter ?? () {}),
            onPreviousParagraph: onPreviousParagraph ?? () {},
            onNextParagraph: onNextParagraph ?? () {},
            onPlay: onPlay ?? () {},
            onPause: onPause ?? () {},
            onResume: onResume ?? () {},
            onSpeedChanged: onSpeedChanged ?? (_) {},
            onSleepChanged: onSleepChanged ?? (_) {},
          ),
        ),
      ));

  testWidgets('cada botón de navegación nombra su unidad', (tester) async {
    await pump(tester);
    expect(find.text('Capítulo'), findsNWidgets(2));
    expect(find.text('Párrafo'), findsNWidgets(2));
    // Velocidad y dormir se describen solos.
    expect(find.text('Velocidad'), findsNothing);
    expect(find.text('1.0×'), findsOneWidget);
    expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
  });

  testWidgets('los cuatro saltos llaman a lo suyo', (tester) async {
    final llamadas = <String>[];
    await pump(
      tester,
      onPreviousChapter: () => llamadas.add('cap-'),
      onPreviousParagraph: () => llamadas.add('par-'),
      onNextParagraph: () => llamadas.add('par+'),
      onNextChapter: () => llamadas.add('cap+'),
    );
    await tester.tap(find.byTooltip('Capítulo anterior'));
    await tester.tap(find.byTooltip('Párrafo anterior'));
    await tester.tap(find.byTooltip('Párrafo siguiente'));
    await tester.tap(find.byTooltip('Capítulo siguiente'));
    expect(llamadas, ['cap-', 'par-', 'par+', 'cap+']);
  });

  testWidgets('en el primer y el último capítulo el salto se apaga',
      (tester) async {
    await pump(tester, firstChapter: true, lastChapter: true);
    InkResponse bajo(String tooltip) => tester.widget<InkResponse>(find
        .descendant(
            of: find.byTooltip(tooltip), matching: find.byType(InkResponse))
        .first);
    expect(bajo('Capítulo anterior').onTap, isNull);
    expect(bajo('Capítulo siguiente').onTap, isNull);
    expect(bajo('Párrafo anterior').onTap, isNotNull);
  });

  testWidgets('play, pausa y reanudar según el estado', (tester) async {
    final llamadas = <String>[];
    await pump(tester,
        onPlay: () => llamadas.add('play'),
        onPause: () => llamadas.add('pause'),
        onResume: () => llamadas.add('resume'));
    await tester.tap(find.byTooltip('Reproducir'));

    await pump(tester,
        reader: const ReaderState().copyWith(status: ReaderStatus.playing),
        onPause: () => llamadas.add('pause'));
    expect(find.byIcon(Icons.pause), findsOneWidget);
    await tester.tap(find.byTooltip('Pausar'));

    await pump(tester,
        reader: const ReaderState().copyWith(status: ReaderStatus.paused),
        onResume: () => llamadas.add('resume'));
    await tester.tap(find.byTooltip('Reproducir'));

    expect(llamadas, ['play', 'pause', 'resume']);
  });

  testWidgets('sintetizando: la rueda ocupa el sitio del play',
      (tester) async {
    await pump(tester,
        reader:
            const ReaderState().copyWith(status: ReaderStatus.synthesizing));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byTooltip('Reproducir'), findsNothing);
  });

  testWidgets('la velocidad se escribe con los decimales que hagan falta',
      (tester) async {
    await pump(tester, speed: 1.25);
    expect(find.text('1.25×'), findsOneWidget);
    await pump(tester, speed: 2.0);
    expect(find.text('2.0×'), findsOneWidget);
  });

  testWidgets('el temporizador manda lo elegido y muestra lo que queda',
      (tester) async {
    final elegido = <Duration?>[];
    await pump(tester, onSleepChanged: elegido.add);
    await tester.tap(find.byTooltip('Temporizador de apagado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Al final del capítulo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Temporizador de apagado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desactivado'));
    await tester.pumpAndSettle();
    expect(elegido, [null, Duration.zero]);

    await pump(tester,
        reader: const ReaderState().copyWith(sleepAtChapterEnd: true));
    expect(find.text('cap.'), findsOneWidget);
    expect(find.byIcon(Icons.bedtime), findsOneWidget);
  });

  testWidgets('a 320 dp nada desborda', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pump(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Capítulo'), findsNWidgets(2));
  });
}
