import 'package:chesslens/src/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() => container.dispose());

  test('defaults to following the system, no true black', () {
    final settings = container.read(settingsProvider);
    expect(settings.themeMode, ThemeMode.system);
    expect(settings.trueBlack, isFalse);
  });

  test('changes are stored in shared preferences', () async {
    final controller = container.read(settingsProvider.notifier);
    await controller.setThemeMode(ThemeMode.dark);
    await controller.setTrueBlack(true);

    expect(container.read(settingsProvider).themeMode, ThemeMode.dark);
    expect(prefs.getString(SettingsController.themeModeKey), 'dark');
    expect(prefs.getBool(SettingsController.trueBlackKey), isTrue);
  });

  test('an unknown stored value falls back to system', () async {
    SharedPreferences.setMockInitialValues({
      SettingsController.themeModeKey: 'sepia',
    });
    final other = ProviderContainer(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
      ],
    );
    addTearDown(other.dispose);

    expect(other.read(settingsProvider).themeMode, ThemeMode.system);
  });
}
