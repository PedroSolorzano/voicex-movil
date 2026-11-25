// Generates the audio of whole chapters on this Mac, to carry to the phone by
// cable instead of downloading it over the network while reading.
//
//   dart run tools/audios/bajar.dart <libro.epub> <capítulos> [opciones]
//
// It uses the app's own EPUB parser, so paragraph N here is paragraph N on the
// phone, and writes the files with a manifest that the app's "Importar audios
// del Mac" reads. See tools/audios/README.md.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:voicex_movil/epub/parser.dart';

const _defaultVoices = {'qwen3': 'esposa', 'chatterbox2': 'colombiana'};

// Measured on 361 real paragraphs of Chatterbox on this Mac: the voice speaks
// ~17.7 characters per second at the standard speed, and the server makes audio
// ~1.8x faster than it plays. Estimates, good to plan an evening, not a clock.
const _charsPerSecond = 17.5;
const _generationSpeed = 1.7;

/// A chapter longer than this is suggested in parts.
const _comfortableHours = 1.5;

double _hours(int chars) => chars / _charsPerSecond / 3600;

String _fmtHours(double h) {
  if (h < 1) return '${(h * 60).round()} min';
  final whole = h.floor();
  final min = ((h - whole) * 60).round();
  return min == 0 ? '$whole h' : '$whole h $min min';
}

/// Cuts a chapter into parts of about [targetHours], on paragraph borders.
/// Returns the first paragraph of each part.
List<int> _partStarts(List<int> paragraphChars, double targetHours) {
  final total = _hours(paragraphChars.fold(0, (a, b) => a + b));
  final parts = (total / targetHours).ceil().clamp(1, 99);
  final perPart = total / parts;
  final starts = [0];
  var acc = 0.0;
  for (var i = 0; i < paragraphChars.length; i++) {
    acc += _hours(paragraphChars[i]);
    if (acc >= perPart * starts.length && i + 1 < paragraphChars.length &&
        starts.length < parts) {
      starts.add(i + 1);
    }
  }
  return starts;
}

/// Must match `_cacheFormatTag` in lib/ui/providers/reader_provider.dart.
const _formatTag = 'f96';

Future<void> main(List<String> args) async {
  if (args.isEmpty ||
      (args.length < 2 && !args.contains('--lista')) ||
      args.contains('--ayuda')) {
    stderr.writeln('''
Uso: dart run tools/audios/bajar.dart <libro.epub> <capítulos> [opciones]

  <capítulos>        números como los ve la app (1 = primer capítulo): 3, 3-5, 1,4
  --motor <id>       chatterbox2 (por defecto) o qwen3
  --voz <nombre>     voz del servidor (por defecto: colombiana / esposa)
  --desde <n>        en el primer capítulo, empezar en el párrafo n (como en la app)
  --horas <h>        parar tras ~h horas de escucha (1, 1.5…) y decir cómo seguir
  --servidor <url>   por defecto http://127.0.0.1:8765
  --salida <carpeta> por defecto tools/audios/salida
  --inventario <f>   inventario del teléfono; por defecto inventario.json junto al EPUB
  --sin-inventario   generar todo lo pedido aunque el teléfono ya lo tenga
  --lista            capítulos con horas de escucha y tiempo de generación, y cómo
                     partir los largos; no genera nada
''');
    exit(args.contains('--ayuda') ? 0 : 64);
  }

  String? opt(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final epubPath = args[0];
  final book = await parseEpub(epubPath);
  final hash =
      (await sha256.bind(File(epubPath).openRead()).first).toString();

  // What the phone already has, from the inventory the app writes with
  // "Dejar mis libros listos para el Mac". Next to the EPUB by default.
  final listEngine = opt('--motor') ?? 'chatterbox2';
  final listVoice = opt('--voz') ?? _defaultVoices[listEngine];
  final phone = args.contains('--sin-inventario') || listVoice == null
      ? null
      : _loadPhone(
          opt('--inventario') ?? '${File(epubPath).parent.path}/inventario.json',
          hash,
          '$listEngine-$listVoice');
  if (phone != null) {
    stdout.writeln('Inventario del teléfono: ${phone.when} '
        '(${phone.total} párrafos de este libro con esta voz). Si descargaste '
        'algo desde entonces, repite «Dejar mis libros listos» y traer-libros.sh.');
  } else if (!args.contains('--sin-inventario')) {
    stdout.writeln('Sin inventario del teléfono: se generará todo lo pedido. '
        'Para saltar lo que ya tiene, usa «Dejar mis libros listos para el '
        'Mac» y tools/audios/traer-libros.sh.');
  }

  if (args.contains('--lista')) {
    stdout.writeln('${book.title} — ${book.author} (${book.language})');
    stdout.writeln('Escucha a velocidad estándar; generar toma ~'
        '${(60 / _generationSpeed).round()} min por cada hora de audio.\n');
    for (final c in book.chapters) {
      final chars = c.paragraphs.map((p) => p.rawText.length).toList();
      final h = _hours(chars.fold(0, (a, b) => a + b));
      final here = phone?.have[c.index]?.length ?? 0;
      stdout.writeln('${(c.index + 1).toString().padLeft(3)}  '
          '${c.paragraphs.length.toString().padLeft(5)} párr.  '
          '${_fmtHours(h).padLeft(9)} de audio  '
          '(generar ~${_fmtHours(h / _generationSpeed)})  ${c.title}'
          '${here > 0 ? '  · en el teléfono: $here/${c.paragraphs.length}' : ''}');
      if (h > _comfortableHours) {
        final starts = _partStarts(chars, _comfortableHours);
        final n = starts.length;
        stdout.writeln('       largo: mejor en $n partes de ~'
            '${_fmtHours(h / n)}. Por ejemplo, la primera:');
        stdout.writeln('       dart run tools/audios/bajar.dart <libro.epub> '
            '${c.index + 1} --horas ${(h / n).toStringAsFixed(1)}');
      }
    }
    return;
  }

  final engine = opt('--motor') ?? 'chatterbox2';
  final voice = opt('--voz') ?? _defaultVoices[engine];
  if (voice == null) {
    stderr.writeln('Motor desconocido: $engine (usa chatterbox2 o qwen3)');
    exit(64);
  }
  if (!book.language.toLowerCase().startsWith('es')) {
    stderr.writeln('Este libro no está en español (${book.language}): la app '
        'lo lee con Edge, no con $engine, y no encontraría este audio.');
    exit(64);
  }

  final wanted = _parseChapters(args[1], book.chapters.length);
  final skipUntil = int.tryParse(opt('--desde') ?? '') ?? 0;
  final hoursBudget = double.tryParse(opt('--horas') ?? '');
  if (opt('--horas') != null && (hoursBudget == null || hoursBudget <= 0)) {
    stderr.writeln('--horas espera un número mayor que 0 (ejemplo: 1.5).');
    exit(64);
  }
  var budgetChars =
      hoursBudget == null ? null : (hoursBudget * 3600 * _charsPerSecond).round();
  ({int chapter, int paragraph})? stoppedAt;
  final server = (opt('--servidor') ?? 'http://127.0.0.1:8765')
      .replaceAll(RegExp(r'/+$'), '');
  final token = _token();

  // Plain ASCII: the folder name travels through adb into Android/data.
  const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
  final slug = book.title
      .toLowerCase()
      .split('')
      .map((c) => accents[c] ?? c)
      .join()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final root = Directory(
      '${opt('--salida') ?? 'tools/audios/salida'}/${slug.isEmpty ? 'libro' : slug}')
    ..createSync(recursive: true);

  // The manifest accumulates across runs: chapter 1 today, chapter 2 tomorrow,
  // one folder to push.
  final manifestFile = File('${root.path}/manifest.json');
  final manifest = manifestFile.existsSync()
      ? jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>
      : <String, dynamic>{};
  final items = <String, Map<String, dynamic>>{
    for (final i in (manifest['items'] as List? ?? const []))
      '${i['chapter']}:${i['paragraph']}:${manifest['voiceId']}':
          (i as Map).cast<String, dynamic>(),
  };
  final voiceId = '$engine-$voice';
  if (manifest['voiceId'] != null && manifest['voiceId'] != voiceId) {
    stderr.writeln('La carpeta ${root.path} ya tiene audio de '
        '${manifest['voiceId']}; para cambiar de voz usa otra --salida.');
    exit(64);
  }

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 30);
  var made = 0, reused = 0, failed = 0, onPhone = 0;
  final started = DateTime.now();

  Future<void> save() async {
    final list = items.values.toList()
      ..sort((a, b) {
        final c = (a['chapter'] as int).compareTo(b['chapter'] as int);
        return c != 0 ? c : (a['paragraph'] as int).compareTo(b['paragraph'] as int);
      });
    manifestFile.writeAsStringSync(const JsonEncoder.withIndent(' ').convert({
      'version': 1,
      'contentHash': hash,
      'title': book.title,
      'author': book.author,
      'voiceId': voiceId,
      'format': _formatTag,
      'items': list,
    }));
  }

  for (final chapterNumber in wanted) {
    final chapter = book.chapters[chapterNumber - 1];
    final first = chapterNumber == wanted.first ? skipUntil : 0;
    bool onThePhone(int paragraph) =>
        phone?.have[chapter.index]?.contains(paragraph) ?? false;
    final toDo = chapter.paragraphs
        .where((p) => p.index >= first && !onThePhone(p.index))
        .toList();
    final pending = toDo.fold<int>(0, (a, p) => a + p.rawText.length);
    stdout.writeln('\n[$chapterNumber] ${chapter.title} — '
        '${toDo.length} párrafos por generar'
        '${phone == null ? '' : ' (el teléfono ya tiene ${chapter.paragraphs.length - first - toDo.length})'}, '
        '~${_fmtHours(_hours(pending))} '
        'de audio (generar ~${_fmtHours(_hours(pending) / _generationSpeed)})');
    for (final para in chapter.paragraphs) {
      if (para.index < first) continue;
      // Already on the phone: nothing to generate, and it costs no budget.
      if (onThePhone(para.index)) {
        onPhone++;
        continue;
      }
      if (budgetChars != null && budgetChars <= 0) {
        stoppedAt = (chapter: chapterNumber, paragraph: para.index);
        break;
      }
      budgetChars = budgetChars == null ? null : budgetChars - para.rawText.length;
      final name = 'c${chapter.index}_p${para.index}.mp3';
      final file = File('${root.path}/$name');
      final key = '${chapter.index}:${para.index}:$voiceId';
      if (items.containsKey(key) && file.existsSync() && file.lengthSync() > 0) {
        reused++;
        continue;
      }
      try {
        final audio = await _synthesize(
            client, server, token, para.rawText, voice, engine);
        file.writeAsBytesSync(audio);
        items[key] = {
          'chapter': chapter.index,
          'paragraph': para.index,
          'file': name,
        };
        made++;
        if (made % 5 == 0) await save();
        final secs = DateTime.now().difference(started).inSeconds;
        stdout.write('\r  ${para.index + 1}/${chapter.paragraphs.length}'
            '   generados $made · ${secs}s   ');
      } catch (e) {
        failed++;
        stderr.writeln('\n  párrafo ${para.index}: $e');
        if (failed >= 5) {
          await save();
          stderr.writeln('Demasiados fallos seguidos; ¿está corriendo el '
              'servidor? Lo hecho se conserva: vuelve a correr el mismo '
              'comando y continúa donde quedó.');
          exit(1);
        }
      }
    }
    await save();
    if (stoppedAt != null) break;
  }
  client.close();
  if (onPhone > 0) {
    stdout.writeln('\n\nSaltados: $onPhone párrafos que el teléfono ya tiene.');
  }
  stdout.writeln('\n\nListo: $made párrafos nuevos, $reused ya estaban'
      '${failed > 0 ? ', $failed fallaron (repite el comando)' : ''}.');
  final stop = stoppedAt;
  if (stop != null) {
    final rest = wanted.where((n) => n > stop.chapter).toList();
    stdout.writeln('Paré al llegar a ~${_fmtHours(hoursBudget!)} de audio. Para '
        'seguir con la siguiente parte:\n  dart run tools/audios/bajar.dart "$epubPath" '
        '${[stop.chapter, ...rest].join(',')} --desde ${stop.paragraph} '
        '--horas $hoursBudget');
  }
  stdout.writeln('Carpeta: ${root.path}');
  if (made > 0) {
    stdout.writeln('Siguiente paso: tools/audios/pasar.sh');
  } else if (onPhone > 0) {
    stdout.writeln('Nada nuevo que pasar: el teléfono ya tiene todo lo pedido.');
  }
}

List<int> _parseChapters(String spec, int total) {
  final out = <int>{};
  for (final part in spec.split(',')) {
    final m = RegExp(r'^\s*(\d+)\s*(?:-\s*(\d+))?\s*$').firstMatch(part);
    if (m == null) {
      stderr.writeln('Capítulos no válidos: "$spec" (ejemplos: 3, 3-5, 1,4)');
      exit(64);
    }
    final a = int.parse(m.group(1)!);
    final b = int.parse(m.group(2) ?? m.group(1)!);
    for (var n = a; n <= b; n++) {
      if (n < 1 || n > total) {
        stderr.writeln('El capítulo $n no existe: el libro tiene $total.');
        exit(64);
      }
      out.add(n);
    }
  }
  return out.toList()..sort();
}

String _token() {
  final env = Platform.environment['VOICE_TOKEN'];
  if (env != null && env.isNotEmpty) return env;
  final f = File('tools/mlx/.token');
  return f.existsSync() ? f.readAsStringSync().trim() : '';
}

Future<List<int>> _synthesize(HttpClient client, String server, String token,
    String text, String voice, String engine) async {
  final req = await client.postUrl(Uri.parse('$server/tts'));
  req.headers.contentType = ContentType.json;
  if (token.isNotEmpty) req.headers.set('Authorization', 'Bearer $token');
  req.write(jsonEncode({'text': text, 'voice': voice, 'engine': engine}));
  final resp = await req.close().timeout(const Duration(minutes: 5));
  final body = await resp.fold<List<int>>([], (a, b) => a..addAll(b));
  if (resp.statusCode != 200) {
    throw 'el servidor respondió ${resp.statusCode}: '
        '${utf8.decode(body, allowMalformed: true)}';
  }
  if (body.isEmpty) throw 'el servidor devolvió un audio vacío';
  return body;
}

/// What the phone reported for one book and one voice.
class _Phone {
  final String when;

  /// Chapter index → paragraphs already downloaded.
  final Map<int, Set<int>> have;

  _Phone(this.when, this.have);

  int get total => have.values.fold(0, (a, s) => a + s.length);
}

_Phone? _loadPhone(String path, String hash, String voiceId) {
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    if (json['format'] != _formatTag) {
      stderr.writeln('El inventario es de otro formato de caché '
          '(${json['format']}): se ignora. Repite «Dejar mis libros listos».');
      return null;
    }
    final book = (json['books'] as Map<String, dynamic>)[hash];
    // This book is not on the phone with this EPUB, or has nothing downloaded.
    final chapters = book == null
        ? null
        : ((book as Map<String, dynamic>)['voices']
            as Map<String, dynamic>)[voiceId] as Map<String, dynamic>?;
    final have = <int, Set<int>>{
      for (final e in (chapters ?? const <String, dynamic>{}).entries)
        int.parse(e.key): {for (final n in e.value as List) n as int},
    };
    final when = DateTime.tryParse('${json['generated']}');
    return _Phone(
        when == null
            ? 'sin fecha'
            : '${when.day}/${when.month} ${when.hour.toString().padLeft(2, '0')}:'
                '${when.minute.toString().padLeft(2, '0')}',
        have);
  } catch (e) {
    stderr.writeln('No pude leer $path ($e): se ignora.');
    return null;
  }
}
