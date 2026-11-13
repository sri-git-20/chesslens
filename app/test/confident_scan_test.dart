import 'package:chesslens/src/board/review_args.dart';
import 'package:chesslens/src/board/review_model.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

ReviewArgs _args(String placement, {double confidence = 0.99, int? lowAt}) {
  final values = List<double>.filled(64, confidence);
  if (lowAt != null) values[lowAt] = 0.4;
  return ReviewArgs(boardFen: placement, confidence: values);
}

void main() {
  test('a confident, legal scan opens straight in analysis, White to move', () {
    final ready = confidentScanPosition(_args('4k3/8/8/8/8/8/8/4K3'));
    expect(ready, isNotNull);
    expect(ready!.args.sideToMove, Side.white);
    expect(ready.fen.split(' ')[1], 'w');
  });

  test('one hard-to-read square sends the scan to Review', () {
    expect(confidentScanPosition(_args('4k3/8/8/8/8/8/8/4K3', lowAt: 12)), isNull);
  });

  test('Black to move is chosen when only that is legal', () {
    // The black king on e8 is in check from the rook on e2.
    final ready = confidentScanPosition(_args('4k3/8/8/8/8/8/4R3/K7'));
    expect(ready, isNotNull);
    expect(ready!.args.sideToMove, Side.black);
    expect(ready.fen.split(' ')[1], 'b');
  });

  test('an illegal position goes to Review', () {
    expect(confidentScanPosition(_args('8/8/8/8/8/8/8/8')), isNull);
  });

  test('no confidence values (not a scan) goes to Review', () {
    expect(
      confidentScanPosition(const ReviewArgs(boardFen: '4k3/8/8/8/8/8/8/4K3')),
      isNull,
    );
  });
}
