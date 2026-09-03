import 'package:shared_preferences/shared_preferences.dart';

/// Fallback voices used when the live Edge catalogue is unavailable or the user
/// has not picked a specific voice. Kept deliberately small — the full list
/// (300+ voices) comes from EdgeTtsProvider.listVoices().
const voiceMap = {
  'edge': {
    'es': {'female': 'es-MX-DaliaNeural', 'male': 'es-MX-JorgeNeural'},
    'en': {'female': 'en-US-JennyNeural', 'male': 'en-US-GuyNeural'},
  },
};

/// Engines the app can build. Anything else found in stored settings comes from
/// a version that offered more of them, and has to be brought back here.
const ttsEngines = ['edge', 'kokoro', 'piper'];

String resolveVoice(String provider, String lang, String gender) {
  return voiceMap[provider]?[lang]?[gender] ??
      voiceMap['edge']!['es']!['female']!;
}

/// Reader colour schemes. Kept as an enum-like string so it round-trips through
/// SharedPreferences without a migration.
const readerThemes = ['sepia', 'light', 'dark'];

/// Bundled reading fonts. 'system' uses the platform default.
const readerFonts = ['serif', 'sans', 'system'];

class AppSettings {
  String ttsProvider;
  String gender;

  /// Explicit Edge voice per language. Empty means "derive from gender via voiceMap".
  String edgeVoiceEs;
  String edgeVoiceEn;

  /// Applied at playback time (just_audio time-stretch), NOT baked into the audio.
  /// This keeps one cached file valid for every speed.
  double playbackSpeed;

  /// SSML prosody values. Held at neutral so cached audio stays speed-agnostic;
  /// exposed here only so an advanced user could still tweak them.
  String edgeRate;
  String edgeVolume;

  bool highlightSentences;
  bool highlightWords;

  // ── Kokoro (servidor propio en la red local) ─────────────────────────────
  /// Base URL of the self-hosted Kokoro-FastAPI, e.g. http://192.168.1.50:8880
  String kokoroBaseUrl;
  String kokoroVoiceEs;
  String kokoroVoiceEn;

  /// Download the next chapters ahead while on WiFi with the server reachable.
  bool prefetchOnWifi;
  int prefetchChapters;

  // ── Piper (servidor propio, voces nativas por idioma) ────────────────────
  String piperBaseUrl;

  /// Piper model per language. Its voices are trained one language each, so the
  /// server must be told which model to use: feeding English text to a Spanish
  /// model produces Spanish phonetics over English words — unintelligible.
  String piperVoiceEs;
  String piperVoiceEn;

  /// Phoneme length. Above 1.0 slows the voice; es_AR-daniela reads fast at 1.0.
  double piperLengthScale;
  String theme;
  int cacheMaxMb;

  // ── Reading (visual) settings ────────────────────────────────────────────
  double fontSize;
  double lineHeight;
  double margin;
  String readerFont;
  String readerTheme;
  bool followAudioScroll;

  AppSettings({
    this.ttsProvider = 'edge',
    this.gender = 'female',
    this.edgeVoiceEs = '',
    this.edgeVoiceEn = '',
    this.playbackSpeed = 1.0,
    this.edgeRate = '+0%',
    this.edgeVolume = '+0%',
    this.highlightSentences = true,
    this.highlightWords = true,
    this.kokoroBaseUrl = '',
    this.kokoroVoiceEs = 'af_bella',
    this.kokoroVoiceEn = 'af_bella',
    this.prefetchOnWifi = true,
    this.prefetchChapters = 3,
    this.piperBaseUrl = '',
    this.piperVoiceEs = 'es_AR-daniela-high',
    this.piperVoiceEn = 'en_US-lessac-high',
    this.piperLengthScale = 1.0,
    this.theme = 'dark',
    this.cacheMaxMb = 150,
    this.fontSize = 18,
    this.lineHeight = 1.7,
    this.margin = 24,
    this.readerFont = 'serif',
    this.readerTheme = 'sepia',
    this.followAudioScroll = true,
  });

  /// Voice id for [lang] under the engine currently selected.
  String voiceFor(String lang) => voiceForEngine(ttsProvider, lang);

  /// Voice id for [lang] under a specific [engine].
  ///
  /// Needed because the cache key names the engine that produced the audio,
  /// which is not always the selected one: a fallback to Edge must be keyed
  /// with Edge's voice, not with whatever Kokoro or Piper would have used.
  String voiceForEngine(String engine, String lang) {
    switch (engine) {
      case 'kokoro':
        final v = lang == 'es' ? kokoroVoiceEs : kokoroVoiceEn;
        return v.isNotEmpty ? v : 'af_bella';
      case 'piper':
        return lang == 'es' ? piperVoiceEs : piperVoiceEn;
      case 'edge':
        final explicit = lang == 'es' ? edgeVoiceEs : edgeVoiceEn;
        if (explicit.isNotEmpty) return explicit;
    }
    return resolveVoice(engine, lang, gender);
  }

  /// True when a Kokoro server has been configured at all.
  bool get hasKokoroServer => kokoroBaseUrl.trim().isNotEmpty;

  bool get hasPiperServer => piperBaseUrl.trim().isNotEmpty;

  /// Base URL of the self-hosted engine currently selected, if any.
  String get selfHostedUrl => switch (ttsProvider) {
        'kokoro' => kokoroBaseUrl,
        'piper' => piperBaseUrl,
        _ => '',
      };

  /// Whether the selected engine depends on a machine on the local network.
  bool get usesSelfHostedServer =>
      ttsProvider == 'kokoro' || ttsProvider == 'piper';

  /// Brings a stored engine name back to one the app still has.
  ///
  /// Android TTS was retired in 0.6.0. Left as-is, a phone that had it selected
  /// would boot with `ttsProvider = 'android'`: the factory would quietly hand
  /// back Edge, but the cache key and the status bar would keep claiming an
  /// engine that no longer exists.
  static String resolveEngine(String? stored) =>
      ttsEngines.contains(stored) ? stored! : 'edge';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      ttsProvider: resolveEngine(prefs.getString('ttsProvider')),
      gender: prefs.getString('gender') ?? 'female',
      edgeVoiceEs: prefs.getString('edgeVoiceEs') ?? '',
      edgeVoiceEn: prefs.getString('edgeVoiceEn') ?? '',
      // Migrates the old androidSpeed slider into the unified playback speed.
      playbackSpeed:
          prefs.getDouble('playbackSpeed') ?? prefs.getDouble('androidSpeed') ?? 1.0,
      edgeRate: prefs.getString('edgeRate') ?? '+0%',
      edgeVolume: prefs.getString('edgeVolume') ?? '+0%',
      highlightSentences: prefs.getBool('highlightSentences') ?? true,
      highlightWords: prefs.getBool('highlightWords') ?? true,
      kokoroBaseUrl: prefs.getString('kokoroBaseUrl') ?? '',
      kokoroVoiceEs: prefs.getString('kokoroVoiceEs') ?? 'af_bella',
      kokoroVoiceEn: prefs.getString('kokoroVoiceEn') ?? 'af_bella',
      prefetchOnWifi: prefs.getBool('prefetchOnWifi') ?? true,
      prefetchChapters: prefs.getInt('prefetchChapters') ?? 3,
      piperBaseUrl: prefs.getString('piperBaseUrl') ?? '',
      piperVoiceEs: prefs.getString('piperVoiceEs') ?? 'es_AR-daniela-high',
      piperVoiceEn: prefs.getString('piperVoiceEn') ?? 'en_US-lessac-high',
      piperLengthScale: prefs.getDouble('piperLengthScale') ?? 1.0,
      theme: prefs.getString('theme') ?? 'dark',
      cacheMaxMb: prefs.getInt('cacheMaxMb') ?? 150,
      fontSize: prefs.getDouble('fontSize') ?? 18,
      lineHeight: prefs.getDouble('lineHeight') ?? 1.7,
      margin: prefs.getDouble('margin') ?? 24,
      readerFont: prefs.getString('readerFont') ?? 'serif',
      readerTheme: prefs.getString('readerTheme') ?? 'sepia',
      followAudioScroll: prefs.getBool('followAudioScroll') ?? true,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ttsProvider', ttsProvider);
    await prefs.setString('gender', gender);
    await prefs.setString('edgeVoiceEs', edgeVoiceEs);
    await prefs.setString('edgeVoiceEn', edgeVoiceEn);
    await prefs.setDouble('playbackSpeed', playbackSpeed);
    await prefs.setString('edgeRate', edgeRate);
    await prefs.setString('edgeVolume', edgeVolume);
    await prefs.setBool('highlightSentences', highlightSentences);
    await prefs.setBool('highlightWords', highlightWords);
    await prefs.setString('kokoroBaseUrl', kokoroBaseUrl);
    await prefs.setString('kokoroVoiceEs', kokoroVoiceEs);
    await prefs.setString('kokoroVoiceEn', kokoroVoiceEn);
    await prefs.setBool('prefetchOnWifi', prefetchOnWifi);
    await prefs.setInt('prefetchChapters', prefetchChapters);
    await prefs.setString('piperBaseUrl', piperBaseUrl);
    await prefs.setString('piperVoiceEs', piperVoiceEs);
    await prefs.setString('piperVoiceEn', piperVoiceEn);
    await prefs.setDouble('piperLengthScale', piperLengthScale);
    await prefs.setString('theme', theme);
    await prefs.setInt('cacheMaxMb', cacheMaxMb);
    await prefs.setDouble('fontSize', fontSize);
    await prefs.setDouble('lineHeight', lineHeight);
    await prefs.setDouble('margin', margin);
    await prefs.setString('readerFont', readerFont);
    await prefs.setString('readerTheme', readerTheme);
    await prefs.setBool('followAudioScroll', followAudioScroll);
  }

  AppSettings copyWith({
    String? ttsProvider,
    String? gender,
    String? edgeVoiceEs,
    String? edgeVoiceEn,
    double? playbackSpeed,
    String? edgeRate,
    String? edgeVolume,
    bool? highlightSentences,
    bool? highlightWords,
    String? kokoroBaseUrl,
    String? kokoroVoiceEs,
    String? kokoroVoiceEn,
    bool? prefetchOnWifi,
    int? prefetchChapters,
    String? piperBaseUrl,
    String? piperVoiceEs,
    String? piperVoiceEn,
    double? piperLengthScale,
    String? theme,
    int? cacheMaxMb,
    double? fontSize,
    double? lineHeight,
    double? margin,
    String? readerFont,
    String? readerTheme,
    bool? followAudioScroll,
  }) =>
      AppSettings(
        ttsProvider: ttsProvider ?? this.ttsProvider,
        gender: gender ?? this.gender,
        edgeVoiceEs: edgeVoiceEs ?? this.edgeVoiceEs,
        edgeVoiceEn: edgeVoiceEn ?? this.edgeVoiceEn,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
        edgeRate: edgeRate ?? this.edgeRate,
        edgeVolume: edgeVolume ?? this.edgeVolume,
        highlightSentences: highlightSentences ?? this.highlightSentences,
        highlightWords: highlightWords ?? this.highlightWords,
        kokoroBaseUrl: kokoroBaseUrl ?? this.kokoroBaseUrl,
        kokoroVoiceEs: kokoroVoiceEs ?? this.kokoroVoiceEs,
        kokoroVoiceEn: kokoroVoiceEn ?? this.kokoroVoiceEn,
        prefetchOnWifi: prefetchOnWifi ?? this.prefetchOnWifi,
        prefetchChapters: prefetchChapters ?? this.prefetchChapters,
        piperBaseUrl: piperBaseUrl ?? this.piperBaseUrl,
        piperVoiceEs: piperVoiceEs ?? this.piperVoiceEs,
        piperVoiceEn: piperVoiceEn ?? this.piperVoiceEn,
        piperLengthScale: piperLengthScale ?? this.piperLengthScale,
        theme: theme ?? this.theme,
        cacheMaxMb: cacheMaxMb ?? this.cacheMaxMb,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        margin: margin ?? this.margin,
        readerFont: readerFont ?? this.readerFont,
        readerTheme: readerTheme ?? this.readerTheme,
        followAudioScroll: followAudioScroll ?? this.followAudioScroll,
      );
}
