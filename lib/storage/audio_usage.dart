import 'dart:io';

import '../config/settings.dart';

/// What a cache key says about the audio it names.
///
/// The key is `<engine>-<voice>` ("qwen3-esposa", "edge-es-MX-DaliaNeural").
/// An old key with no prefix at all came from Edge, before the engines were
/// told apart.
class CacheKeyInfo {
  /// The engine id, which is the prefix of the key.
  final String engine;

  /// What follows the engine: the voice, or for the phone engine its language
  /// and voice.
  final String detail;

  /// True when no engine of this build produces that audio any more.
  ///
  /// Nothing can play it, so it only takes up space. The start-up migration
  /// already deletes the ones it knows about; this catches whatever it does not.
  final bool retired;

  const CacheKeyInfo(this.engine, this.detail, {required this.retired});
}

CacheKeyInfo describeCacheKey(String voiceId) {
  final cut = voiceId.indexOf('-');
  final engine = cut < 0 ? 'edge' : voiceId.substring(0, cut);
  final detail = cut < 0 ? voiceId : voiceId.substring(cut + 1);
  return CacheKeyInfo(engine, detail, retired: !ttsEngines.contains(engine));
}

/// Audio stored for one voice of one engine, in one book.
class KeyUsage {
  final String voiceId;
  final int downloadsKb;
  final int cacheKb;
  final int items;

  const KeyUsage({
    required this.voiceId,
    required this.downloadsKb,
    required this.cacheKb,
    required this.items,
  });

  int get totalKb => downloadsKb + cacheKb;

  CacheKeyInfo get info => describeCacheKey(voiceId);
}

/// Everything stored for one book, or for a book that is no longer in the
/// library ([title] null).
///
/// The audio cache has no foreign key to the books table, so deleting a book
/// used to leave its audio behind with no owner: counted in the total shown in
/// Ajustes and listed under no book.
class BookAudioUsage {
  final int bookId;
  final String? title;
  final List<KeyUsage> keys;

  const BookAudioUsage({
    required this.bookId,
    required this.title,
    required this.keys,
  });

  bool get orphaned => title == null;

  int get downloadsKb => keys.fold(0, (n, k) => n + k.downloadsKb);
  int get cacheKb => keys.fold(0, (n, k) => n + k.cacheKb);
  int get totalKb => downloadsKb + cacheKb;
  int get items => keys.fold(0, (n, k) => n + k.items);

  /// KB of audio no engine of this build can play.
  int get retiredKb =>
      keys.where((k) => k.info.retired).fold(0, (n, k) => n + k.totalKb);
}

/// What is stored for one chapter of a book.
class ChapterAudioUsage {
  final int chapter;

  /// Distinct paragraphs with audio, whichever engine made it.
  final int paragraphs;

  /// Of those, the ones that were downloaded on purpose.
  final int downloadedParagraphs;
  final int kb;

  const ChapterAudioUsage({
    required this.chapter,
    required this.paragraphs,
    required this.downloadedParagraphs,
    required this.kb,
  });
}

/// Audio files on disk that no row of the cache refers to.
///
/// They are left by a crash between writing a file and recording it, by a book
/// deleted before the cache learned to follow it, or by an engine whose rows
/// were dropped without their file. Invisible by construction: nothing in the
/// database mentions them.
class StrayAudio {
  final List<File> files;
  final int bytes;

  const StrayAudio(this.files, this.bytes);

  static const none = StrayAudio([], 0);

  int get kb => (bytes / 1024).ceil();
}

// The names the app gives the audio it caches: `<book>_<chapter>_<paragraph>_…`
// in the temporary directory, and the same behind `dl_` for a download. Matching
// on this shape and nothing broader is deliberate: the temporary directory also
// holds the file a playback is using right now (`qwen3_<uuid>.mp3`,
// `edge_<uuid>.mp3`), and deleting that would silence it.
final _cachedAudioName =
    RegExp(r'^(dl_)?\d+_\d+_\d+_.+\.(mp3|m4a|aac|wav)(\.ts\.json)?$');

/// Whether [name] is the file name of an audio the cache wrote.
bool looksLikeCachedAudio(String name) => _cachedAudioName.hasMatch(name);

/// Looks in [dirs] for cached audio that is not in [known], the paths the
/// database knows about.
Future<StrayAudio> findStrayAudio(
    Iterable<Directory> dirs, Set<String> known) async {
  final stray = <File>[];
  var bytes = 0;
  for (final dir in dirs) {
    if (!await dir.exists()) continue;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.path.split('/').last;
      if (!looksLikeCachedAudio(name)) continue;
      // A word-timing sidecar is not recorded on its own: it belongs to the
      // audio next to it.
      final audioPath = name.endsWith('.ts.json')
          ? entity.path.substring(0, entity.path.length - '.ts.json'.length)
          : entity.path;
      if (known.contains(audioPath)) continue;
      stray.add(entity);
      bytes += await entity.length();
    }
  }
  return StrayAudio(stray, bytes);
}

/// Deletes what [findStrayAudio] found. Returns how many files went.
Future<int> deleteStrayAudio(StrayAudio stray) async {
  var gone = 0;
  for (final f in stray.files) {
    try {
      if (await f.exists()) {
        await f.delete();
        gone++;
      }
    } catch (_) {}
  }
  return gone;
}
