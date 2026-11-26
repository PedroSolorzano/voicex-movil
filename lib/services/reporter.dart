import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:sqflite/sqflite.dart';

import '../config/server_config.dart';
import '../storage/database.dart';
import '../tts/server_health.dart';
import '../tts/tts_endpoint.dart';

/// Sends crashes and feedback to the voice server (`tools/mlx`), with its token.
///
/// Two rules shape everything here.
///
/// **A report never carries the text of a book.** The obvious leak is an
/// exception message: a synthesis failure can arrive with the paragraph that
/// was being sent embedded in it, and this thing sends automatically. So what
/// travels is the exception *type*, the endpoint and the status — never the raw
/// message — plus a hard truncation as a second net. [sanitize] is the one
/// place that decides, and it has its own tests.
///
/// **A report is queued, not sent.** The failures worth reporting mostly happen
/// when the server is unreachable, which is exactly when sending fails. Queuing
/// on the device and flushing when the server answers again is what keeps the
/// interesting cases; without it the reporter would work only when nothing was
/// wrong.
class Reporter {
  /// Anything longer than this is a payload, not a diagnosis.
  static const _maxField = 300;

  /// Enough to see a pattern, few enough that nothing accumulates unnoticed.
  static const _maxQueued = 50;

  static bool _installed = false;

  /// Whether an uncaught failure may be queued and sent.
  ///
  /// A plain static, mirrored from [AppSettings.sendCrashReports] by whoever
  /// loads and saves settings: this class is reached from
  /// `FlutterError.onError` and from `runZonedGuarded`, which run outside any
  /// provider scope and sometimes with the app already broken — reading
  /// Riverpod from there would be one more thing that can throw while handling
  /// a throw. Defaults to true so a crash during startup, before settings are
  /// read, is not lost.
  static bool crashReportsEnabled = true;

  /// Routes uncaught Flutter and platform errors here.
  ///
  /// Called once at startup; [runZonedGuarded] in `main` covers the rest.
  static void install() {
    if (_installed) return;
    _installed = true;

    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(recordCrash(details.exception, details.stack,
          context: details.context?.toString()));
    };

    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(recordCrash(error, stack));
      return true;
    };

    // Moments when the server may be back. Before, the queue only moved when
    // a new report was written or the phone changed networks: a report made
    // with the Mac off waited even after the Mac was on again.
    onServerAnswered = () => unawaited(flush());
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(flush()));
    unawaited(flush());
  }

  // Kept so the listener is not collected; it lives as long as the app.
  // ignore: unused_field
  static AppLifecycleListener? _lifecycle;

  /// Strips anything that could be book text, and caps what is left.
  ///
  /// Deliberately blunt. The alternative — trying to recognise prose and let
  /// the rest through — fails silently the first time somebody reads a book
  /// that looks like a stack trace.
  @visibleForTesting
  static String sanitize(Object? value) {
    if (value == null) return '';
    final text = value.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length <= _maxField
        ? text
        : '${text.substring(0, _maxField)}… (recortado)';
  }

  /// Describes a failure without quoting it.
  ///
  /// The type alone identifies the fault -- `TimeoutException`,
  /// `SocketException`, `HttpException` -- and it cannot contain a paragraph.
  @visibleForTesting
  static String describe(Object error) {
    final type = error.runtimeType.toString();
    if (error is HttpException) {
      // The URI is ours; the message may not be.
      final where = error.uri?.path ?? '';
      return where.isEmpty ? type : '$type en $where';
    }
    return type;
  }

  /// Queues a crash. Never throws: a failure inside the reporter must not
  /// become a second crash.
  static Future<void> recordCrash(Object error, StackTrace? stack,
      {String? context}) async {
    // Solo los automáticos. Lo que alguien escribe a propósito
    // (`recordFeedback`) no pasa por aquí: apagar el envío de fallos no puede
    // silenciar un reporte que la persona sí quiso mandar.
    if (!crashReportsEnabled) return;
    try {
      await _enqueue({
        'tipo': 'crash',
        'error': describe(error),
        // Only the frames, which are our own symbols, and only a few.
        'traza': _topFrames(stack),
        if (context != null) 'contexto': sanitize(context),
      });
    } catch (e) {
      dev.log('[Reporter] no se pudo encolar el fallo: $e');
    }
  }

  /// Queues something a tester wrote or recorded.
  static Future<void> recordFeedback({
    required String tipo,
    required String texto,
    String? audioPath,
    Map<String, Object?> contexto = const {},
  }) async {
    await _enqueue({
      'tipo': tipo,
      'texto': sanitize(texto),
      if (audioPath != null) 'nota': audioPath.split('/').last,
      ...contexto,
    }, audioPath: audioPath);
  }

  /// The last few diagnostic lines, which is what turns "no me funciona" into
  /// something actionable.
  static List<String> diagnostics() =>
      TtsDiagnostics.entries.reversed.take(8).map((e) => e.toString()).toList();

  static String _topFrames(StackTrace? stack) {
    if (stack == null) return '';
    final frames = stack.toString().split('\n').take(6).join(' | ');
    return sanitize(frames);
  }

  /// Removes a voice note that has lost its report, never throwing: this runs
  /// on paths that are already handling a failure.
  static Future<void> deleteNoteQuietly(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      dev.log('[Reporter] no se pudo borrar la nota de voz: $e');
    }
  }

  static Future<void> _enqueue(Map<String, Object?> body,
      {String? audioPath}) async {
    final db = await getDatabase();
    final queued = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM reports')) ??
        0;
    if (queued >= _maxQueued) {
      dev.log('[Reporter] cola llena ($queued), se descarta el reporte');
      // The note belonged to a report that will now never be sent. Nothing
      // else knows about that file, so leaving it behind means an orphan in
      // the cache directory that no code path will ever clean up.
      await deleteNoteQuietly(audioPath);
      return;
    }
    await db.insert('reports', {
      'body': jsonEncode({
        ...body,
        'app': appVersionTag,
        'cuando': DateTime.now().toIso8601String(),
        'diagnostico': diagnostics(),
      }),
      'audio_path': audioPath,
    });
    unawaited(flush());
  }

  static bool _flushing = false;

  /// Whether this build has anywhere to send a report at all.
  ///
  /// An APK handed to somebody with no server of ours behind it — Edge only —
  /// carries no address, so [flush] returns immediately and everything queued
  /// stays queued forever. The screens ask this before offering a form that
  /// promises delivery.
  ///
  /// The token is not required: a server started without one asks for nothing.
  /// A wrong or missing one is answered with 401 and the report stays queued.
  static bool get canDeliver => TtsServerConfig.hasServer;

  /// Delivers everything queued, oldest first. Silent by design.
  static Future<void> flush() async {
    if (!canDeliver) return;
    await flushTo(TtsServerConfig.voiceUrl);
  }

  /// [flush] against [base]: the compiled address cannot be swapped in a test.
  @visibleForTesting
  static Future<void> flushTo(String base) async {
    if (_flushing) return;
    _flushing = true;
    try {
      final db = await getDatabase();
      final rows = await db.query('reports', orderBy: 'id', limit: 10);
      for (final row in rows) {
        final id = row['id'] as int;
        final done = await _deliver(db, base, id, row);
        if (done) {
          await db.delete('reports', where: 'id = ?', whereArgs: [id]);
        } else {
          // Se corta al primer fallo: si el servidor no está, los siguientes
          // tampoco van a salir, y reintentarlos solo gasta batería.
          await db.rawUpdate(
              'UPDATE reports SET attempts = attempts + 1 WHERE id = ?', [id]);
          break;
        }
      }
    } catch (e) {
      dev.log('[Reporter] flush falló: $e');
    } finally {
      _flushing = false;
    }
  }

  /// Sends what is still missing of one report: the text, then the voice note.
  /// True when nothing is left to send.
  ///
  /// The two go apart, and the row remembers that the text arrived
  /// (`body_sent`): a report used to count as delivered with its text alone,
  /// so a note that failed halfway — signal lost mid-upload — was never tried
  /// again, and the text arrived without it.
  static Future<bool> _deliver(
      Database db, String base, int id, Map<String, Object?> row) async {
    final client = HttpClient()..connectionTimeout = TtsTimeouts.connect;
    try {
      if (row['body_sent'] != 1) {
        final req = await client.postUrl(buildUri(base, '/report'));
        req.headers.contentType = ContentType.json;
        applyRequestHeaders(req,
            token: TtsServerConfig.voiceToken, engine: 'reporte');
        req.write(row['body'] as String);
        final resp = await req.close().timeout(TtsTimeouts.probe);
        await resp.drain<void>();
        if (resp.statusCode >= 400) return false;
        await db.update('reports', {'body_sent': 1},
            where: 'id = ?', whereArgs: [id]);
      }
      final audioPath = row['audio_path'] as String?;
      if (audioPath == null) return true;
      return await _sendAudio(client, base, audioPath);
    } catch (e) {
      dev.log('[Reporter] envío falló: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Uploads the voice note and deletes the local copy once it is delivered.
  ///
  /// True when there is nothing more to do with it: it arrived, it is gone,
  /// or the server refused it for good (a 4xx other than a rejected key) —
  /// retrying that one would hold the whole queue behind it forever. False
  /// when it is worth another try: no network, a server error, a wrong key.
  static Future<bool> _sendAudio(
      HttpClient client, String base, String path) async {
    final file = File(path);
    if (!await file.exists()) return true;
    try {
      final name = path.split('/').last;
      final req = await client.openUrl(
          'PUT', buildUri(base, '/report/audio/$name'));
      applyRequestHeaders(req,
          token: TtsServerConfig.voiceToken, engine: 'reporte');
      req.add(await file.readAsBytes());
      final resp = await req.close().timeout(TtsTimeouts.body);
      await resp.drain<void>();
      final code = resp.statusCode;
      if (code < 400) {
        await deleteNoteQuietly(path);
        return true;
      }
      if (code >= 500 || code == 401) return false;
      dev.log('[Reporter] el servidor rechazó la nota de voz ($code)');
      await deleteNoteQuietly(path);
      return true;
    } catch (e) {
      dev.log('[Reporter] la nota de voz no subió: $e');
      return false;
    }
  }
}
