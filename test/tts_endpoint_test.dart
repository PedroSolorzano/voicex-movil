import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/tts/tts_endpoint.dart';

/// The address is typed or pasted by a human, and the two mistakes below used
/// to be indistinguishable from a server that was switched off: the probe said
/// "no responde" while synthesis kept working.
void main() {
  group('normalizeBaseUrl', () {
    test('drops the trailing slash that broke the health probe', () {
      // With the slash, the probe asked for `//health` and got a 404, because
      // only the provider constructors trimmed it.
      expect(normalizeBaseUrl('http://192.168.1.50:8880/'),
          'http://192.168.1.50:8880');
      expect(normalizeBaseUrl('http://192.168.1.50:8880///'),
          'http://192.168.1.50:8880');
    });

    test('adds the scheme when it is missing', () {
      // Without it, Uri.parse yields no host and getUrl throws an ArgumentError
      // that the probe swallowed into the same generic failure.
      expect(normalizeBaseUrl('192.168.1.50:8880'), 'http://192.168.1.50:8880');
      expect(normalizeBaseUrl('host.tailnet-abc.ts.net'),
          'http://host.tailnet-abc.ts.net');
    });

    test('leaves an https address alone', () {
      expect(normalizeBaseUrl('https://host.tailnet-abc.ts.net'),
          'https://host.tailnet-abc.ts.net');
    });

    test('preserves the path prefix', () {
      // Behind the proxy each engine lives under its own prefix. Dropping the
      // segment would point every request at the wrong place.
      expect(normalizeBaseUrl('https://host.ts.net/kokoro/'),
          'https://host.ts.net/kokoro');
      expect(buildUri('https://host.ts.net/kokoro/', '/health').toString(),
          'https://host.ts.net/kokoro/health');
    });

    test('trims surrounding whitespace', () {
      expect(normalizeBaseUrl('  http://host:8880  '), 'http://host:8880');
    });

    test('an empty address stays empty rather than becoming http://', () {
      expect(normalizeBaseUrl(''), '');
      expect(normalizeBaseUrl('   '), '');
    });
  });

  group('authHeaders', () {
    test('no token, no header', () {
      // A server reached directly on the LAN has nothing to authenticate to.
      expect(authHeaders(''), isEmpty);
    });

    test('a token becomes a bearer credential', () {
      expect(authHeaders('abc123'),
          {HttpHeaders.authorizationHeader: 'Bearer abc123'});
    });
  });
}
