import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/settings.dart';
import '../../services/reporter.dart';

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final settings = await AppSettings.load();
    _mirrorToReporter(settings);
    return settings;
  }

  Future<void> save(AppSettings updated) async {
    await updated.save();
    _mirrorToReporter(updated);
    state = AsyncData(updated);
  }

  /// El reportero se llama desde manejadores de error globales, fuera de todo
  /// scope de Riverpod, así que no puede leer este provider: se le copia el
  /// valor cada vez que cambia.
  void _mirrorToReporter(AppSettings settings) =>
      Reporter.crashReportsEnabled = settings.sendCrashReports;

  /// Aplica un cambio sin escribirlo todavía.
  ///
  /// Para los controles que se ven mientras se usan —el tamaño de letra sobre
  /// el propio texto— donde la escritura va con retardo pero el efecto tiene
  /// que ser inmediato. Quien lo llame es responsable de guardar después.
  void setDraft(AppSettings updated) => state = AsyncData(updated);
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
