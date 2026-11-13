import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:chesslens/src/scan/geometry.dart';
import 'package:chesslens/src/scan/interpreter_models.dart';
import 'package:chesslens/src/scan/model_decode.dart';
import 'package:chesslens/src/scan/scan_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const _fixtures = 'test/fixtures/scan';
const _models = 'assets/models';

double _cornerDistance(Quad a, Quad b) {
  var total = 0.0;
  for (var i = 0; i < 4; i++) {
    total += math.sqrt(
      math.pow(a.points[i].x - b.points[i].x, 2) + math.pow(a.points[i].y - b.points[i].y, 2),
    );
  }
  return total / 4;
}

Quad _quadOf(Object json) => Quad([
      for (final p in json as List) Pt((p as List)[0] as double, p[1] as double),
    ]);

int _squareDiffs(String a, String b) {
  List<String> expand(String fen) => [
        for (final ch in fen.replaceAll('/', '').split(''))
          if (int.tryParse(ch) != null) ...List.filled(int.parse(ch), '.') else ch,
      ];
  final x = expand(a);
  final y = expand(b);
  var diffs = 0;
  for (var i = 0; i < 64; i++) {
    if (x[i] != y[i]) diffs++;
  }
  return diffs;
}

/// Creates the interpreters, or returns why that is not possible here (the
/// LiteRT native library is bundled by the app build, not by `flutter test`).
(InterpreterModels?, String?) _tryModels() {
  for (final name in ['detector', 'corners', 'squares']) {
    if (!File('$_models/$name.tflite').existsSync()) {
      return (null, 'model file $name.tflite is missing');
    }
  }
  try {
    return (
      InterpreterModels.fromFiles(
        detector: '$_models/detector.tflite',
        corners: '$_models/corners.tflite',
        squares: '$_models/squares.tflite',
      ),
      null,
    );
  } catch (error) {
    return (null, 'the LiteRT native library cannot be loaded here ($error)');
  }
}

void main() {
  test('Dart pipeline matches the reference pipeline on the fixtures', () {
    final expectedFile = File('$_fixtures/expected.json');
    if (!expectedFile.existsSync()) {
      markTestSkipped('no fixtures in $_fixtures');
      return;
    }
    final (models, reason) = _tryModels();
    if (models == null) {
      markTestSkipped('Skipped: $reason');
      return;
    }
    final doc = jsonDecode(expectedFile.readAsStringSync()) as Map<String, dynamic>;
    final engine = ScanEngine(models.pipeline);
    var key = 0;
    var boardsChecked = 0;
    var totalDiffs = 0;
    var worstCorner = 0.0;
    var truthSquares = 0;
    var truthWrong = 0;

    for (final entry in doc['images'] as List) {
      final image = entry as Map<String, dynamic>;
      final file = image['file'] as String;
      final bytes = File('$_fixtures/$file').readAsBytesSync();
      final analysis = engine.analyze(++key, EncodedInput(bytes));
      final reference = (image['reference'] as Map<String, dynamic>)['boards'] as List;
      expect(analysis.boards.length, reference.length, reason: '$file: board count');

      final unused = [...analysis.boards];
      for (final r in reference) {
        final ref = r as Map<String, dynamic>;
        final refQuad = _quadOf(ref['quad'] as Object);
        unused.sort(
          (a, b) => _cornerDistance(a.quad, refQuad).compareTo(_cornerDistance(b.quad, refQuad)),
        );
        final match = unused.removeAt(0);
        final distance = _cornerDistance(match.quad, refQuad);
        worstCorner = math.max(worstCorner, distance);
        expect(distance, lessThan(4), reason: '$file: corners differ from the reference');
        final fen = placementFromClasses(squareClasses(match.probs));
        final diffs = _squareDiffs(fen, ref['fen'] as String);
        totalDiffs += diffs;
        expect(diffs, lessThanOrEqualTo(2), reason: '$file: squares differ from the reference');
        boardsChecked++;
      }

      // How good is the model itself against the ground truth?
      for (final t in image['boards'] as List) {
        final truth = t as Map<String, dynamic>;
        final truthQuad = _quadOf(truth['quad'] as Object);
        final close = analysis.boards.where((b) => _cornerDistance(b.quad, truthQuad) < 8);
        if (close.isEmpty) continue;
        final best = close.reduce(
          (a, b) => _cornerDistance(a.quad, truthQuad) < _cornerDistance(b.quad, truthQuad) ? a : b,
        );
        truthSquares += 64;
        truthWrong += _squareDiffs(
          placementFromClasses(squareClasses(best.probs)),
          truth['fen'] as String,
        );
      }
    }
    models.close();
    // ignore: avoid_print
    print(
      'fixtures: $boardsChecked boards, worst corner distance to reference '
      '${worstCorner.toStringAsFixed(2)} px, $totalDiffs square differences to the '
      'reference, ground-truth squares wrong $truthWrong of $truthSquares',
    );
    expect(boardsChecked, greaterThan(0));
  });
}
