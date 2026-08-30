import 'package:shared_preferences/shared_preferences.dart';

/// Fallback voices used when the live Edge catalogue is unavailable or the user
/// has not picked a specific voice. Kept deliberately small — the full list
/// (300+ voices) comes from EdgeTtsProvider.listVoices().
const voiceMap = {
  'edge': {
    'es': {'female': 'es-MX-DaliaNeural', 'male': 'es-MX-JorgeNeural'},
    'en': {'female': 'en-US-JennyNeural', 'male': 'en-US-GuyNeural'},
  },
  'android': {
    'es': {'female': 'es-ES', 'male': 'es-ES'},
    'en': {'female': 'en-US', 'male': 'en-US'},
  },
};

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
    this.theme = 'dark',
    this.cacheMaxMb = 150,
    this.fontSize = 18,
    this.lineHeight = 1.7,
    this.margin = 24,
    this.readerFont = 'serif',
    this.readerTheme = 'sepia',
    this.followAudioScroll = true,
  });

  /// Voice id for [lang], honouring an explicit choice before the gender map.
  String voiceFor(String lang) {
    if (ttsProvider == 'edge') {
      final explicit = lang == 'es' ? edgeVoiceEs : edgeVoiceEn;
      if (explicit.isNotEmpty) return explicit;
    }
    return resolveVoice(ttsProvider, lang, gender);
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      ttsProvider: prefs.getString('ttsProvider') ?? 'edge',
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
