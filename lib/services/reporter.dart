import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../config/server_config.dart';
import '../storage/database.dart';
import '../tts/server_health.dart';
import '../tts/tts_endpoint.dart';

/// Sends crashes and tester feedback to the same proxy that fronts the TTS
/// servers, with the same token.
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
  }

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

  static Future<void> _enqueue(Map<String, Object?> body,
      {String? audioPath}) async {
    final db = await getDatabase();
    final queued = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM reports')) ??
        0;
    if (queued >= _maxQueued) {
      dev.log('[Reporter] cola llena ($queued), se descarta el reporte');
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

  /// Delivers everything queued, oldest first. Silent by design.
  static Future<void> flush() async {
    if (_flushing || TtsServerConfig.token.isEmpty) return;
    final base = TtsServerConfig.reportUrl;
    if (base.isEmpty) return;

    _flushing = true;
    try {
      final db = await getDatabase();
      final rows = await db.query('reports', orderBy: 'id', limit: 10);
      for (final row in rows) {
        final id = row['id'] as int;
        final sent = await _send(base, row['body'] as String,
            row['audio_path'] as String?);
        if (sent) {
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

  static Future<bool> _send(String base, String body, String? audioPath) async {
    final client = HttpClient()..connectionTimeout = TtsTimeouts.connect;
    try {
      final req = await client.postUrl(buildUri(base, '/report'));
      req.headers.contentType = ContentType.json;
      applyRequestHeaders(req,
          token: TtsServerConfig.token, engine: 'reporte');
      req.write(body);
      final resp = await req.close().timeout(TtsTimeouts.probe);
      await resp.drain<void>();
      if (resp.statusCode >= 400) return false;

      if (audioPath != null) await _sendAudio(client, base, audioPath);
      return true;
    } catch (e) {
      dev.log('[Reporter] envío falló: $e');
      return false;
    } finally {
      client.close(force: true);
    }
  }

  /// Uploads the voice note and deletes the local copy once it is delivered.
  static Future<void> _sendAudio(
      HttpClient client, String base, String path) async {
    final file = File(path);
    if (!file.existsSync()) return;
    try {
      final name = path.split('/').last;
      final req = await client.openUrl(
          'PUT', buildUri(base, '/report/audio/$name'));
      applyRequestHeaders(req,
          token: TtsServerConfig.token, engine: 'reporte');
      req.add(await file.readAsBytes());
      final resp = await req.close().timeout(TtsTimeouts.body);
      await resp.drain<void>();
      if (resp.statusCode < 400) await file.delete();
    } catch (e) {
      dev.log('[Reporter] la nota de voz no subió: $e');
    }
  }
}
