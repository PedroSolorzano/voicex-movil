/// Where the self-hosted engines live, and the credential to reach them.
///
/// Baked in at build time with `--dart-define-from-file`, one file per build,
/// so the address never appears as an editable field a tester can break, paste
/// into a group chat, or leak in a screenshot.
///
/// **This is not a secret store, and pretending otherwise would be the
/// dangerous mistake.** A value compiled with `String.fromEnvironment` is a
/// plain literal inside the AOT snapshot: `strings` on the extracted library
/// finds it in seconds, and R8 does not obfuscate Dart code. The tunnel's
/// hostname is public anyway — every `*.ts.net` certificate is published to
/// Certificate Transparency minutes after it is issued.
///
/// What actually protects the machine at home is elsewhere: a different token
/// per tester so a leak is attributable and revocable on its own, a rate limit
/// keyed on that token, a whitelist of the handful of routes the app really
/// calls, backends bound to loopback so nothing can bypass the proxy, and the
/// tunnel switched off outside a testing window. The token here is a revocable
/// identifier, not a password.
///
/// Empty values are the normal case: a build with no server configured simply
/// has no self-hosted engines, and Edge — which needs nothing — carries it.
class TtsServerConfig {
  const TtsServerConfig._();

  static const kokoroUrl = String.fromEnvironment('KOKORO_URL');

  static const piperUrl = String.fromEnvironment('PIPER_URL');
  static const token = String.fromEnvironment('TTS_TOKEN');

  /// Base del proxy para los reportes: la URL de un motor sin su prefijo.
  ///
  /// Se deduce en vez de configurarse aparte para que no haya dos sitios donde
  /// escribir el mismo host y equivocarse en uno.
  static String get reportUrl {
    final base = kokoroUrl.isNotEmpty ? kokoroUrl : piperUrl;
    if (base.isEmpty) return '';
    final cut = base.lastIndexOf('/');
    return cut > base.indexOf('://') + 2 ? base.substring(0, cut) : base;
  }

  /// Whether this build can talk to Kokoro at all.
  ///
  /// A URL without a token would mean an unauthenticated request to a proxy
  /// that will answer 401, so both have to be present — except on the LAN,
  /// where a bare URL and no proxy is still a valid setup.
  static bool get hasKokoro => kokoroUrl.isNotEmpty;
  static bool get hasPiper => piperUrl.isNotEmpty;

  /// Engines this build is able to offer, in the order they appear in Ajustes.
  ///
  /// Edge is always there: it needs no server and no configuration.
  /// Engines this build is able to offer, in the order they appear in Ajustes.
  ///
  /// Edge y el motor del teléfono están siempre: el primero necesita internet y
  /// nada más, el segundo ni siquiera eso. Kokoro y Piper dependen de que la
  /// compilación traiga su dirección.
  static List<String> get availableEngines => [
        'edge',
        if (hasKokoro) 'kokoro',
        if (hasPiper) 'piper',
        'android',
      ];
}
