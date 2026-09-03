import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'tts_provider.dart';

const _uuid = Uuid();

/// El motor de voz del propio teléfono.
///
/// Se retiró en 0.6.0 y vuelve en 0.7.0 porque es **el único que funciona sin
/// red ni servidor**. Edge necesita internet; Kokoro y Piper, una máquina
/// encendida al otro lado. Para alguien a quien se le pasa el APK sin servidor
/// propio, éste es el que sigue leyendo en el metro.
///
/// La razón que lo retiró sigue siendo cierta: no reporta límites de palabra,
/// así que el resaltado baja a oración estimada, y escribe WAV, que ocupa varias
/// veces lo que el AAC de Kokoro. Lo que cambió es la valoración de la voz —un
/// Samsung trae voces propias bastante mejores que la genérica— y, sobre todo,
/// que ahora la app se reparte a gente sin servidor.
///
/// [voice] puede ser dos cosas: el **nombre** de una voz concreta del catálogo
/// del sistema, o un simple código de idioma. Elegir la voz importa: sin ello el
/// sistema usa su predeterminada, que en un Samsung suele ser la de Google y no
/// la buena.
class AndroidTtsProvider implements TTSProvider {
  final FlutterTts _tts = FlutterTts();
  final String langCode;
  bool _initialized = false;

  AndroidTtsProvider({this.langCode = 'es-ES'});

  Future<void> _init() async {
    if (_initialized) return;
    // Makes synthesizeToFile() resolve when synthesis actually finishes instead
    // of returning immediately — otherwise a half-written file reaches the player.
    await _tts.awaitSynthCompletion(true);
    _initialized = true;
  }

  /// Un identificador con guion bajo o espacios es un nombre de voz
  /// (`es-es-x-eef-local`, `Spanish Spain`); uno con solo guiones y dos o tres
  /// letras por tramo es un código de idioma (`es-ES`).
  static bool looksLikeLocale(String value) =>
      RegExp(r'^[a-z]{2,3}([-_][A-Za-z]{2,4})?$').hasMatch(value.trim());

  @override
  Future<TTSResult> synthesize({
    required String text,
    required String voice,
    required String rate,
    required String volume,
  }) async {
    await _init();

    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/android_${_uuid.v4()}.wav';

    if (voice.isEmpty || looksLikeLocale(voice)) {
      await _tts.setLanguage(voice.isEmpty ? langCode : voice);
    } else {
      // El sistema necesita el par nombre+locale; con el nombre solo, algunos
      // motores lo ignoran en silencio y siguen con la voz por defecto.
      await _tts.setVoice({'name': voice, 'locale': langCode});
    }
    // Neutro a propósito: la velocidad se aplica al reproducir, así que un solo
    // archivo en caché sirve para todas.
    await _tts.setSpeechRate(1.0);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    await _tts.synthesizeToFile(text, filePath);

    final file = File(filePath);
    if (!await file.exists() || await file.length() == 0) {
      throw Exception(
          'El motor de voz del teléfono no generó audio. Comprueba en los '
          'ajustes de Android que haya un motor instalado y con el idioma '
          'descargado.');
    }

    dev.log('[AndroidTTS] ${await file.length()}B → $filePath');
    // The platform engine exposes no word boundaries, so word highlighting is
    // unavailable. ReaderNotifier falls back to a duration estimate.
    return TTSResult(filePath: filePath, timestamps: const []);
  }

  @override
  Future<List<Voice>> listVoices() async {
    await _init();
    final voices = await _tts.getVoices as List?;
    if (voices == null) return const [];
    return voices
        .whereType<Map>()
        .map((v) => Voice(
              id: v['name']?.toString() ?? '',
              name: _friendlyName(v),
              locale: v['locale']?.toString() ?? '',
              gender: 'unknown',
            ))
        .where((v) => v.id.isNotEmpty)
        .toList();
  }

  /// Los nombres del sistema son códigos (`es-es-x-eed-local`). Se marca cuál
  /// está descargada en el teléfono, que es lo único que decide si va a sonar
  /// sin conexión.
  static String _friendlyName(Map v) {
    final name = v['name']?.toString() ?? '';
    final local = name.endsWith('-local') || name.contains('#female_1-local');
    return local ? '$name  ·  sin conexión' : name;
  }

  @override
  Future<void> dispose() async {
    await _tts.stop();
  }
}
