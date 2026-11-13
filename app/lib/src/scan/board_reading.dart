import 'dart:math' as math;
import 'dart:typed_data';

import 'package:dartchess/dartchess.dart';

import '../chess/castling.dart';
import '../chess/legality.dart';
import 'model_decode.dart';

const int _wP = 1, _wK = 6, _bP = 7, _bK = 12;

/// Whether the evidence clearly says Black is at the bottom of the diagram.
///
/// [classes] are the 64 arg-max classes as drawn (row 0 at the top). Pawns
/// count one point each for standing on the side of their own colour's far
/// half; kings count double. The board is flipped only when the total is at
/// least 3.
bool blackAtBottom(Uint8List classes) {
  var pawnScore = 0;
  int? whiteKingRow;
  int? blackKingRow;
  for (var i = 0; i < 64; i++) {
    final row = i ~/ 8;
    final top = row < 4;
    switch (classes[i]) {
      case _wP:
        pawnScore += top ? 1 : -1;
      case _bP:
        pawnScore += top ? -1 : 1;
      case _wK:
        whiteKingRow = row;
      case _bK:
        blackKingRow = row;
    }
  }
  var kingScore = 0;
  if (whiteKingRow != null) {
    if (whiteKingRow <= 1) kingScore++;
    if (whiteKingRow >= 6) kingScore--;
  }
  if (blackKingRow != null) {
    if (blackKingRow >= 6) kingScore++;
    if (blackKingRow <= 1) kingScore--;
  }
  return pawnScore + 2 * kingScore >= 3;
}

/// Turns the board 180 degrees: square i becomes square 63 - i.
Float32List rotateProbs(Float32List probs) {
  final out = Float32List(probs.length);
  for (var i = 0; i < 64; i++) {
    out.setRange(
      (63 - i) * classCount,
      (64 - i) * classCount,
      probs,
      i * classCount,
    );
  }
  return out;
}

bool _isLegal(Uint8List classes) {
  try {
    final board = Board.parseFen(placementFromClasses(classes));
    return checkLegality(board, Side.white, CastlingRights.none).isLegal ||
        checkLegality(board, Side.black, CastlingRights.none).isLegal;
  } catch (_) {
    return false;
  }
}

/// A position after the optional repair.
class RepairResult {
  const RepairResult(this.classes, this.changed);

  final Uint8List classes;

  /// Squares whose class was changed to the second-best guess.
  final List<int> changed;
}

/// If the arg-max position is illegal, tries the second most likely class on
/// the least confident squares (up to three squares at once, chosen among the
/// [candidates] least confident) and returns the most probable legal result.
/// Returns the arg-max position unchanged when nothing legal is found.
RepairResult repairPosition(Float32List probs, {int candidates = 8, int maxSwaps = 3}) {
  final base = squareClasses(probs);
  if (_isLegal(base)) return RepairResult(base, const []);

  double p(int square, int cls) => probs[square * classCount + cls];
  double cost(int square, int alt) =>
      math.log(math.max(p(square, base[square]), 1e-9)) - math.log(math.max(p(square, alt), 1e-9));

  final alternatives = <int, int>{};
  for (var i = 0; i < 64; i++) {
    int? second;
    for (var c = 0; c < classCount; c++) {
      if (c == base[i]) continue;
      if (second == null || p(i, c) > p(i, second)) second = c;
    }
    if (second != null && p(i, second) > 1e-4) alternatives[i] = second;
  }
  final order = alternatives.keys.toList()
    ..sort((a, b) => p(a, base[a]).compareTo(p(b, base[b])));
  final pool = order.take(candidates).toList();

  List<int>? bestSet;
  var bestCost = double.infinity;

  void search(int from, List<int> chosen, double total) {
    if (chosen.isNotEmpty && total < bestCost) {
      final trial = Uint8List.fromList(base);
      for (final s in chosen) {
        trial[s] = alternatives[s]!;
      }
      if (_isLegal(trial)) {
        bestCost = total;
        bestSet = List.of(chosen);
      }
    }
    if (chosen.length == maxSwaps) return;
    for (var k = from; k < pool.length; k++) {
      final s = pool[k];
      chosen.add(s);
      search(k + 1, chosen, total + cost(s, alternatives[s]!));
      chosen.removeLast();
    }
  }

  search(0, [], 0);
  final set = bestSet;
  if (set == null) return RepairResult(base, const []);
  final fixed = Uint8List.fromList(base);
  for (final s in set) {
    fixed[s] = alternatives[s]!;
  }
  return RepairResult(fixed, List.unmodifiable(set..sort()));
}

/// One board after post-processing: ready for the Review screen.
class BoardReading {
  const BoardReading({
    required this.placement,
    required this.confidence,
    required this.orientation,
    required this.repaired,
    required this.isLegal,
  });

  /// Piece placement with rank 8 first (as White sees it).
  final String placement;

  /// 64 values in FEN order (a8 ... h1).
  final List<double> confidence;

  /// The side shown at the bottom in the book.
  final Side orientation;

  /// Squares (FEN order) that were changed by the legality repair.
  final List<int> repaired;

  /// Whether the placement is legal for at least one side to move.
  final bool isLegal;
}

/// Orientation, legality repair and confidence mapping for one board.
///
/// [probs] are the squares model output (64 x 13, row 0 = top as drawn).
BoardReading interpretBoard(Float32List probs) {
  final drawn = squareClasses(probs);
  final flip = blackAtBottom(drawn);
  final oriented = flip ? rotateProbs(probs) : probs;
  final repair = repairPosition(oriented);
  final confidence = [
    for (var i = 0; i < 64; i++) oriented[i * classCount + repair.classes[i]],
  ];
  return BoardReading(
    placement: placementFromClasses(repair.classes),
    confidence: List.unmodifiable(confidence),
    orientation: flip ? Side.black : Side.white,
    repaired: repair.changed,
    isLegal: _isLegal(repair.classes),
  );
}
