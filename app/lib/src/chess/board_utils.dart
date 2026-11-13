import 'package:dartchess/dartchess.dart';

import 'castling.dart';
import 'legality.dart';

/// The standard starting position, piece placement only.
const String startPlacement = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR';

/// An empty board, piece placement only.
const String emptyPlacement = '8/8/8/8/8/8/8/8';

/// Turns the board around 180 degrees: a1 becomes h8, white pieces stay
/// white. This is "flip" in the sense of looking at the same position from
/// the other side, applied to the squares, not the colours.
Board rotateBoard(Board board) {
  var result = Board.empty;
  for (final (square, piece) in board.pieces) {
    final rotated = Square(63 - square.value);
    result = result.setPieceAt(rotated, piece);
  }
  return result;
}

/// The opposite side, for flipping the board view.
Side flipSide(Side side) => side.opposite;

/// Builds a playable position from Review choices.
///
/// Returns `null` when the choices are not a legal position. Use
/// [checkLegality] to find out why.
Chess? buildPosition({
  required Board board,
  required Side turn,
  required CastlingRights castling,
}) {
  return checkLegality(board, turn, castling).position;
}

/// The full FEN of a legal position built from Review choices.
String? buildFullFen({
  required Board board,
  required Side turn,
  required CastlingRights castling,
}) => buildPosition(board: board, turn: turn, castling: castling)?.fen;

/// Parses a full FEN into a legal [Chess] position, or returns `null`.
Chess? chessFromFen(String fen) {
  try {
    return Chess.fromSetup(Setup.parseFen(fen));
  } catch (_) {
    return null;
  }
}
