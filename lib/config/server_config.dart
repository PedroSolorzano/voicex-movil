/// Where the self-hosted voice server lives, and the credential to reach it.
///
/// Baked in at build time with `--dart-define-from-file`, one file per build,
/// so the address never appears as an editable field a tester can break, paste
/// into a group chat, or leak in a screenshot.
///
/// **This is not a secret store, and pretending otherwise would be the
/// dangerous mistake.** A value compiled with `String.fromEnvironment` is a
/// plain literal inside the AOT snapshot: `strings` on the extracted library
/// finds it in seconds, and R8 does not obfuscate Dart code. The token is a
/// revocable identifier, not a password: what actually protects the machine is
/// that it only answers to that token and that it sits on a private network.
///
/// Empty values are the normal case: a build with no server configured simply
/// has no self-hosted engines, and Edge — which needs nothing — carries it.
class TtsServerConfig {
  const TtsServerConfig._();

  /// Address of `tools/mlx`, the Mac that runs Qwen3-TTS and Chatterbox.
  ///
  /// One server, two engines: [serverEngines] share this address and token.
  static const voiceUrl = String.fromEnvironment('VOICE_URL');

  /// Credential of that server (`tools/mlx/.token`).
  static const voiceToken = String.fromEnvironment('VOICE_TOKEN');

  /// "Contar un problema" delivers to this same server, with this same token
  /// (`POST /report` and `PUT /report/audio/…` in `tools/mlx/server.py`).
  ///
  /// It used to have an address and a token of its own, for a proxy that lived
  /// on a machine that no longer exists. Sharing the server's means there is
  /// nothing extra to configure: the feature exists exactly when the build
  /// knows where the server is.

  /// Engines served by `tools/mlx`. The ids are the ones the server answers to
  /// and the ones in the cache key.
  ///
  /// `chatterbox2` and not `chatterbox`: that id was retired in 0.8.0 and the
  /// cache migration deletes every row that carries it
  /// (`_dropRetiredEngineRows` in `lib/storage/repositories.dart`).
  static const serverEngines = ['qwen3', 'chatterbox2'];

  static bool get hasServer => voiceUrl.isNotEmpty;

  /// Engines this build is able to offer, in the order they appear in Ajustes.
  ///
  /// Edge y el motor del teléfono están siempre: el primero necesita internet y
  /// nada más, el segundo ni siquiera eso. Qwen3 y Chatterbox dependen de que
  /// la compilación traiga la dirección del servidor.
  static List<String> get availableEngines => [
        'edge',
        if (hasServer) ...serverEngines,
        'android',
      ];
}
