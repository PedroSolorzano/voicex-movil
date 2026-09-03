import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/ui/providers/reader_provider.dart';

/// The gate that decides whether the app may fill the cache ahead.
///
/// It used to ask "is this WiFi?", which quietly broke the moment a VPN was
/// installed: on Android the VPN takes over the reported transport, so a phone
/// on the home network can answer `[vpn]` and nothing else.
void main() {
  group('isLikelyMetered', () {
    test('mobile data is metered', () {
      expect(isLikelyMetered([ConnectivityResult.mobile]), isTrue);
    });

    test('WiFi is not', () {
      expect(isLikelyMetered([ConnectivityResult.wifi]), isFalse);
    });

    test('a VPN over WiFi does not disable prefetching', () {
      // The regression this function exists to prevent. Both shapes matter:
      // some Android versions report the VPN alongside the real transport,
      // others report it alone.
      expect(isLikelyMetered([ConnectivityResult.vpn, ConnectivityResult.wifi]),
          isFalse);
      expect(isLikelyMetered([ConnectivityResult.vpn]), isFalse);
    });

    test('a VPN over mobile data is still caught when the transport shows', () {
      expect(isLikelyMetered([ConnectivityResult.vpn, ConnectivityResult.mobile]),
          isTrue);
    });

    test('ethernet is not metered', () {
      expect(isLikelyMetered([ConnectivityResult.ethernet]), isFalse);
    });

    test('no connection at all is treated as metered, so nothing is attempted',
        () {
      expect(isLikelyMetered([ConnectivityResult.none]), isTrue);
      expect(isLikelyMetered([]), isTrue);
    });
  });
}
