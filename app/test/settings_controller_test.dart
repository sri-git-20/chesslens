import 'package:chesslens/src/engine/engine_providers.dart';
import 'package:chesslens/src/engine/engine_service.dart';
import 'package:chesslens/src/settings/settings_controller.dart';
import 'package:chesslens/src/theme/board_themes.dart';
import 'package:chessground/chessground.dart' show PieceSet;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:multistockfish/multistockfish.dart' show StockfishFlavor;
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

  test('engine and board settings have sensible defaults', () {
    final settings = container.read(settingsProvider);
    expect(settings.engineThreads, inInclusiveRange(1, 4));
    expect(settings.engineHashMb, 64);
    expect(settings.multiPv, 2);
    expect(settings.depthLimit, 30);
    expect(settings.timeLimitSeconds, 60);
    expect(settings.showCoordinates, isTrue);
    expect(settings.boardTheme, BoardTheme.green);
    expect(settings.pieceSet, PieceSet.cburnett);
    expect(settings.engineNetworkPath, isNull);
  });

  test('engine and board settings are stored and restored', () async {
    final controller = container.read(settingsProvider.notifier);
    await controller.setEngineThreads(3);
    await controller.setEngineHashMb(256);
    await controller.setMultiPv(3);
    await controller.setDepthLimit(0);
    await controller.setTimeLimitSeconds(120);
    await controller.setShowCoordinates(false);
    await controller.setBoardTheme(BoardTheme.blue);
    await controller.setPieceSet(PieceSet.merida);
    await controller.setEngineNetworkPath('/data/net.nnue');

    final restored = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(restored.dispose);
    final settings = restored.read(settingsProvider);
    expect(settings.engineThreads, 3);
    expect(settings.engineHashMb, 256);
    expect(settings.multiPv, 3);
    expect(settings.depthLimit, 0);
    expect(settings.timeLimitSeconds, 120);
    expect(settings.showCoordinates, isFalse);
    expect(settings.boardTheme, BoardTheme.blue);
    expect(settings.pieceSet, PieceSet.merida);
    expect(settings.engineNetworkPath, '/data/net.nnue');

    await controller.setEngineNetworkPath(null);
    expect(prefs.containsKey(SettingsController.engineNetworkPathKey), isFalse);
    expect(container.read(settingsProvider).engineNetworkPath, isNull);
  });

  test('out of range stored values fall back to defaults', () async {
    SharedPreferences.setMockInitialValues({
      SettingsController.engineThreadsKey: 64,
      SettingsController.engineHashKey: 999,
      SettingsController.multiPvKey: 9,
      SettingsController.depthLimitKey: 7,
      SettingsController.boardThemeKey: 'neon',
      SettingsController.pieceSetKey: 'nope',
    });
    final other = ProviderContainer(
      overrides: [
        sharedPreferencesProvider
            .overrideWithValue(await SharedPreferences.getInstance()),
      ],
    );
    addTearDown(other.dispose);
    final settings = other.read(settingsProvider);
    expect(settings.engineThreads, 4);
    expect(settings.engineHashMb, 64);
    expect(settings.multiPv, 3);
    expect(settings.depthLimit, 30);
    expect(settings.boardTheme, BoardTheme.green);
    expect(settings.pieceSet, PieceSet.cburnett);
  });

  test('the engine spec follows the network path setting', () async {
    final controller = container.read(settingsProvider.notifier);
    expect(container.read(engineSpecProvider), EngineSpec.light);
    await controller.setEngineNetworkPath('/data/net.nnue');
    final spec = container.read(engineSpecProvider);
    expect(spec.flavor, StockfishFlavor.latestNoNNUE);
    expect(spec.nnuePath, '/data/net.nnue');
  });
}
