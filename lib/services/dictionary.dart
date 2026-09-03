import 'dart:async';
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

  /// True when the lookup failed for a reason that may not repeat — a timeout,
  /// a dropped connection, a server having a bad minute.
  ///
  /// It exists to keep such failures **out of the cache**. Caching them meant a
  /// word that failed once kept failing for the rest of the session, long after
  /// the network had recovered, and re-tapping it changed nothing. "No results"
  /// is a different animal: that answer is stable and worth remembering.
  final bool retryable;

  const DictionaryEntry({
    required this.word,
    this.phonetic,
    this.definitions = const [],
    this.error,
    this.retryable = false,
  });

  bool get isEmpty => definitions.isEmpty;
}

/// Word definitions, keyless and free in both languages the app reads.
///
/// Both languages now come from **Wiktionary's plain-text extract API**, the
/// same endpoint with a different host. English used to go through
/// dictionaryapi.dev, and that was the whole problem: measured on 2026-09-03,
/// six lookups took 0.10 s, 0.15 s, 19.4 s, 19.5 s, 19.8 s and one answered 522
/// — the code Cloudflare returns when the origin behind it never replies. With
/// an eight-second budget, timing out was the normal case, not the exception.
/// Wiktionary answered the same words in well under a second, and it also had
/// `waterbag`, which dictionaryapi.dev did not.
///
/// The extract is prose rather than structured data, so both parsers read it
/// heuristically. English asks for `exsectionformat=wiki`, which marks headings
/// as `== English ==` and `=== Noun ===`: the nesting level says outright which
/// section is a language and which a part of speech, so nothing has to be
/// guessed from a list of language names.
///
/// **Requires connectivity.** This is the one feature that cannot work offline;
/// callers should offer the pronounce button and a hand-off to another app as
/// the fallback.
class DictionaryService {
  static const _enBase = 'https://en.wiktionary.org/w/api.php';
  static const _esBase = 'https://es.wiktionary.org/w/api.php';

  static const _connect = Duration(seconds: 6);
  static const _headers = Duration(seconds: 8);

  /// Reading the body needs its own ceiling. Without one, a connection that
  /// degrades after the headers hangs with nothing to show for it.
  static const _body = Duration(seconds: 8);

  /// Small in-memory cache: re-tapping the same word while reading is common.
  static final Map<String, DictionaryEntry> _cache = {};

  /// Visible for testing.
  static void clearCache() => _cache.clear();

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

    // A transient failure must not become this word's permanent answer.
    if (!entry.retryable) _cache[key] = entry;
    return entry;
  }

  static Future<DictionaryEntry> _lookupEnglish(String word) =>
      _fetchExtract(word, _enBase, 'wiki', parseEnglishExtract);

  static Future<DictionaryEntry> _lookupSpanish(String word) =>
      _fetchExtract(word, _esBase, 'plain', parseSpanishExtract);

  /// Fetches the article extract and hands it to [parse].
  static Future<DictionaryEntry> _fetchExtract(
    String word,
    String base,
    String sectionFormat,
    DictionaryEntry Function(String title, String extract) parse,
  ) async {
    final client = HttpClient()..connectionTimeout = _connect;
    try {
      final uri = Uri.parse('$base?action=query&prop=extracts&explaintext=1'
          '&exsectionformat=$sectionFormat&redirects=1&format=json'
          // Encoded: accents and apostrophes are ordinary in both languages.
          '&titles=${Uri.encodeQueryComponent(word)}');
      final req = await client.getUrl(uri);
      final resp = await req.close().timeout(_headers);
      if (resp.statusCode != 200) {
        await resp.drain<void>();
        return DictionaryEntry(
          word: word,
          error: 'El diccionario respondió ${resp.statusCode}.',
          // 5xx is the server having a bad moment; 4xx is about this word.
          retryable: resp.statusCode >= 500,
        );
      }

      final body =
          await resp.transform(utf8.decoder).join().timeout(_body);
      final pages =
          (jsonDecode(body)['query']?['pages'] as Map<String, dynamic>?) ?? {};
      // '-1' is how the API says the article does not exist.
      if (pages.isEmpty || pages.containsKey('-1')) {
        return DictionaryEntry(
            word: word, error: 'Sin resultados para "$word".');
      }

      final page = pages.values.first as Map<String, dynamic>;
      return parse(page['title'] as String? ?? word,
          page['extract'] as String? ?? '');
    } on TimeoutException {
      return DictionaryEntry(
        word: word,
        error: 'El diccionario tardó demasiado en responder.',
        retryable: true,
      );
    } on SocketException {
      return DictionaryEntry(
        word: word,
        error: 'Sin conexión. El diccionario necesita internet.',
        retryable: true,
      );
    } catch (e) {
      // The detail goes to the log, not to the reader: a Dart exception with
      // microseconds in it says nothing to anybody.
      dev.log('[Dictionary] lookup of "$word" failed: $e');
      return DictionaryEntry(
        word: word,
        error: 'No se pudo consultar el diccionario.',
        retryable: true,
      );
    } finally {
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------- English

  static final _heading = RegExp(r'^(=+)\s*(.*?)\s*=+$');
  static final _ipa = RegExp(r'IPA\(key\):\s*(/[^/,;]+/)');

  /// Headings that introduce senses. Everything else — Etymology, Pronunciation,
  /// Translations, Derived terms — is scaffolding around them.
  static const _englishPos = {
    'noun', 'verb', 'adjective', 'adverb', 'pronoun', 'preposition',
    'conjunction', 'interjection', 'determiner', 'article', 'numeral',
    'particle', 'proper noun', 'phrase', 'proverb', 'prefix', 'suffix',
    'contraction', 'abbreviation', 'initialism', 'acronym', 'symbol', 'letter',
  };

  /// Cross-references Wiktionary hangs off a sense. They read like definitions
  /// and are not.
  static bool _isNote(String line) => const [
        'Synonym', 'Antonym', 'Coordinate term', 'Hypernym', 'Hyponym',
        'Meronym', 'Holonym', 'Troponym', 'See also', 'Usage notes',
      ].any((p) => line.startsWith('$p:') || line.startsWith('${p}s:'));

  /// Visible for testing.
  ///
  /// Only the `== English ==` section counts: the same spelling usually exists
  /// in a dozen other languages further down, and for `house` those sections
  /// are almost all about house music.
  static DictionaryEntry parseEnglishExtract(String word, String extract) {
    final definitions = <Definition>[];
    var inEnglish = false;
    var pos = '';
    var collecting = false;
    var atHeadword = false;
    String? phonetic;

    for (final raw in extract.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final title = heading.group(2)!;
        // Level 2 is a language. Reaching another one ends English.
        if (level <= 2) {
          if (inEnglish) break;
          inEnglish = title.toLowerCase() == 'english';
          continue;
        }
        if (!inEnglish) continue;
        collecting = _englishPos.contains(title.toLowerCase());
        // The line right after a part of speech is the headword with its
        // inflections -- "waterbag (plural waterbags)" -- not a sense.
        atHeadword = collecting;
        if (collecting) pos = title;
        continue;
      }

      if (!inEnglish) continue;
      phonetic ??= _ipa.firstMatch(line)?.group(1);
      if (!collecting) continue;
      if (atHeadword) {
        atHeadword = false;
        continue;
      }
      if (_isNote(line)) continue;

      definitions.add((partOfSpeech: pos, meaning: line, example: null));
      // Half a dozen senses is already more than anyone reads in a sheet.
      if (definitions.length >= 6) break;
    }

    return DictionaryEntry(
      word: word,
      phonetic: phonetic,
      definitions: definitions,
      error: definitions.isEmpty ? 'Sin definiciones disponibles.' : null,
    );
  }

  // ---------------------------------------------------------------- Spanish

  static final _numbered = RegExp(r'^\d+\s*(.*)$');
  static final _partOfSpeech = RegExp(
      r'^(Sustantivo|Verbo|Adjetivo|Adverbio|Pronombre|Preposición|'
      r'Conjunción|Interjección|Locución|Artículo|Forma)\b.*',
      caseSensitive: false);

  /// Visible for testing.
  ///
  /// The Spanish Wiktionary is asked for plain sections instead of wiki ones,
  /// so headings arrive unmarked: definitions are the lines following a
  /// numbered marker, and the part of speech is the heading above them. Only
  /// the "Español" section counts.
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

  /// Strips the punctuation the text aligner keeps attached to words, so
  /// "aquello." and "—No" become lookup-able.
  static String _normalise(String raw) => raw
      .toLowerCase()
      .replaceAll(RegExp(r'''^[^\p{L}]+|[^\p{L}]+$''', unicode: true), '')
      .trim();
}
