import 'dart:typed_data';

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/foundation.dart';

/// Everything the Review screen needs. Every way of getting a diagram into the
/// app (scan, paste, saved puzzle) ends by building one of these and opening
/// `ReviewScreen`.
@immutable
class ReviewArgs {
  const ReviewArgs({
    required this.boardFen,
    this.confidence,
    this.sideToMove = Side.white,
    this.orientation = Side.white,
    this.sourceCrop,
    this.puzzleId,
  });

  /// Piece placement only, for example `8/8/8/4k3/8/8/4P3/4K3`.
  final String boardFen;

  /// 64 values, index 0 = a8 ... 63 = h1 (FEN order). Squares below 0.85 are
  /// outlined in amber.
  final List<double>? confidence;

  final Side sideToMove;

  /// The side shown at the bottom of the board.
  final Side orientation;

  /// PNG of the original diagram, shown for comparison.
  final Uint8List? sourceCrop;

  /// Set when editing a saved puzzle.
  final int? puzzleId;
}
