import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/settings.dart';
import '../../storage/repositories.dart';
import '../../tts/tts_factory.dart';
import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  AppSettings? _draft;
  final _cacheRepo = AudioCacheRepo();
  int _cacheSizeKb = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
  }

  Future<void> _loadCacheSize() async {
    final kb = await _cacheRepo.totalSizeKb();
    if (mounted) setState(() => _cacheSizeKb = kb);
  }

  AppSettings get _settings =>
      _draft ?? ref.read(settingsProvider).valueOrNull ?? AppSettings();

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
          // TTS Provider
          _Section(title: 'Motor TTS', children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'edge', label: Text('Edge TTS (online)')),
                ButtonSegment(
                    value: 'android', label: Text('Android (offline)')),
              ],
              selected: {s.ttsProvider},
              onSelectionChanged: (v) =>
                  setState(() => _draft = s.copyWith(ttsProvider: v.first)),
            ),
          ]),

          // Voice grid
          _Section(title: 'Voces', children: [
            _VoiceGrid(provider: s.ttsProvider),
          ]),

          // Speed
          _Section(title: 'Velocidad (Android TTS)', children: [
            Row(
              children: [
                const Text('0.5×'),
                Expanded(
                  child: Slider(
                    value: s.androidSpeed,
                    min: 0.5,
                    max: 2.0,
                    divisions: 15,
                    label: '${s.androidSpeed.toStringAsFixed(2)}×',
                    onChanged: (v) =>
                        setState(() => _draft = s.copyWith(androidSpeed: v)),
                  ),
                ),
                const Text('2.0×'),
              ],
            ),
          ]),

          // Highlight
          _Section(title: 'Lectura', children: [
            SwitchListTile(
              title: const Text('Resaltar oración activa'),
              value: s.highlightSentences,
              onChanged: (v) =>
                  setState(() => _draft = s.copyWith(highlightSentences: v)),
            ),
          ]),

          // Theme
          _Section(title: 'Tema', children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'dark', label: Text('Oscuro')),
                ButtonSegment(value: 'light', label: Text('Claro')),
                ButtonSegment(value: 'system', label: Text('Sistema')),
              ],
              selected: {s.theme},
              onSelectionChanged: (v) =>
                  setState(() => _draft = s.copyWith(theme: v.first)),
            ),
          ]),

          // Cache
          _Section(title: 'Caché de audio', children: [
            Text(
                'Uso actual: ${(_cacheSizeKb / 1024).toStringAsFixed(1)} MB / ${s.cacheMaxMb} MB'),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Máximo: '),
                Expanded(
                  child: Slider(
                    value: s.cacheMaxMb.toDouble(),
                    min: 50,
                    max: 500,
                    divisions: 18,
                    label: '${s.cacheMaxMb} MB',
                    onChanged: (v) => setState(
                        () => _draft = s.copyWith(cacheMaxMb: v.toInt())),
                  ),
                ),
                Text('${s.cacheMaxMb} MB'),
              ],
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined),
              label: const Text('Limpiar caché'),
              onPressed: _clearCache,
            ),
          ]),

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref.read(settingsProvider.notifier).save(_settings);
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Ajustes guardados')));
    }
  }

  Future<void> _clearCache() async {
    await _cacheRepo.clearAll();
    await _loadCacheSize();
  }
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
        const Divider(),
      ],
    );
  }
}

const _voiceRows = [
  ('ES ♀', 'es', 'female'),
  ('ES ♂', 'es', 'male'),
  ('EN ♀', 'en', 'female'),
  ('EN ♂', 'en', 'male'),
];

class _VoiceGrid extends ConsumerWidget {
  final String provider;
  const _VoiceGrid({required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _voiceRows.map((row) {
        final (label, lang, gender) = row;
        final voiceId = resolveVoice(provider, lang, gender);
        return OutlinedButton(
          onPressed: () => _preview(ref, voiceId, provider),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(voiceId,
                  style: const TextStyle(fontSize: 10),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        );
      }).toList(),
    );
  }

  Future<void> _preview(WidgetRef ref, String voiceId, String provider) async {
    final settings = ref.read(settingsProvider).valueOrNull ?? AppSettings();
    final tts = getProvider(settings.copyWith(ttsProvider: provider));
    try {
      await tts.synthesize(
        text: 'Hola, esta es una prueba de voz.',
        voice: voiceId,
        rate: '+0%',
        volume: '+0%',
      );
    } finally {
      await tts.dispose();
    }
  }
}
