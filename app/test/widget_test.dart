import 'package:chesslens/src/app.dart';
import 'package:chesslens/src/collections/collection_providers.dart';
import 'package:chesslens/src/collections/memory_collection_repository.dart';
import 'package:chesslens/src/collections/models.dart';
import 'package:chesslens/src/engine/engine_providers.dart';
import 'package:chesslens/src/engine/fake_engine_service.dart';
import 'package:chesslens/src/settings/settings_controller.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Widget> _app([
  Map<String, Object> prefs = const {},
  MemoryCollectionRepository? repository,
]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final instance = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(instance),
      collectionRepositoryProvider
          .overrideWithValue(repository ?? MemoryCollectionRepository()),
      engineServiceProvider.overrideWithValue(FakeEngineService()),
    ],
    child: const ChessLensApp(),
  );
}

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('home lists every scan source', (tester) async {
    await tester.pumpWidget(await _app());

    expect(find.text('ChessLens'), findsOneWidget);
    for (final label in ['Camera', 'Gallery', 'PDF', 'Paste FEN', 'Set up a position']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('home shows the empty collections message', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(await _app());
    await tester.pump();
    expect(find.textContaining('No collections yet'), findsOneWidget);
  });

  testWidgets('home lists saved collections and opens one', (tester) async {
    _tallScreen(tester);
    final repository = MemoryCollectionRepository();
    final collection = await repository.createCollection('Endgames');
    await repository.addPuzzle(Puzzle(
      id: 0,
      collectionId: collection.id,
      fen: '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1',
      orientation: Side.white,
      createdAt: DateTime(2026),
    ));
    await tester.pumpWidget(await _app(const {}, repository));
    await tester.pump();
    await tester.pump();

    expect(find.text('Endgames'), findsOneWidget);
    expect(find.text('1 puzzle \u00b7 0 solved'), findsOneWidget);

    await tester.tap(find.text('Endgames'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Endgames'), findsOneWidget);
    expect(find.text('1'), findsOneWidget); // the index badge
    expect(find.textContaining('Tap a puzzle to open it'), findsOneWidget);
  });

  testWidgets('Set up a position opens Review with an empty board', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(await _app());
    await tester.tap(find.text('Set up a position'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('White has no king.'), findsOneWidget);
  });

  testWidgets('Paste FEN shows parse errors, then opens Review', (tester) async {
    _tallScreen(tester);
    await tester.pumpWidget(await _app());
    await tester.tap(find.text('Paste FEN'));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.enterText(find.byType(TextField), 'hello');
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(find.textContaining('piece placement is not valid'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '4k3/8/8/8/8/8/4P3/4K3 b - - 0 1');
    await tester.tap(find.text('Continue'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('The position is legal.'), findsOneWidget);
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
