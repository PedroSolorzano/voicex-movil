import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:package_info_plus/package_info_plus.dart';
import '../../config/settings.dart';
import '../../storage/repositories.dart';
import '../../tts/tts_factory.dart';
import '../providers/settings_provider.dart';
import '../providers/voices_provider.dart';

const _previewTextEs = 'Hola, así sonará la narración de tus libros.';
const _previewTextEn = 'Hello, this is how your books will be narrated.';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AppSettings? _draft;
  final _cacheRepo = AudioCacheRepo();
  final _previewPlayer = ja.AudioPlayer();
  int _cacheSizeKb = 0;
  bool _saving = false;
  String? _previewing;
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  @override
  void dispose() {
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadCacheSize() async {
    final kb = await _cacheRepo.totalSizeKb();
    if (mounted) setState(() => _cacheSizeKb = kb);
  }

  AppSettings get _settings =>
      _draft ?? ref.read(settingsProvider).valueOrNull ?? AppSettings();

  void _update(AppSettings next) => setState(() => _draft = next);

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (_, next) {
      if (_draft == null && next.hasValue) {
        setState(() => _draft = next.value);
      }
    });

    final s = _settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: 'Motor de voz', children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'edge',
                    label: Text('Edge'),
                    icon: Icon(Icons.cloud_outlined)),
                ButtonSegment(
                    value: 'android',
                    label: Text('Android'),
                    icon: Icon(Icons.phone_android)),
              ],
              selected: {s.ttsProvider},
              onSelectionChanged: (v) =>
                  _update(s.copyWith(ttsProvider: v.first)),
            ),
            const SizedBox(height: 8),
            Text(
              s.ttsProvider == 'edge'
                  ? 'Voces neuronales de Microsoft. Requiere internet; el audio '
                      'se guarda en caché para volver a escucharlo sin conexión.'
                  : 'Motor de voz del propio teléfono. Funciona sin internet, '
                      'pero no marca las palabras, así que el resaltado de oración '
                      'se calcula de forma aproximada.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),

          _Section(title: 'Voces', children: [
            _VoiceTile(
              label: 'Español',
              lang: 'es',
              settings: s,
              onPick: (id) => _update(s.copyWith(edgeVoiceEs: id)),
              onPreview: _preview,
              previewing: _previewing,
            ),
            const SizedBox(height: 8),
            _VoiceTile(
              label: 'Inglés',
              lang: 'en',
              settings: s,
              onPick: (id) => _update(s.copyWith(edgeVoiceEn: id)),
              onPreview: _preview,
              previewing: _previewing,
            ),
            if (s.ttsProvider == 'edge') ...[
              const SizedBox(height: 8),
              Row(children: [
                const Text('Género por defecto: '),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Femenina'),
                  selected: s.gender == 'female',
                  onSelected: (_) => _update(s.copyWith(gender: 'female')),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Masculina'),
                  selected: s.gender == 'male',
                  onSelected: (_) => _update(s.copyWith(gender: 'male')),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Se usa cuando no has elegido una voz concreta arriba.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ]),

          _Section(title: 'Velocidad de reproducción', children: [
            Row(
              children: [
                const Text('0.5×'),
                Expanded(
                  child: Slider(
                    value: s.playbackSpeed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: '${s.playbackSpeed.toStringAsFixed(2)}×',
                    onChanged: (v) => _update(s.copyWith(playbackSpeed: v)),
                  ),
                ),
                const Text('2.0×'),
              ],
            ),
            Text(
              'Se aplica al reproducir, así que cambiarla no vuelve a gastar '
              'datos ni invalida el audio ya descargado.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),

          _Section(title: 'Lectura', children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Resaltar oración activa'),
              value: s.highlightSentences,
              onChanged: (v) => _update(s.copyWith(highlightSentences: v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Resaltar palabra actual'),
              subtitle: const Text(
                  'Subraya la palabra que se está pronunciando. Solo con Edge, '
                  'que es el que reporta los tiempos por palabra.'),
              value: s.highlightWords,
              onChanged: s.highlightSentences
                  ? (v) => _update(s.copyWith(highlightWords: v))
                  : null,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Seguir el audio al desplazar'),
              subtitle: const Text(
                  'Centra automáticamente el párrafo que se está leyendo'),
              value: s.followAudioScroll,
              onChanged: (v) => _update(s.copyWith(followAudioScroll: v)),
            ),
            const SizedBox(height: 8),
            _LabelledSlider(
              label: 'Tamaño de letra',
              value: s.fontSize,
              min: 12,
              max: 32,
              divisions: 20,
              display: '${s.fontSize.round()}',
              onChanged: (v) => _update(s.copyWith(fontSize: v)),
            ),
            _LabelledSlider(
              label: 'Interlineado',
              value: s.lineHeight,
              min: 1.2,
              max: 2.4,
              divisions: 12,
              display: s.lineHeight.toStringAsFixed(1),
              onChanged: (v) => _update(s.copyWith(lineHeight: v)),
            ),
            _LabelledSlider(
              label: 'Márgenes',
              value: s.margin,
              min: 8,
              max: 48,
              divisions: 10,
              display: '${s.margin.round()}',
              onChanged: (v) => _update(s.copyWith(margin: v)),
            ),
            const SizedBox(height: 8),
            const Text('Tipografía'),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'serif', label: Text('Serif')),
                ButtonSegment(value: 'sans', label: Text('Sans')),
                ButtonSegment(value: 'system', label: Text('Sistema')),
              ],
              selected: {s.readerFont},
              onSelectionChanged: (v) =>
                  _update(s.copyWith(readerFont: v.first)),
            ),
            const SizedBox(height: 12),
            const Text('Fondo del lector'),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'sepia', label: Text('Sepia')),
                ButtonSegment(value: 'light', label: Text('Claro')),
                ButtonSegment(value: 'dark', label: Text('Oscuro')),
              ],
              selected: {s.readerTheme},
              onSelectionChanged: (v) =>
                  _update(s.copyWith(readerTheme: v.first)),
            ),
          ]),

          _Section(title: 'Tema de la app', children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'dark', label: Text('Oscuro')),
                ButtonSegment(value: 'light', label: Text('Claro')),
                ButtonSegment(value: 'system', label: Text('Sistema')),
              ],
              selected: {s.theme},
              onSelectionChanged: (v) => _update(s.copyWith(theme: v.first)),
            ),
          ]),

          _Section(title: 'Caché de audio', children: [
            Text(
                'Uso actual: ${(_cacheSizeKb / 1024).toStringAsFixed(1)} MB / ${s.cacheMaxMb} MB'),
            const SizedBox(height: 8),
            _LabelledSlider(
              label: 'Máximo',
              value: s.cacheMaxMb.toDouble(),
              min: 50,
              max: 500,
              divisions: 18,
              display: '${s.cacheMaxMb} MB',
              onChanged: (v) => _update(s.copyWith(cacheMaxMb: v.toInt())),
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Limpiar caché'),
              onPressed: _clearCache,
            ),
          ]),

          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Guardar'),
          ),
          const SizedBox(height: 32),
          if (_packageInfo != null)
            Center(
              child: Text(
                'VoiceX v${_packageInfo!.version}  (build ${_packageInfo!.buildNumber})',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.4),
                    ),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(settingsProvider.notifier).save(_settings);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Ajustes guardados')));
  }

  Future<void> _clearCache() async {
    await _cacheRepo.clearAll();
    await _loadCacheSize();
  }

  /// Synthesizes a short line and actually plays it. The previous version
  /// generated the file and threw it away, so the button was silent.
  Future<void> _preview(String voiceId, String lang) async {
    if (_previewing != null) return;
    setState(() => _previewing = voiceId);

    final s = _settings;
    final tts = getProvider(s);
    String? path;
    try {
      final result = await tts.synthesize(
        text: lang == 'en' ? _previewTextEn : _previewTextEs,
        voice: voiceId,
        rate: s.edgeRate,
        volume: s.edgeVolume,
      );
      path = result.filePath;
      await _previewPlayer.setFilePath(path);
      await _previewPlayer.setSpeed(s.playbackSpeed);
      await _previewPlayer.play();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo reproducir la prueba: $e')));
      }
    } finally {
      await tts.dispose();
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      if (mounted) setState(() => _previewing = null);
    }
  }
}

// ─── Voice picker ────────────────────────────────────────────────────────────

class _VoiceTile extends ConsumerWidget {
  final String label;
  final String lang;
  final AppSettings settings;
  final ValueChanged<String> onPick;
  final Future<void> Function(String voiceId, String lang) onPreview;
  final String? previewing;

  const _VoiceTile({
    required this.label,
    required this.lang,
    required this.settings,
    required this.onPick,
    required this.onPreview,
    required this.previewing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = settings.voiceFor(lang);
    final isPreviewing = previewing == current;

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        title: Text(label),
        subtitle: Text(current, style: Theme.of(context).textTheme.bodySmall),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Escuchar prueba',
              icon: isPreviewing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_circle_outline),
              onPressed:
                  previewing != null ? null : () => onPreview(current, lang),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _openPicker(context, ref, current),
      ),
    );
  }

  Future<void> _openPicker(
      BuildContext context, WidgetRef ref, String current) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _VoicePickerSheet(
        providerKind: settings.ttsProvider,
        lang: lang,
        current: current,
        onPreview: (id) => onPreview(id, lang),
      ),
    );
    if (picked != null) onPick(picked);
  }
}

class _VoicePickerSheet extends ConsumerStatefulWidget {
  final String providerKind;
  final String lang;
  final String current;
  final Future<void> Function(String voiceId) onPreview;

  const _VoicePickerSheet({
    required this.providerKind,
    required this.lang,
    required this.current,
    required this.onPreview,
  });

  @override
  ConsumerState<_VoicePickerSheet> createState() => _VoicePickerSheetState();
}

class _VoicePickerSheetState extends ConsumerState<_VoicePickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(voicesProvider(widget.providerKind));

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar voz o país…',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _PickerFallback(
                message: 'No se pudo cargar el catálogo de voces.\n'
                    'Se usará la voz por defecto.',
                detail: '$e',
              ),
              data: (all) {
                final voices = voicesForLanguage(all, widget.lang)
                    .where((v) =>
                        _query.isEmpty ||
                        v.name.toLowerCase().contains(_query) ||
                        v.id.toLowerCase().contains(_query) ||
                        v.locale.toLowerCase().contains(_query))
                    .toList();

                if (voices.isEmpty) {
                  return const _PickerFallback(
                    message: 'No hay voces disponibles para este idioma.',
                  );
                }

                return ListView.builder(
                  controller: scrollCtrl,
                  itemCount: voices.length,
                  itemBuilder: (_, i) {
                    final v = voices[i];
                    final selected = v.id == widget.current;
                    return ListTile(
                      selected: selected,
                      leading: Icon(v.gender == 'male'
                          ? Icons.man_outlined
                          : v.gender == 'female'
                              ? Icons.woman_outlined
                              : Icons.record_voice_over_outlined),
                      title: Text(v.name, maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: Text('${v.id} · ${v.locale}',
                          style: Theme.of(context).textTheme.labelSmall),
                      trailing: IconButton(
                        tooltip: 'Escuchar',
                        icon: const Icon(Icons.play_circle_outline),
                        onPressed: () => widget.onPreview(v.id),
                      ),
                      onTap: () => Navigator.pop(context, v.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PickerFallback extends StatelessWidget {
  final String message;
  final String? detail;
  const _PickerFallback({required this.message, this.detail});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (detail != null) ...[
                const SizedBox(height: 8),
                Text(detail!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ],
          ),
        ),
      );
}

// ─── Small building blocks ───────────────────────────────────────────────────

class _LabelledSlider extends StatelessWidget {
  final String label;
  final double value, min, max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  const _LabelledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(width: 120, child: Text(label)),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              label: display,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
              width: 56,
              child: Text(display, textAlign: TextAlign.end)),
        ],
      );
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: Theme.of(context).colorScheme.primary)),
        ),
        ...children,
        const Divider(height: 24),
      ],
    );
  }
}
