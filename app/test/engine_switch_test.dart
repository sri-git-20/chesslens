import 'package:chesslens/src/analysis/analysis_controller.dart';
import 'package:chesslens/src/analysis/analysis_screen.dart';
import 'package:chesslens/src/engine/fake_engine_service.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('analysis started with the engine off sends nothing until it is turned on',
      () async {
    final engine = FakeEngineService();
    final controller = AnalysisController(
      start: Chess.initial,
      engine: engine,
      engineOn: false,
    )..start();
    addTearDown(controller.dispose);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.engineOn, isFalse);
    expect(engine.requests, isEmpty);

    controller.makeMove(NormalMove.fromUci('e2e4'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(engine.requests, isEmpty);

    controller.setEngineOn(true);
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (engine.requests.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(engine.requests, hasLength(1));
    expect(engine.requests.single.fen, contains('4P3'));
  });

  testWidgets('the engine switch shows its label and reports taps', (tester) async {
    var value = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            appBar: AppBar(
              actions: [
                EngineSwitch(
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Engine'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(value, isTrue);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.text('Engine'));
    await tester.pumpAndSettle();
    expect(value, isFalse);
  });
}
