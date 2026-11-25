import 'package:flutter_test/flutter_test.dart';
import 'package:voicex_movil/storage/audio_usage.dart';
import 'package:voicex_movil/ui/widgets/audio_labels.dart';

void main() {
  group('engineLabelFor', () {
    test('names the engines of this build', () {
      expect(engineLabelFor('edge'), 'Edge');
      expect(engineLabelFor('qwen3'), 'Qwen3');
      expect(engineLabelFor('chatterbox2'), 'Chatterbox');
      expect(engineLabelFor('android'), 'Teléfono');
    });

    test('says a retired engine is retired instead of calling it Edge', () {
      expect(engineLabelFor('kokoro'), 'Motor retirado (kokoro)');
      expect(engineLabelFor('f5'), 'Motor retirado (f5)');
    });
  });

  test('keyLabel joins engine and voice', () {
    expect(keyLabel(describeCacheKey('qwen3-esposa')), 'Qwen3 · esposa');
    expect(keyLabel(describeCacheKey('edge-es-MX-DaliaNeural')),
        'Edge · es-MX-DaliaNeural');
    expect(keyLabel(describeCacheKey('kokoro-af_bella')),
        'Motor retirado (kokoro) · af_bella');
  });

  group('formatSize', () {
    test('keeps KB under a megabyte and uses MB above', () {
      expect(formatSize(0), '0 KB');
      expect(formatSize(900), '900 KB');
      expect(formatSize(1024), '1.0 MB');
      expect(formatSize(107 * 1024), '107.0 MB');
    });
  });

  test('paragraphsLabel is singular for one', () {
    expect(paragraphsLabel(1), '1 párrafo');
    expect(paragraphsLabel(0), '0 párrafos');
    expect(paragraphsLabel(12), '12 párrafos');
  });
}
