import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/settings.dart';

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => AppSettings.load();

  Future<void> save(AppSettings updated) async {
    await updated.save();
    state = AsyncData(updated);
  }
}

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
