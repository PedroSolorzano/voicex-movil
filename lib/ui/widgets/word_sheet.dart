import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../epub/models.dart';
import '../../epub/text_align.dart';
import '../../services/dictionary.dart';

/// Bridges to MainActivity for handing a word to another app (a translator,
/// typically). Uses ACTION_PROCESS_TEXT, which is why the manifest already
/// declares the matching `<queries>` block.
const _textChannel = MethodChannel('voicex/shared_epub');

/// Actions for a single word: hear it, look it up, or send it elsewhere — plus
/// the ones that act on the paragraph it came from.
///
/// Shown on long press. Tapping the page is what shows and hides the chrome,
/// the way every other reader behaves, so everything else lives here.
class WordSheet extends StatefulWidget {
  final String word;

  /// Book language: picks which dictionary to consult.
  final String language;

  /// Plays the word. Returns false when no audio could be produced.
  final Future<bool> Function() onPronounce;

  /// Starts reading aloud from the paragraph this word came from.
  ///
  /// This used to be the paragraph's own `onTap`, which made it the easiest
  /// gesture in the app to trigger by accident — a thumb brushing the page
  /// while the book was playing stopped it and moved the saved position. A
  /// long press is nobody's accident.
  final VoidCallback onReadFromHere;

  /// The paragraph the word came from, for the actions that act on a passage
  /// rather than on the word.
  final Paragraph paragraph;

  /// Where the word starts inside `paragraph.rawText`, which is what says
  /// which sentence "this one" means.
  final int offset;

  const WordSheet({
    super.key,
    required this.word,
    required this.language,
    required this.onPronounce,
    required this.onReadFromHere,
    required this.paragraph,
    required this.offset,
  });

  @override
  State<WordSheet> createState() => _WordSheetState();
}

class _WordSheetState extends State<WordSheet> {
  DictionaryEntry? _entry;
  bool _loading = false;
  bool _pronouncing = false;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  Future<void> _lookup() async {
    setState(() => _loading = true);
    final entry = await DictionaryService.lookup(widget.word,
        language: widget.language);
    if (!mounted) return;
    setState(() {
      _entry = entry;
      _loading = false;
    });
  }

  Future<void> _pronounce() async {
    setState(() => _pronouncing = true);
    final ok = await widget.onPronounce();
    if (!mounted) return;
    setState(() => _pronouncing = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No hay audio para esta palabra todavía.'),
      ));
    }
  }

  /// La oración que contiene la palabra pulsada.
  String get _oracion => sentenceAt(widget.paragraph, widget.offset);

  Future<void> _copiar(String texto, String aviso) async {
    // El mensajero se toma antes de cerrar: después, este `context` ya no
    // está montado y no encuentra ninguno.
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(aviso)));
  }

  Future<void> _compartir() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _textChannel.invokeMethod('shareText', _oracion);
      if (mounted) Navigator.pop(context);
    } on PlatformException catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('No se pudo compartir: ${e.message}')));
    }
  }

  /// Hands the word to whatever app can process text — Google Translate and
  /// friends. The offline answer when the dictionary is unreachable.
  Future<void> _openElsewhere() async {
    try {
      await _textChannel.invokeMethod('processText', widget.word);
      if (mounted) Navigator.pop(context);
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ninguna app pudo abrirlo: ${e.message}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    widget.word,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_entry?.phonetic != null) ...[
                  const SizedBox(width: 10),
                  Text(_entry!.phonetic!,
                      style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                FilledButton.icon(
                  icon: _pronouncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.volume_up),
                  label: const Text('Pronunciar'),
                  onPressed: _pronouncing ? null : _pronounce,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Otra app'),
                  onPressed: _openElsewhere,
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Lo que actúa sobre el pasaje y no sobre la palabra. Copiar una
            // cita no se podía: los párrafos son `Text` plano y no hay
            // selección en ninguna parte de la app.
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: const Text('Leer desde aquí'),
                  onPressed: widget.onReadFromHere,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.format_quote, size: 18),
                  label: const Text('Copiar oración'),
                  onPressed: () => _copiar(_oracion, 'Oración copiada'),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.notes, size: 18),
                  label: const Text('Copiar párrafo'),
                  onPressed: () =>
                      _copiar(widget.paragraph.rawText, 'Párrafo copiado'),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Compartir'),
                  onPressed: _compartir,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_entry != null)
              _Definitions(entry: _entry!, onRetry: _lookup),
          ],
        ),
      ),
    );
  }
}

class _Definitions extends StatelessWidget {
  final DictionaryEntry entry;
  final VoidCallback onRetry;

  const _Definitions({required this.entry, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (entry.isEmpty) {
      return Row(
        children: [
          Expanded(
            child: Text(entry.error ?? 'Sin definiciones.',
                style: theme.textTheme.bodySmall),
          ),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 300),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: entry.definitions.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          final d = entry.definitions[i];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (d.partOfSpeech.isNotEmpty)
                Text(d.partOfSpeech,
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontStyle: FontStyle.italic)),
              Text(d.meaning, style: theme.textTheme.bodyMedium),
              if (d.example != null && d.example!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('“${d.example}”',
                      style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
            ],
          );
        },
      ),
    );
  }
}
