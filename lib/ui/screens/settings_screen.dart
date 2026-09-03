import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:package_info_plus/package_info_plus.dart';
import '../../config/settings.dart';
import '../../storage/repositories.dart';
import '../../tts/tts_factory.dart';
import '../../tts/kokoro_tts_provider.dart';
import '../../tts/piper_tts_provider.dart';
import '../providers/reader_provider.dart';
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
  int _downloadsKb = 0;
  List<BookEngineUsage> _bookUsage = const [];
  Timer? _saveDebounce;
  bool _testingServer = false;
  bool _serverOk = false;
  String? _serverStatus;
  late final TextEditingController _kokoroUrlController;

  /// Engine whose URL the text field currently holds.
  String? _urlFieldOwner;
  String? _previewing;
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    final loaded = ref.read(settingsProvider).valueOrNull;
    _kokoroUrlController =
        TextEditingController(text: loaded?.selfHostedUrl ?? '');
    _loadCacheSize();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _packageInfo = info);
    });
  }

  @override
  void dispose() {
    // Leaving the screen must not drop a change still waiting on the debounce.
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      unawaited(ref.read(settingsProvider.notifier).save(_settings));
    }
    _previewPlayer.dispose();
    _kokoroUrlController.dispose();
    super.dispose();
  }

  /// Probes the configured server so a typo in the address is caught here
  /// rather than as a silent fallback to Edge mid-chapter.
  Future<void> _testKokoro() async {
    final url = _kokoroUrlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _serverOk = false;
        _serverStatus = 'Escribe la dirección del servidor.';
      });
      return;
    }

    setState(() {
      _testingServer = true;
      _serverStatus = null;
    });

    final isPiper = _settings.ttsProvider == 'piper';
    if (isPiper) {
      PiperTtsProvider.resetHealthCache();
    } else {
      KokoroTtsProvider.resetHealthCache();
    }
    final ok = isPiper
        ? await PiperTtsProvider.isReachable(url)
        : await KokoroTtsProvider.isReachable(url);
    if (!mounted) return;

    setState(() {
      _testingServer = false;
      _serverOk = ok;
      _serverStatus = ok
          ? 'Servidor accesible.'
          : 'No responde. Comprueba que el contenedor esté arriba y que el '
              'teléfono esté en la misma red.';
    });
  }

  Future<void> _loadCacheSize() async {
    final size = await _cacheRepo.sizeBreakdown();
    // The reader sits below this screen in the stack, so its provider still
    // holds the open book: no need to thread an id through the route.
    final bookId = ref.read(readerProvider).book?.id;
    final usage =
        bookId == null ? const <BookEngineUsage>[] : await _cacheRepo.usageForBook(bookId);

    if (!mounted) return;
    setState(() {
      _cacheSizeKb = size.cacheKb;
      _downloadsKb = size.downloadsKb;
      _bookUsage = usage;
    });
  }

  AppSettings get _settings =>
      _draft ?? ref.read(settingsProvider).valueOrNull ?? AppSettings();

  /// Applies a change straight away and persists it shortly after.
  ///
  /// Settings used to need an explicit Save at the bottom of a long page, so
  /// switching engine meant scrolling past everything to confirm it. The draft
  /// still exists so the UI reacts instantly; only the write is debounced, and
  /// a drag across a slider does not become one write per pixel.
  void _update(AppSettings next) {
    setState(() => _draft = next);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _persist);
  }

  Future<void> _persist() async {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    await ref.read(settingsProvider.notifier).save(_settings);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (_, next) {
      if (_draft == null && next.hasValue) {
        setState(() => _draft = next.value);
      }
    });

    final s = _settings;

    // Each engine keeps its own address. Without this the field would still be
    // showing the previous engine's URL after switching, while typing wrote to
    // the new one — so a Kokoro address could silently land in Piper's setting.
    if (_urlFieldOwner != s.ttsProvider) {
      _urlFieldOwner = s.ttsProvider;
      _kokoroUrlController.text = s.selfHostedUrl;
      _serverStatus = null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: 'Motor de voz', children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final engine in const [
                  ('edge', 'Edge', Icons.cloud_outlined),
                  ('kokoro', 'Kokoro', Icons.home_outlined),
                  ('piper', 'Piper', Icons.record_voice_over_outlined),
                ])
                  ChoiceChip(
                    avatar: Icon(engine.$3, size: 18),
                    label: Text(engine.$2),
                    selected: s.ttsProvider == engine.$1,
                    onSelected: (_) =>
                        _update(s.copyWith(ttsProvider: engine.$1)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              switch (s.ttsProvider) {
                'kokoro' =>
                  'Servidor propio en tu red. Mejor calidad de voz, pero solo '
                      'responde con la computadora encendida: fuera de casa la app '
                      'usa Edge automáticamente, o el audio ya descargado.',
                'piper' =>
                  'Servidor propio con voces entrenadas en cada idioma. Muy '
                      'rápido, pero no marca las palabras: el resaltado se calcula '
                      'por oración de forma aproximada.',
                _ =>
                  'Voces neuronales de Microsoft. Requiere internet; el audio se '
                      'guarda en caché para volver a escucharlo sin conexión.',
              },
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ]),

          if (s.usesSelfHostedServer)
            _Section(
                title: 'Servidor ${providerLabel(s.ttsProvider)}',
                children: [
              TextField(
                controller: _kokoroUrlController,
                decoration: InputDecoration(
                  labelText: 'Dirección del servidor',
                  hintText: 'http://192.168.1.50:8880',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: _testingServer
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering),
                    tooltip: 'Probar conexión',
                    onPressed: _testingServer ? null : _testKokoro,
                  ),
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                onChanged: (v) => _update(s.ttsProvider == 'piper'
                    ? s.copyWith(piperBaseUrl: v.trim())
                    : s.copyWith(kokoroBaseUrl: v.trim())),
              ),
              if (_serverStatus != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _serverStatus!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _serverOk
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
              if (s.ttsProvider == 'piper') ...[
                const SizedBox(height: 12),
                _LabelledSlider(
                  label: 'Ritmo',
                  value: s.piperLengthScale,
                  min: 0.8,
                  max: 1.6,
                  divisions: 16,
                  // Named, not just numbered: this is phoneme *length*, so a
                  // higher number is slower — the opposite of what a bare "×"
                  // suggests, and a reader chasing a slower voice will reach
                  // for the low end and get a faster one.
                  display: _paceLabel(s.piperLengthScale),
                  onChanged: (v) => _update(s.copyWith(piperLengthScale: v)),
                  // The pace is part of the cache key because Piper bakes it
                  // into the samples. Moving the slider by accident silently
                  // orphans every download made at the previous pace, which is
                  // exactly how hours of audio went missing during testing.
                  onChangeEnd: (v) => _warnPaceInvalidates(v),
                ),
                Text(
                  'Alarga cada fonema al sintetizar: números más altos hablan '
                  'más pausado. Suena mejor que frenar la reproducción, pero va '
                  'grabado en el audio, así que cambiarlo obliga a descargar de '
                  'nuevo.\n\n'
                  'Para ir más despacio sin volver a descargar, usa "Velocidad '
                  'de reproducción" más abajo.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Descargar por adelantado en WiFi'),
                subtitle: const Text(
                    'Deja capítulos listos para escuchar sin conexión. Nunca usa '
                    'datos móviles.'),
                value: s.prefetchOnWifi,
                onChanged: (v) => _update(s.copyWith(prefetchOnWifi: v)),
              ),
              if (s.prefetchOnWifi)
                _LabelledSlider(
                  label: 'Capítulos',
                  value: s.prefetchChapters.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  display: '${s.prefetchChapters}',
                  onChanged: (v) =>
                      _update(s.copyWith(prefetchChapters: v.toInt())),
                ),
            ]),

          _Section(title: 'Voces', children: [
            _VoiceTile(
              label: 'Español',
              lang: 'es',
              settings: s,
              onPick: (id) => _update(s.ttsProvider == 'kokoro'
                  ? s.copyWith(kokoroVoiceEs: id)
                  : s.copyWith(edgeVoiceEs: id)),
              onPreview: _preview,
              previewing: _previewing,
            ),
            const SizedBox(height: 8),
            _VoiceTile(
              label: 'Inglés',
              lang: 'en',
              settings: s,
              onPick: (id) => _update(s.ttsProvider == 'kokoro'
                  ? s.copyWith(kokoroVoiceEn: id)
                  : s.copyWith(edgeVoiceEn: id)),
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

          _Section(title: 'Almacenamiento', children: [
            Text('Caché temporal: '
                '${(_cacheSizeKb / 1024).toStringAsFixed(1)} MB / ${s.cacheMaxMb} MB'),
            Text('Descargas: ${(_downloadsKb / 1024).toStringAsFixed(1)} MB',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            _LabelledSlider(
              label: 'Máximo caché',
              value: s.cacheMaxMb.toDouble(),
              min: 50,
              max: 500,
              divisions: 18,
              display: '${s.cacheMaxMb} MB',
              onChanged: (v) => _update(s.copyWith(cacheMaxMb: v.toInt())),
            ),
            const SizedBox(height: 4),
            Text(
              'La caché se llena sola al escuchar y el sistema la va reciclando. '
              'Las descargas son las que pediste tú y no se borran solas.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.delete_sweep_outlined),
                  label: const Text('Limpiar caché'),
                  onPressed: _clearCache,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.folder_delete_outlined),
                  label: const Text('Borrar descargas'),
                  onPressed: _downloadsKb > 0 ? _deleteDownloads : null,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Borrar todo'),
                  style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error),
                  onPressed: (_cacheSizeKb + _downloadsKb) > 0
                      ? _deleteEverything
                      : null,
                ),
              ],
            ),
          ]),

          if (_bookUsage.isNotEmpty)
            _Section(title: 'Este libro', children: [
              Text(
                ref.read(readerProvider).book?.title ?? '',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Cada motor guarda su propio audio, así que puedes liberar el de '
                'uno sin perder el de los demás.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final usage in _bookUsage)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(providerLabel(usage.engine)),
                  subtitle: Text(_usageLabel(usage),
                      style: Theme.of(context).textTheme.labelSmall),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Borrar el audio de ${providerLabel(usage.engine)}',
                    onPressed: () => _deleteBookEngine(usage),
                  ),
                ),
              TextButton.icon(
                icon: const Icon(Icons.delete_sweep_outlined),
                label: const Text('Borrar todo lo de este libro'),
                onPressed: () => _deleteBookEngine(null),
              ),
            ]),

          const SizedBox(height: 24),
          Center(
            child: Text(
              'Los cambios se guardan solos.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.5),
                  ),
            ),
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

  /// "1.25× · pausado". The number alone reads backwards for phoneme length.
  static String _paceLabel(double value) {
    final word = switch (value) {
      < 0.95 => 'rápido',
      < 1.1 => 'normal',
      < 1.35 => 'pausado',
      _ => 'muy pausado',
    };
    return '${value.toStringAsFixed(2)}× · $word';
  }

  /// Warns once when the Piper pace moves away from what was downloaded.
  Future<void> _warnPaceInvalidates(double value) async {
    final downloaded = await _cacheRepo.countPinnedByKey(prefix: 'piper-');
    if (!mounted || downloaded == 0) return;

    // The pace closes the key ('piper-<voice>-1_25'), it does not open it. The
    // warning used to look for it as a prefix, never found it, and so fired at
    // every nudge of the slider — including a nudge back to the value the
    // downloads were made at.
    final atThisPace = await _cacheRepo.countPinnedByKey(
      prefix: 'piper-',
      suffix: ReaderNotifier.piperPaceSuffix(value),
    );
    if (!mounted || atThisPace > 0) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 6),
      content: Text('Con este ritmo no se usarán los $downloaded párrafos ya '
          'descargados: el ritmo va grabado en el audio.'),
    ));
  }

  /// Wipes the temporary cache only. Handy after switching engines: audio
  /// cached under one engine is what made comparisons misleading.
  Future<void> _clearCache() async {
    await _cacheRepo.clearAll();
    await _loadCacheSize();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Caché limpiada. Las descargas se conservan.'),
    ));
  }

  static String _usageLabel(BookEngineUsage u) {
    final parts = <String>[];
    if (u.downloadsKb > 0) {
      parts.add('${(u.downloadsKb / 1024).toStringAsFixed(1)} MB descargados');
    }
    if (u.cacheKb > 0) {
      parts.add('${(u.cacheKb / 1024).toStringAsFixed(1)} MB en caché');
    }
    parts.add('${u.items} párrafos');
    return parts.join(' · ');
  }

  /// Frees one engine's audio for the open book, or all of it when [usage] is
  /// null. Downloads are involved, so it confirms first.
  Future<void> _deleteBookEngine(BookEngineUsage? usage) async {
    final book = ref.read(readerProvider).book;
    if (book?.id == null) return;

    final label =
        usage == null ? 'todo el audio de este libro' : providerLabel(usage.engine);
    final mb = usage == null
        ? _bookUsage.fold<int>(0, (sum, u) => sum + u.totalKb) / 1024
        : usage.totalKb / 1024;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Borrar $label'),
        content: Text('Se liberarán ${mb.toStringAsFixed(1)} MB de '
            '"${book!.title}". Lo que estuviera descargado habrá que volver a '
            'generarlo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;

    await _cacheRepo.deleteForBook(book!.id!, engine: usage?.engine);
    await _loadCacheSize();
  }

  /// Everything, every book. The nuclear option.
  Future<void> _deleteEverything() async {
    final mb = ((_cacheSizeKb + _downloadsKb) / 1024).toStringAsFixed(1);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar todo el audio'),
        content: Text('Se eliminarán $mb MB de todos los libros y todos los '
            'motores, incluidas las descargas para escuchar sin conexión.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Borrar todo')),
        ],
      ),
    );
    if (ok != true) return;

    await _cacheRepo.deleteEverything();
    await _loadCacheSize();
  }

  /// Downloads cost hours of synthesis, so this one asks first.
  Future<void> _deleteDownloads() async {
    final mb = (_downloadsKb / 1024).toStringAsFixed(1);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Borrar descargas'),
        content: Text('Se eliminarán $mb MB de audio descargado para escuchar '
            'sin conexión. Volver a generarlo puede llevar horas.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;

    await _cacheRepo.deleteDownloads();
    await _loadCacheSize();
  }

  /// Synthesizes a short line and actually plays it. The previous version
  /// generated the file and threw it away, so the button was silent.
  Future<void> _preview(String voiceId, String lang) async {
    if (_previewing != null) return;
    setState(() => _previewing = voiceId);

    final s = _settings;
    // Language matters for Kokoro: without it the preview would mispronounce.
    final tts = getProvider(s, lang: lang);
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
        settings: settings,
        lang: lang,
        current: current,
        onPreview: (id) => onPreview(id, lang),
      ),
    );
    if (picked != null) onPick(picked);
  }
}

class _VoicePickerSheet extends ConsumerStatefulWidget {
  final AppSettings settings;
  final String lang;
  final String current;
  final Future<void> Function(String voiceId) onPreview;

  const _VoicePickerSheet({
    required this.settings,
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
    final async = ref.watch(voicesProvider(widget.settings));

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
  final ValueChanged<double>? onChangeEnd;

  const _LabelledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.onChangeEnd,
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
              onChangeEnd: onChangeEnd,
            ),
          ),
          SizedBox(
            width: 108,
            child: Text(display,
                textAlign: TextAlign.end,
                maxLines: 2,
                style: const TextStyle(fontSize: 12)),
          ),
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
