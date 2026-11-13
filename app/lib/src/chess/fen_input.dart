import 'package:dartchess/dartchess.dart';

import 'castling.dart';

/// A FEN typed or pasted by the user, either a full FEN or just the piece
/// placement (`8/8/4k3/8/8/4K3/8/8`).
class FenInput {
  const FenInput({
    required this.board,
    required this.turn,
    required this.castling,
    required this.isPlacementOnly,
  });

  final Board board;

  /// Side to move; [Side.white] when the FEN has no turn field.
  final Side turn;

  /// Castling rights from the FEN, or inferred from the pieces when the FEN
  /// has no castling field.
  final CastlingRights castling;

  final bool isPlacementOnly;

  String get placement => board.fen;
}

/// Thrown by [parseFenInput] with a message that is fit to show to the user.
class FenInputException implements Exception {
  const FenInputException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Parses a full FEN or a placement-only FEN.
///
/// Throws [FenInputException] when the text is not usable.
FenInput parseFenInput(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw const FenInputException('Enter a FEN first.');
  }
  final fields = trimmed.split(RegExp(r'[\s_]+'));
  if (fields.length > 6) {
    throw const FenInputException(
      'A FEN has at most six parts separated by spaces.',
    );
  }
  final Setup setup;
  try {
    setup = Setup.parseFen(trimmed);
  } on FenException catch (error) {
    throw FenInputException(_describeFenCause(error.cause));
  } catch (_) {
    throw const FenInputException('This is not a valid FEN.');
  }
  final placementOnly = fields.length == 1;
  final hasCastlingField = fields.length >= 3;
  final board = setup.board;
  final castling = hasCastlingField
      ? _castlingFromSetup(setup)
      : inferCastlingRights(board);
  return FenInput(
    board: board,
    turn: setup.turn,
    castling: castling,
    isPlacementOnly: placementOnly,
  );
}

CastlingRights _castlingFromSetup(Setup setup) {
  final rights = setup.castlingRights;
  final board = setup.board;
  bool has(Square rook, Side side) =>
      rights.has(rook) &&
      board.pieceAt(rook)?.color == side &&
      board.pieceAt(rook)?.role == Role.rook;
  // Rights are rook squares. Shredder-FEN style files other than a and h are
  // mapped to the nearest side of the king.
  var result = CastlingRights.none;
  for (final side in Side.values) {
    final king = board.kingOf(side);
    if (king == null) continue;
    final backrank = side == Side.white ? Rank.first : Rank.eighth;
    if (king.rank != backrank) continue;
    for (final rook in rights.squares) {
      if (rook.rank != backrank || !has(rook, side)) continue;
      result = result.withRight(
        side,
        rook.file > king.file ? CastlingSide.king : CastlingSide.queen,
        true,
      );
    }
  }
  return result;
}

String _describeFenCause(IllegalFenCause cause) => switch (cause) {
      IllegalFenCause.board =>
        'The piece placement is not valid. Each of the 8 ranks needs exactly '
            '8 squares.',
      IllegalFenCause.turn => 'The side to move must be w or b.',
      IllegalFenCause.castling => 'The castling part of the FEN is not valid.',
      IllegalFenCause.enPassant =>
        'The en passant part of the FEN is not valid.',
      IllegalFenCause.halfmoveClock ||
      IllegalFenCause.fullmoveNumber =>
        'The move counters in the FEN must be numbers.',
      _ => 'This is not a valid FEN.',
    };
