import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provided in `main()` (and in tests) with an already-loaded instance, so
/// settings are available synchronously on the first frame.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a loaded instance',
  ),
);

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.trueBlack = false,
  });

  /// Follow the phone (system), or force light or dark.
  final ThemeMode themeMode;

  /// Pure black backgrounds whenever the dark theme is showing.
  final bool trueBlack;

  AppSettings copyWith({ThemeMode? themeMode, bool? trueBlack}) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      trueBlack: trueBlack ?? this.trueBlack,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.trueBlack == trueBlack;

  @override
  int get hashCode => Object.hash(themeMode, trueBlack);
}

class SettingsController extends Notifier<AppSettings> {
  static const String themeModeKey = 'settings.themeMode';
  static const String trueBlackKey = 'settings.trueBlack';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final storedMode = prefs.getString(themeModeKey);
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == storedMode,
        orElse: () => ThemeMode.system,
      ),
      trueBlack: prefs.getBool(trueBlackKey) ?? false,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(themeModeKey, mode.name);
  }

  Future<void> setTrueBlack(bool value) async {
    state = state.copyWith(trueBlack: value);
    await _prefs.setBool(trueBlackKey, value);
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
