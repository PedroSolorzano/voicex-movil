import 'package:shared_preferences/shared_preferences.dart';

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

class AppSettings {
  String ttsProvider;
  String gender;
  String edgeRate;
  String edgeVolume;
  double androidSpeed;
  bool highlightSentences;
  String theme;
  int cacheMaxMb;

  AppSettings({
    this.ttsProvider = 'edge',
    this.gender = 'female',
    this.edgeRate = '+0%',
    this.edgeVolume = '+0%',
    this.androidSpeed = 1.0,
    this.highlightSentences = true,
    this.theme = 'dark',
    this.cacheMaxMb = 150,
  });

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      ttsProvider: prefs.getString('ttsProvider') ?? 'edge',
      gender: prefs.getString('gender') ?? 'female',
      edgeRate: prefs.getString('edgeRate') ?? '+0%',
      edgeVolume: prefs.getString('edgeVolume') ?? '+0%',
      androidSpeed: prefs.getDouble('androidSpeed') ?? 1.0,
      highlightSentences: prefs.getBool('highlightSentences') ?? true,
      theme: prefs.getString('theme') ?? 'dark',
      cacheMaxMb: prefs.getInt('cacheMaxMb') ?? 150,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ttsProvider', ttsProvider);
    await prefs.setString('gender', gender);
    await prefs.setString('edgeRate', edgeRate);
    await prefs.setString('edgeVolume', edgeVolume);
    await prefs.setDouble('androidSpeed', androidSpeed);
    await prefs.setBool('highlightSentences', highlightSentences);
    await prefs.setString('theme', theme);
    await prefs.setInt('cacheMaxMb', cacheMaxMb);
  }

  AppSettings copyWith({
    String? ttsProvider,
    String? gender,
    String? edgeRate,
    String? edgeVolume,
    double? androidSpeed,
    bool? highlightSentences,
    String? theme,
    int? cacheMaxMb,
  }) =>
      AppSettings(
        ttsProvider: ttsProvider ?? this.ttsProvider,
        gender: gender ?? this.gender,
        edgeRate: edgeRate ?? this.edgeRate,
        edgeVolume: edgeVolume ?? this.edgeVolume,
        androidSpeed: androidSpeed ?? this.androidSpeed,
        highlightSentences: highlightSentences ?? this.highlightSentences,
        theme: theme ?? this.theme,
        cacheMaxMb: cacheMaxMb ?? this.cacheMaxMb,
      );
}
