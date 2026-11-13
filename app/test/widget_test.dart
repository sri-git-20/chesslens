import 'package:chesslens/src/app.dart';
import 'package:chesslens/src/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _app([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final instance = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(instance)],
    child: const ChessLensApp(),
  );
}

void main() {
  testWidgets('home lists every scan source', (tester) async {
    await tester.pumpWidget(await _app());

    expect(find.text('ChessLens'), findsOneWidget);
    for (final label in ['Camera', 'Gallery', 'PDF', 'Paste FEN']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('dark mode with true black gives a black background',
      (tester) async {
    await tester.pumpWidget(await _app());

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('True black'));
    await tester.pumpAndSettle();

    final context = tester.element(find.text('Appearance'));
    final theme = Theme.of(context);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, Colors.black);
  });

  testWidgets('saved settings are restored on launch', (tester) async {
    await tester.pumpWidget(await _app({
      SettingsController.themeModeKey: 'dark',
      SettingsController.trueBlackKey: true,
    }));

    final theme = Theme.of(tester.element(find.text('Camera')));
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, Colors.black);
  });

  testWidgets('light mode ignores true black', (tester) async {
    await tester.pumpWidget(await _app({
      SettingsController.themeModeKey: 'light',
      SettingsController.trueBlackKey: true,
    }));

    final theme = Theme.of(tester.element(find.text('Camera')));
    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, isNot(Colors.black));
  });
}
