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

/// Word definitions, keyless and free in both languages the app reads.
///
/// - English: dictionaryapi.dev.
/// - Spanish: the Spanish Wiktionary. Its REST `/page/definition` endpoint
///   answers 501, and the English Wiktionary only glosses Spanish words *in
///   English*, so the plain-text extract API is what actually works.
///
/// **Requires connectivity.** This is the one feature that cannot work offline;
/// callers should offer the pronounce button and a hand-off to another app as
/// the fallback.
class DictionaryService {
  static const _base = 'https://api.dictionaryapi.dev/api/v2/entries/en';
  static const _esBase = 'https://es.wiktionary.org/w/api.php';

  /// Small in-memory cache: re-tapping the same word while reading is common.
  static final Map<String, DictionaryEntry> _cache = {};

  /// Looks [rawWord] up in the dictionary matching [language] ('es' / 'en').
  static Future<DictionaryEntry> lookup(String rawWord,
      {String language = 'en'}) async {
    final word = _normalise(rawWord);
    if (word.isEmpty) {
      return const DictionaryEntry(word: '', error: 'Palabra vacía');
    }

    final key = '$language:$word';
    final cached = _cache[key];
    if (cached != null) return cached;

    final entry = language == 'es'
        ? await _lookupSpanish(word)
        : await _lookupEnglish(word);
    _cache[key] = entry;
    return entry;
  }

  static Future<DictionaryEntry> _lookupEnglish(String word) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse('$_base/$word'));
      final resp = await req.close().timeout(const Duration(seconds: 8));

      if (resp.statusCode == 404) {
        await resp.drain<void>();
        return DictionaryEntry(
            word: word, error: 'Sin resultados para "$word".');
      }
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return DictionaryEntry(
            word: word, error: 'El diccionario respondió ${resp.statusCode}.');
      }

      final body = await resp.transform(utf8.decoder).join();
      return _parse(word, jsonDecode(body));
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

  /// Spanish Wiktionary, via the plain-text extract of the article.
  ///
  /// The extract is prose, not structured data, so it is read heuristically:
  /// definitions are the lines following a numbered marker, and the part of
  /// speech is the heading above them. Only the "Español" section counts —
  /// the same spelling often exists in other languages further down.
  static Future<DictionaryEntry> _lookupSpanish(String word) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri.parse('$_esBase?action=query&prop=extracts&explaintext=1'
          '&exsectionformat=plain&redirects=1&format=json&titles=$word');
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return DictionaryEntry(
            word: word, error: 'El diccionario respondió ${resp.statusCode}.');
      }

      final body = await resp.transform(utf8.decoder).join();
      final pages =
          (jsonDecode(body)['query']?['pages'] as Map<String, dynamic>?) ?? {};
      if (pages.isEmpty || pages.containsKey('-1')) {
        return DictionaryEntry(
            word: word, error: 'Sin resultados para "$word".');
      }

      final page = pages.values.first as Map<String, dynamic>;
      final extract = page['extract'] as String? ?? '';
      return parseSpanishExtract(
          page['title'] as String? ?? word, extract);
    } on SocketException {
      return DictionaryEntry(
          word: word,
          error: 'Sin conexión. El diccionario necesita internet.');
    } catch (e) {
      dev.log('[Dictionary] Spanish lookup failed: $e');
      return DictionaryEntry(word: word, error: 'No se pudo consultar: $e');
    } finally {
      client.close(force: true);
    }
  }

  static final _numbered = RegExp(r'^\d+\s*(.*)$');
  static final _partOfSpeech = RegExp(
      r'^(Sustantivo|Verbo|Adjetivo|Adverbio|Pronombre|Preposición|'
      r'Conjunción|Interjección|Locución|Artículo|Forma)\b.*',
      caseSensitive: false);

  /// Visible for testing.
  static DictionaryEntry parseSpanishExtract(String word, String extract) {
    final lines = extract
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    final definitions = <Definition>[];
    var inSpanish = false;
    var pos = '';
    var expecting = false;

    for (final line in lines) {
      // Sections are language names; anything after "Español" belongs to
      // another language and must not be mixed in.
      if (line == 'Español') {
        inSpanish = true;
        continue;
      }
      if (inSpanish && _isLanguageHeading(line)) break;
      if (!inSpanish) continue;

      if (_partOfSpeech.hasMatch(line)) {
        pos = line;
        continue;
      }
      // Skip the notes Wiktionary hangs off each sense.
      if (line.startsWith('Uso:') ||
          line.startsWith('Sinónimos:') ||
          line.startsWith('Antónimos:') ||
          line.startsWith('Ejemplo')) {
        continue;
      }

      final numbered = _numbered.firstMatch(line);
      if (numbered != null) {
        final inline = numbered.group(1)?.trim() ?? '';
        // "1 Vivienda" is a semantic field, with the definition on the next
        // line; a long inline text is the definition itself.
        if (inline.length > 25) {
          definitions.add((partOfSpeech: pos, meaning: inline, example: null));
          expecting = false;
        } else {
          expecting = true;
        }
        continue;
      }

      if (expecting) {
        definitions.add((partOfSpeech: pos, meaning: line, example: null));
        expecting = false;
      }
      if (definitions.length >= 6) break;
    }

    return DictionaryEntry(
      word: word,
      definitions: definitions,
      error: definitions.isEmpty ? 'Sin definiciones disponibles.' : null,
    );
  }

  /// Wiktionary headings that start another language's section.
  static bool _isLanguageHeading(String line) => const {
        'Inglés', 'Francés', 'Portugués', 'Italiano', 'Catalán', 'Gallego',
        'Latín', 'Alemán', 'Asturiano', 'Aragonés', 'Euskera', 'Rumano',
      }.contains(line);

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
