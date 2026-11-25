import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';

import '../../storage/audio_importer.dart';
import '../../storage/audio_usage.dart';
import '../../storage/book_exporter.dart';
import '../../storage/repositories.dart';
import '../providers/reader_provider.dart' show cacheFormatTag;
import '../widgets/audio_labels.dart';

/// Where the app keeps the audio it writes: the cache in the temporary folder,
/// downloads in the documents one.
Future<List<Directory>> defaultAudioDirs() async =>
    [await getApplicationDocumentsDirectory(), await getTemporaryDirectory()];

/// Where `tools/audios/pasar.sh` leaves the audio generated on the Mac: the
/// app's own folder on shared storage, which `adb push` can write and this app
/// can read without asking for any permission.
Future<Directory?> defaultImportInbox() async {
  final external = await getExternalStorageDirectory();
  return external == null ? null : Directory('${external.path}/importar');
}

/// Every byte of audio on the phone, by book, in one place.
///
/// Ajustes showed a total ("Descargas: 107 MB") that spans every book, and a
/// detail that covered only the book open at the time, so the two never
/// reconciled and there was no way to see where the rest was. This lists every
/// book that has audio, says which of it nothing can play any more, and leads
/// to a per-chapter view of each one.
class DownloadsScreen extends StatefulWidget {
  /// Folders searched for audio the database does not know about. Injectable
  /// because `path_provider` does not exist under `flutter test`.
  final Future<List<Directory>> Function() audioDirs;

  /// Folder to import Mac-generated audio from. Injectable for the same reason.
  final Future<Directory?> Function() importInbox;

  /// Where imported audio ends up: the same folder a download writes to.
  final Future<Directory> Function() docsDir;

  const DownloadsScreen({
    super.key,
    this.audioDirs = defaultAudioDirs,
    this.importInbox = defaultImportInbox,
    this.docsDir = getApplicationDocumentsDirectory,
  });

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final _repo = AudioCacheRepo();

  List<BookAudioUsage>? _books;
  StrayAudio _stray = StrayAudio.none;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final books = await _repo.usageByBook();
    final stray = await findStrayAudio(
        await widget.audioDirs(), await _repo.knownPaths());
    if (!mounted) return;
    setState(() {
      _books = books;
      _stray = stray;
    });
  }

  int get _downloadsKb => _books?.fold<int>(0, (n, b) => n + b.downloadsKb) ?? 0;
  int get _cacheKb => _books?.fold<int>(0, (n, b) => n + b.cacheKb) ?? 0;
  int get _orphanKb => _books
          ?.where((b) => b.orphaned)
          .fold<int>(0, (n, b) => n + b.totalKb) ??
      0;
  int get _orphanBooks => _books?.where((b) => b.orphaned).length ?? 0;

  /// Audio from a retired engine in books that still exist. What belongs to a
  /// deleted book is counted there, not twice.
  int get _retiredKb => _books
          ?.where((b) => !b.orphaned)
          .fold<int>(0, (n, b) => n + b.retiredKb) ??
      0;

  int get _totalKb => _downloadsKb + _cacheKb + _stray.kb;

  Future<bool> _confirm(String title, String body, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  void _said(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importFromMac() async {
    final inbox = await widget.importInbox();
    if (inbox == null) {
      _said('Este teléfono no tiene dónde recibir audios.');
      return;
    }
    final result = await importMacAudio(
      inbox: inbox,
      docsDir: await widget.docsDir(),
      formatTag: cacheFormatTag,
    );
    await _load();
    if (!mounted) return;
    if (result.nothingFound) {
      _said('No hay audios esperando. En el Mac: tools/audios/pasar.sh');
      return;
    }
    final lines = [
      if (result.imported > 0)
        'Se importaron ${paragraphsLabel(result.imported)}; ya se oyen sin '
            'conexión.',
      if (result.alreadyThere > 0)
        '${paragraphsLabel(result.alreadyThere)} ya estaban descargados.',
      ...result.problems,
    ];
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Importar audios del Mac'),
        content: Text(lines.join('\n\n')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  Future<void> _exportBooks() async {
    final inbox = await widget.importInbox();
    if (inbox == null) {
      _said('Este teléfono no tiene dónde dejar los libros.');
      return;
    }
    final n = await exportLibraryBooks(
        Directory('${inbox.parent.path}/libros'),
        formatTag: cacheFormatTag);
    _said(n == 0
        ? 'No hay libros en la biblioteca.'
        : n == 1
            ? '1 libro listo para el Mac. Ahí: tools/audios/traer-libros.sh'
            : '$n libros y lo que ya tienes descargado, listos para el Mac. Ahí: tools/audios/traer-libros.sh');
  }

  Future<void> _freeOrphans() async {
    final kb = _orphanKb;
    if (!await _confirm(
        'Audio de libros eliminados',
        'Son ${formatSize(kb)} de audio de libros que ya no están en tu '
            'biblioteca. Nadie puede reproducirlo: se borra sin perder nada.',
        'Borrar')) {
      return;
    }
    await _repo.deleteOrphans();
    await _load();
    _said('Liberados ${formatSize(kb)}');
  }

  Future<void> _freeRetired() async {
    final kb = _retiredKb;
    if (!await _confirm(
        'Audio de motores retirados',
        'Son ${formatSize(kb)} hechos con motores que la app ya no tiene '
            '(Kokoro, Piper, F5…). Ninguno de los motores actuales puede '
            'reproducirlo.',
        'Borrar')) {
      return;
    }
    await _repo.deleteRetiredEngines();
    await _load();
    _said('Liberados ${formatSize(kb)}');
  }

  Future<void> _freeStray() async {
    final kb = _stray.kb;
    if (!await _confirm(
        'Archivos sin registro',
        'Son ${formatSize(kb)} en ${_stray.files.length} archivos de audio que '
            'la app no tiene anotados en ningún libro. Se pueden borrar sin '
            'perder nada.',
        'Borrar')) {
      return;
    }
    await deleteStrayAudio(_stray);
    await _load();
    _said('Liberados ${formatSize(kb)}');
  }

  Future<void> _deleteOrphanBook(BookAudioUsage book) async {
    if (!await _confirm(
        'Libro eliminado',
        'Borrar los ${formatSize(book.totalKb)} de audio de un libro que ya no '
            'está en tu biblioteca.',
        'Borrar')) {
      return;
    }
    await _repo.deleteForBook(book.bookId);
    await _load();
  }

  Future<void> _deleteEverything() async {
    if (!await _confirm(
        'Borrar todo el audio',
        'Se eliminarán ${formatSize(_totalKb)}: todas las descargas, la caché y '
            'los archivos sueltos, de todos los libros. Lo que quieras volver a '
            'oír habrá que generarlo otra vez.',
        'Borrar todo')) {
      return;
    }
    await _repo.deleteEverything();
    await deleteStrayAudio(_stray);
    await _load();
    _said('Audio borrado');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = _books;

    return Scaffold(
      appBar: AppBar(title: const Text('Descargas y caché')),
      body: books == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _Summary(
                    totalKb: _totalKb,
                    downloadsKb: _downloadsKb,
                    cacheKb: _cacheKb,
                    strayKb: _stray.kb),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.usb),
                  label: const Text('Importar audios del Mac'),
                  onPressed: _importFromMac,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.menu_book_outlined, size: 18),
                  label: const Text('Dejar mis libros listos para el Mac'),
                  onPressed: _exportBooks,
                ),
                if (_orphanKb > 0 || _retiredKb > 0 || _stray.kb > 0) ...[
                  const SizedBox(height: 16),
                  Text('Se puede liberar sin perder nada',
                      style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                      'Audio que ningún libro de tu biblioteca ni ningún motor '
                      'actual puede reproducir.',
                      style: theme.textTheme.bodySmall),
                  if (_orphanKb > 0)
                    _Reclaim(
                      title: 'Libros que ya no están en tu biblioteca',
                      detail: '${formatSize(_orphanKb)} · '
                          '${_orphanBooks == 1 ? '1 libro' : '$_orphanBooks libros'}',
                      onTap: _freeOrphans,
                    ),
                  if (_retiredKb > 0)
                    _Reclaim(
                      title: 'Motores que la app ya no tiene',
                      detail: formatSize(_retiredKb),
                      onTap: _freeRetired,
                    ),
                  if (_stray.kb > 0)
                    _Reclaim(
                      title: 'Archivos sin registro',
                      detail: '${formatSize(_stray.kb)} · '
                          '${_stray.files.length} archivos',
                      onTap: _freeStray,
                    ),
                ],
                const SizedBox(height: 16),
                Text('Por libro', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                if (books.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('No hay audio guardado.',
                        style: theme.textTheme.bodyMedium),
                  ),
                for (final book in books)
                  _BookTile(
                    book: book,
                    onOpen: book.orphaned
                        ? () => _deleteOrphanBook(book)
                        : () async {
                            await context.push('/downloads/${book.bookId}');
                            await _load();
                          },
                  ),
                const SizedBox(height: 16),
                if (_totalKb > 0)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: Text('Borrar todo (${formatSize(_totalKb)})'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error),
                    onPressed: _deleteEverything,
                  ),
              ],
            ),
    );
  }
}

class _Summary extends StatelessWidget {
  final int totalKb, downloadsKb, cacheKb, strayKb;

  const _Summary({
    required this.totalKb,
    required this.downloadsKb,
    required this.cacheKb,
    required this.strayKb,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, int kb) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(formatSize(kb), style: theme.textTheme.bodyMedium),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ocupa en el teléfono', style: theme.textTheme.labelLarge),
            const SizedBox(height: 2),
            Text(formatSize(totalKb), style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            row('Descargas: las que pediste tú', downloadsKb),
            row('Caché: se recicla sola', cacheKb),
            if (strayKb > 0) row('Archivos sin registro', strayKb),
          ],
        ),
      ),
    );
  }
}

class _Reclaim extends StatelessWidget {
  final String title, detail;
  final VoidCallback onTap;

  const _Reclaim(
      {required this.title, required this.detail, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(detail),
        trailing: TextButton(onPressed: onTap, child: const Text('Liberar')),
      );
}

class _BookTile extends StatelessWidget {
  final BookAudioUsage book;
  final VoidCallback onOpen;

  const _BookTile({required this.book, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onOpen,
      title: Text(book.title ?? 'Libro eliminado de la biblioteca',
          maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${formatSize(book.totalKb)} · ${paragraphsLabel(book.items)}'),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final k in book.keys)
                Chip(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  label: Text('${keyLabel(k.info)}  ${formatSize(k.totalKb)}',
                      style: theme.textTheme.labelSmall),
                  backgroundColor: k.info.retired
                      ? theme.colorScheme.errorContainer
                      : null,
                ),
            ],
          ),
        ],
      ),
      trailing: Icon(book.orphaned ? Icons.delete_outline : Icons.chevron_right),
    );
  }
}
