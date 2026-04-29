class WordTimestamp {
  final String word;
  final int offsetMs;
  final int durationMs;
  WordTimestamp(
      {required this.word, required this.offsetMs, required this.durationMs});
}

class TTSResult {
  final String filePath;
  final List<WordTimestamp> timestamps;
  TTSResult({required this.filePath, required this.timestamps});
}

class Voice {
  final String id;
  final String name;
  final String locale;
  final String gender;
  Voice(
      {required this.id,
      required this.name,
      required this.locale,
      required this.gender});
}
