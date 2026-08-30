import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

/// One sense of a word.
typedef Definition = ({String partOfSpeech, String meaning, String? example});

/// What a lookup produced, including why it produced nothing.
class DictionaryEntry {
  final String word;
  final String? phonetic;
  final List<Definition> definitions;
  final String? error;

  const DictionaryEntry({
    required this.word,
    this.phonetic,
    this.definitions = const [],
    this.error,
  });

  bool get isEmpty => definitions.isEmpty;
}

/// English definitions from dictionaryapi.dev — free and keyless, which is why
/// it was chosen over bundling a dictionary that would bloat the APK.
///
/// **Requires connectivity.** This is the one feature that cannot work offline;
/// callers should offer the pronounce button and a hand-off to another app as
/// the fallback.
class DictionaryService {
  static const _base = 'https://api.dictionaryapi.dev/api/v2/entries/en';

  /// Small in-memory cache: re-tapping the same word while reading is common.
  static final Map<String, DictionaryEntry> _cache = {};

  static Future<DictionaryEntry> lookup(String rawWord) async {
    final word = _normalise(rawWord);
    if (word.isEmpty) {
      return const DictionaryEntry(word: '', error: 'Palabra vacía');
    }

    final cached = _cache[word];
    if (cached != null) return cached;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse('$_base/$word'));
      final resp = await req.close().timeout(const Duration(seconds: 8));

      if (resp.statusCode == 404) {
        await resp.drain<void>();
        final miss = DictionaryEntry(
            word: word, error: 'Sin resultados para "$word".');
        _cache[word] = miss;
        return miss;
      }
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return DictionaryEntry(
            word: word, error: 'El diccionario respondió ${resp.statusCode}.');
      }

      final body = await resp.transform(utf8.decoder).join();
      final entry = _parse(word, jsonDecode(body));
      _cache[word] = entry;
      return entry;
    } on SocketException {
      return DictionaryEntry(
          word: word,
          error: 'Sin conexión. El diccionario necesita internet.');
    } catch (e) {
      dev.log('[Dictionary] lookup failed: $e');
      return DictionaryEntry(word: word, error: 'No se pudo consultar: $e');
    } finally {
      client.close(force: true);
    }
  }

  static DictionaryEntry _parse(String word, Object? json) {
    if (json is! List || json.isEmpty) {
      return DictionaryEntry(word: word, error: 'Respuesta inesperada.');
    }

    final first = json.first as Map<String, dynamic>;
    final definitions = <Definition>[];

    for (final entry in json.whereType<Map<String, dynamic>>()) {
      final meanings =
          (entry['meanings'] as List?)?.whereType<Map<String, dynamic>>() ??
              const <Map<String, dynamic>>[];
      for (final meaning in meanings) {
        final pos = meaning['partOfSpeech'] as String? ?? '';
        final senses = (meaning['definitions'] as List?)
                ?.whereType<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
        for (final d in senses) {
          final text = d['definition'] as String?;
          if (text == null || text.isEmpty) continue;
          definitions.add((
            partOfSpeech: pos,
            meaning: text,
            example: d['example'] as String?,
          ));
          // Half a dozen senses is already more than anyone reads in a sheet.
          if (definitions.length >= 6) break;
        }
        if (definitions.length >= 6) break;
      }
      if (definitions.length >= 6) break;
    }

    return DictionaryEntry(
      word: first['word'] as String? ?? word,
      phonetic: _phonetic(first),
      definitions: definitions,
      error: definitions.isEmpty ? 'Sin definiciones disponibles.' : null,
    );
  }

  static String? _phonetic(Map<String, dynamic> entry) {
    final direct = entry['phonetic'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;
    final list = (entry['phonetics'] as List?)
            ?.whereType<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    for (final p in list) {
      final text = p['text'] as String?;
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  /// Strips the punctuation the text aligner keeps attached to words, so
  /// "aquello." and "—No" become lookup-able.
  static String _normalise(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'''^[^\p{L}]+|[^\p{L}]+$''', unicode: true), '')
      .trim();
}
