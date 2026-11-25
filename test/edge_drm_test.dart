import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/tts/edge_drm.dart';

// Expected values come from rany2/edge-tts 7.3.1 (`generate_sec_ms_gec_v2`)
// run at these exact instants. Microsoft rejects any other digest with 403.
const _clientToken = '6A5AA1D4EAFF4E9FB37E23D68491D6F4';

void main() {
  group('generateSecMsGec (version 2)', () {
    final golden = <double, String>{
      1700000000:
          '2CD23A2CA0B2595A-F3C846C370E05F9CC83ACC5F995C5F5D87A4D0F14CE8936A0F902E64099E38A2',
      1764000123.5:
          'BB2B3ADE6A8DD1F3-B07567543B86F99C3539F563D8D3368C59A22CAF50BF1E35F42DA34792F80A76',
      1893456000:
          '7442B6E630CDF0DE-CE82EC1509335DC856270C1EEB0F7F2575909AC26840D2C15B28A41EBB7E9CCF',
      1600000000:
          '1F5E89103EC98A08-E69D008C1241797258F0EE06F56044C11FAEC4B60F95C6AB0DB3C5E79BE2F010',
    };

    golden.forEach((unix, expected) {
      test('matches the reference implementation at $unix', () {
        expect(generateSecMsGec(unix, _clientToken), expected);
      });
    });

    test('has the <16 hex>-<64 hex> shape', () {
      expect(generateSecMsGec(1700000000, _clientToken),
          matches(RegExp(r'^[0-9A-F]{16}-[0-9A-F]{64}$')));
    });

    test('is stable inside one five-minute window and changes at the next', () {
      // Windows are multiples of 300 s: 1699999800 starts one, 1700000100 the next.
      final start = generateSecMsGec(1699999800, _clientToken);
      final end = generateSecMsGec(1700000099, _clientToken);
      final next = generateSecMsGec(1700000100, _clientToken);

      expect(end, start);
      expect(next, isNot(start));
    });
  });
}
