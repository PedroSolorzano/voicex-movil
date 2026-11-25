import '../../storage/audio_usage.dart';

/// Name of an engine as a person reads it. An id this build does not know is
/// an engine that was retired, and is said so: the factory's own label would
/// call it Edge, which is exactly the confusion this screen exists to clear.
String engineLabelFor(String engine) => switch (engine) {
      'edge' => 'Edge',
      'qwen3' => 'Qwen3',
      'chatterbox2' => 'Chatterbox',
      'android' => 'Teléfono',
      _ => 'Motor retirado ($engine)',
    };

/// "Qwen3 · esposa", "Edge · es-MX-DaliaNeural".
String keyLabel(CacheKeyInfo info) {
  final engine = engineLabelFor(info.engine);
  return info.detail.isEmpty ? engine : '$engine · ${info.detail}';
}

/// KB as a person reads them: KB under a megabyte, one decimal above.
String formatSize(int kb) =>
    kb < 1024 ? '$kb KB' : '${(kb / 1024).toStringAsFixed(1)} MB';

/// "1 párrafo", "12 párrafos".
String paragraphsLabel(int n) => n == 1 ? '1 párrafo' : '$n párrafos';
