import 'package:flutter/material.dart';
import '../providers/reader_provider.dart';
import 'reader_theme.dart';

/// The listening bar: chapter and paragraph steps around play, then speed and
/// the sleep timer.
///
/// A synthesized audiobook has no tracks or seconds, it has paragraphs and
/// chapters, so every navigation button names the unit it moves. Speed and
/// the timer go without a caption: "1.0×" describes itself and the moon is
/// what every audiobook app uses.
///
/// Callback-driven so it builds without a [ReaderNotifier]; the screen maps
/// each callback onto the provider.
class ReaderTransport extends StatelessWidget {
  final ReaderState reader;
  final ReaderPalette palette;
  final double speed;

  /// Null on the first / last chapter, which disables the button.
  final VoidCallback? onPreviousChapter;
  final VoidCallback? onNextChapter;
  final VoidCallback onPreviousParagraph;
  final VoidCallback onNextParagraph;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final ValueChanged<double> onSpeedChanged;

  /// `null` is "at the end of the chapter"; [Duration.zero] turns the timer off.
  final ValueChanged<Duration?> onSleepChanged;

  const ReaderTransport({
    super.key,
    required this.reader,
    required this.palette,
    required this.speed,
    required this.onPreviousChapter,
    required this.onNextChapter,
    required this.onPreviousParagraph,
    required this.onNextParagraph,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
    required this.onSpeedChanged,
    required this.onSleepChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: _UnitButton(
              icon: Icons.keyboard_double_arrow_left,
              caption: 'Capítulo',
              tooltip: 'Capítulo anterior',
              palette: palette,
              onTap: onPreviousChapter,
            ),
          ),
          Expanded(
            flex: 4,
            child: _UnitButton(
              icon: Icons.skip_previous,
              caption: 'Párrafo',
              tooltip: 'Párrafo anterior',
              palette: palette,
              onTap: onPreviousParagraph,
            ),
          ),
          _PlayButton(
            status: reader.status,
            onPlay: onPlay,
            onPause: onPause,
            onResume: onResume,
          ),
          Expanded(
            flex: 4,
            child: _UnitButton(
              icon: Icons.skip_next,
              caption: 'Párrafo',
              tooltip: 'Párrafo siguiente',
              palette: palette,
              onTap: onNextParagraph,
            ),
          ),
          Expanded(
            flex: 4,
            child: _UnitButton(
              icon: Icons.keyboard_double_arrow_right,
              caption: 'Capítulo',
              tooltip: 'Capítulo siguiente',
              palette: palette,
              onTap: onNextChapter,
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(
              child: _SpeedMenu(
                current: speed,
                palette: palette,
                onChanged: onSpeedChanged,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Center(
              child: _SleepMenu(
                reader: reader,
                palette: palette,
                onChanged: onSleepChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// An icon over an 11 px caption naming the unit it moves.
///
/// The caption scales down rather than clipping: at 320 dp the slot is
/// narrower than "Capítulo".
class _UnitButton extends StatelessWidget {
  final IconData icon;
  final String caption;
  final String tooltip;
  final ReaderPalette palette;
  final VoidCallback? onTap;

  const _UnitButton({
    required this.icon,
    required this.caption,
    required this.tooltip,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final disabled = Theme.of(context).disabledColor;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        child: InkResponse(
          onTap: onTap,
          radius: 32,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 40,
                  child: Center(
                    child: Icon(icon,
                        color: enabled ? palette.text : disabled),
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    caption,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 11,
                      color: enabled ? palette.muted : disabled,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final ReaderStatus status;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final VoidCallback onResume;

  const _PlayButton({
    required this.status,
    required this.onPlay,
    required this.onPause,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    if (status == ReaderStatus.synthesizing) {
      return const SizedBox(
        width: 48,
        height: 48,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final isPlaying = status == ReaderStatus.playing;
    return IconButton.filled(
      iconSize: 30,
      icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
      tooltip: isPlaying ? 'Pausar' : 'Reproducir',
      onPressed: () {
        if (isPlaying) {
          onPause();
        } else if (status == ReaderStatus.paused) {
          onResume();
        } else {
          onPlay();
        }
      },
    );
  }
}

/// Temporizador de apagado: lo primero que se echa en falta escuchando en la
/// cama, y hasta ahora el audio seguía hasta que se acababa el libro.
class _SleepMenu extends StatelessWidget {
  final ReaderState reader;
  final ReaderPalette palette;
  final ValueChanged<Duration?> onChanged;

  const _SleepMenu({
    required this.reader,
    required this.palette,
    required this.onChanged,
  });

  /// Stands in for "al final del capítulo" inside the menu. PopupMenuButton
  /// reports a null value as the menu being dismissed and never delivers it,
  /// so that option, worth null to the caller, needs a value of its own here.
  static const _chapterEnd = Duration(microseconds: -1);

  /// `Duration.zero` is off; [_chapterEnd] leaves as `null`.
  static const _opciones = <(Duration, String)>[
    (Duration.zero, 'Desactivado'),
    (Duration(minutes: 10), '10 minutos'),
    (Duration(minutes: 20), '20 minutos'),
    (Duration(minutes: 30), '30 minutos'),
    (Duration(minutes: 45), '45 minutos'),
    (Duration(minutes: 60), '1 hora'),
    (_chapterEnd, 'Al final del capítulo'),
  ];

  bool get _activo => reader.sleepAt != null || reader.sleepAtChapterEnd;

  String? get _restante {
    if (reader.sleepAtChapterEnd) return 'cap.';
    final at = reader.sleepAt;
    if (at == null) return null;
    final minutos = at.difference(DateTime.now()).inMinutes + 1;
    return minutos > 0 ? '${minutos}m' : null;
  }

  @override
  Widget build(BuildContext context) {
    final restante = _restante;
    return PopupMenuButton<Duration>(
      tooltip: 'Temporizador de apagado',
      onSelected: (d) => onChanged(d == _chapterEnd ? null : d),
      itemBuilder: (_) => [
        for (final (duracion, etiqueta) in _opciones)
          PopupMenuItem(value: duracion, child: Text(etiqueta)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_activo ? Icons.bedtime : Icons.bedtime_outlined,
                size: 22, color: palette.text),
            if (restante != null)
              Text(restante,
                  style: TextStyle(fontSize: 10, color: palette.muted)),
          ],
        ),
      ),
    );
  }
}

class _SpeedMenu extends StatelessWidget {
  final double current;
  final ReaderPalette palette;
  final ValueChanged<double> onChanged;

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  const _SpeedMenu({
    required this.current,
    required this.palette,
    required this.onChanged,
  });

  /// "1.0×", "1.25×": one decimal unless the value needs two.
  static String label(double speed) {
    final one = speed.toStringAsFixed(1);
    final text = double.parse(one) == speed ? one : speed.toStringAsFixed(2);
    return '$text×';
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<double>(
      tooltip: 'Velocidad',
      initialValue: current,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final s in _speeds) PopupMenuItem(value: s, child: Text(label(s))),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Text(
          label(current),
          style: TextStyle(color: palette.text, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
