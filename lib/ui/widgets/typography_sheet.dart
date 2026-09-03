import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/settings.dart';
import '../providers/settings_provider.dart';
import 'reader_theme.dart';

/// Tipografía del lector, sin salir del libro.
///
/// Los controles existían desde 0.3.0, pero vivían en la pantalla global de
/// Ajustes, entre el motor de voz y la caché. Cambiar el tamaño de letra
/// obligaba a abandonar la lectura, ajustar a ciegas, volver, y repetir hasta
/// acertar. Es el control que más se toca en cualquier lector, y era el único
/// que no se podía ver mientras se usaba.
///
/// La hoja se queda a media pantalla a propósito: el texto sigue visible detrás
/// y cada cambio se aplica al instante sobre él.
Future<void> showTypographySheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _TypographySheet(),
    );

class _TypographySheet extends ConsumerStatefulWidget {
  const _TypographySheet();

  @override
  ConsumerState<_TypographySheet> createState() => _TypographySheetState();
}

class _TypographySheetState extends ConsumerState<_TypographySheet> {
  Timer? _guardar;

  @override
  void dispose() {
    // Cerrar la hoja no puede perder un cambio que aún esperaba al debounce.
    if (_guardar?.isActive ?? false) {
      _guardar!.cancel();
      final s = ref.read(settingsProvider).valueOrNull;
      if (s != null) unawaited(ref.read(settingsProvider.notifier).save(s));
    }
    super.dispose();
  }

  /// Aplica el cambio ya y lo persiste un momento después: arrastrar un
  /// deslizador no debe convertirse en una escritura por píxel.
  void _cambiar(AppSettings next) {
    ref.read(settingsProvider.notifier).setDraft(next);
    _guardar?.cancel();
    _guardar = Timer(const Duration(milliseconds: 400),
        () => ref.read(settingsProvider.notifier).save(next));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider).valueOrNull ?? AppSettings();
    final palette = ReaderPalette.of(
        s.readerTheme, MediaQuery.platformBrightnessOf(context));

    return Container(
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: palette.muted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          _Fila(
            palette: palette,
            etiqueta: 'Letra',
            // Iconos en vez de números: el tamaño se juzga mirando el texto de
            // detrás, no leyendo un 18.
            children: [
              _Paso(
                palette: palette,
                icono: Icons.text_decrease,
                onTap: s.fontSize > 12
                    ? () => _cambiar(s.copyWith(fontSize: s.fontSize - 1))
                    : null,
              ),
              Text('${s.fontSize.round()}',
                  style: TextStyle(color: palette.text, fontSize: 15)),
              _Paso(
                palette: palette,
                icono: Icons.text_increase,
                onTap: s.fontSize < 32
                    ? () => _cambiar(s.copyWith(fontSize: s.fontSize + 1))
                    : null,
              ),
            ],
          ),

          _Fila(
            palette: palette,
            etiqueta: 'Interlineado',
            children: [
              _Paso(
                palette: palette,
                icono: Icons.density_small,
                onTap: s.lineHeight > 1.2
                    ? () => _cambiar(s.copyWith(lineHeight: s.lineHeight - 0.1))
                    : null,
              ),
              Text(s.lineHeight.toStringAsFixed(1),
                  style: TextStyle(color: palette.text, fontSize: 15)),
              _Paso(
                palette: palette,
                icono: Icons.density_large,
                onTap: s.lineHeight < 2.4
                    ? () => _cambiar(s.copyWith(lineHeight: s.lineHeight + 0.1))
                    : null,
              ),
            ],
          ),

          _Fila(
            palette: palette,
            etiqueta: 'Márgenes',
            children: [
              _Paso(
                palette: palette,
                icono: Icons.unfold_less,
                onTap: s.margin > 8
                    ? () => _cambiar(s.copyWith(margin: s.margin - 4))
                    : null,
              ),
              Text('${s.margin.round()}',
                  style: TextStyle(color: palette.text, fontSize: 15)),
              _Paso(
                palette: palette,
                icono: Icons.unfold_more,
                onTap: s.margin < 48
                    ? () => _cambiar(s.copyWith(margin: s.margin + 4))
                    : null,
              ),
            ],
          ),

          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'serif', label: Text('Serif')),
              ButtonSegment(value: 'sans', label: Text('Sans')),
              ButtonSegment(value: 'system', label: Text('Sistema')),
            ],
            selected: {s.readerFont},
            showSelectedIcon: false,
            onSelectionChanged: (v) =>
                _cambiar(s.copyWith(readerFont: v.first)),
          ),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'sepia', label: Text('Sepia')),
              ButtonSegment(value: 'light', label: Text('Claro')),
              ButtonSegment(value: 'dark', label: Text('Oscuro')),
            ],
            selected: {s.readerTheme},
            showSelectedIcon: false,
            onSelectionChanged: (v) =>
                _cambiar(s.copyWith(readerTheme: v.first)),
          ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.palette,
    required this.etiqueta,
    required this.children,
  });

  final ReaderPalette palette;
  final String etiqueta;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Text(etiqueta,
                  style: TextStyle(color: palette.muted, fontSize: 13)),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: children,
              ),
            ),
          ],
        ),
      );
}

class _Paso extends StatelessWidget {
  const _Paso({required this.palette, required this.icono, this.onTap});

  final ReaderPalette palette;
  final IconData icono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(icono),
        color: palette.text,
        disabledColor: palette.muted.withValues(alpha: 0.4),
        onPressed: onTap,
      );
}
