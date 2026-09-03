import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/settings.dart';

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => AppSettings.load();

  Future<void> save(AppSettings updated) async {
    await updated.save();
    state = AsyncData(updated);
  }

  /// Aplica un cambio sin escribirlo todavía.
  ///
  /// Para los controles que se ven mientras se usan —el tamaño de letra sobre
  /// el propio texto— donde la escritura va con retardo pero el efecto tiene
  /// que ser inmediato. Quien lo llame es responsable de guardar después.
  void setDraft(AppSettings updated) => state = AsyncData(updated);
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
