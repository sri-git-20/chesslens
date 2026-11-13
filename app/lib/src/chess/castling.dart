import 'package:dartchess/dartchess.dart';

/// Which castling moves are still allowed, as shown by the four checkboxes in
/// Review.
class CastlingRights {
  const CastlingRights({
    this.whiteKingSide = false,
    this.whiteQueenSide = false,
    this.blackKingSide = false,
    this.blackQueenSide = false,
  });

  static const none = CastlingRights();
  static const all = CastlingRights(
    whiteKingSide: true,
    whiteQueenSide: true,
    blackKingSide: true,
    blackQueenSide: true,
  );

  final bool whiteKingSide;
  final bool whiteQueenSide;
  final bool blackKingSide;
  final bool blackQueenSide;

  bool get isEmpty =>
      !whiteKingSide && !whiteQueenSide && !blackKingSide && !blackQueenSide;

  bool has(Side side, CastlingSide castlingSide) => switch ((side, castlingSide)) {
        (Side.white, CastlingSide.king) => whiteKingSide,
        (Side.white, CastlingSide.queen) => whiteQueenSide,
        (Side.black, CastlingSide.king) => blackKingSide,
        (Side.black, CastlingSide.queen) => blackQueenSide,
      };

  CastlingRights withRight(Side side, CastlingSide castlingSide, bool value) {
    return CastlingRights(
      whiteKingSide: side == Side.white && castlingSide == CastlingSide.king
          ? value
          : whiteKingSide,
      whiteQueenSide: side == Side.white && castlingSide == CastlingSide.queen
          ? value
          : whiteQueenSide,
      blackKingSide: side == Side.black && castlingSide == CastlingSide.king
          ? value
          : blackKingSide,
      blackQueenSide: side == Side.black && castlingSide == CastlingSide.queen
          ? value
          : blackQueenSide,
    );
  }

  /// Keeps only the rights that are also in [other].
  CastlingRights intersect(CastlingRights other) => CastlingRights(
        whiteKingSide: whiteKingSide && other.whiteKingSide,
        whiteQueenSide: whiteQueenSide && other.whiteQueenSide,
        blackKingSide: blackKingSide && other.blackKingSide,
        blackQueenSide: blackQueenSide && other.blackQueenSide,
      );

  /// FEN castling field, for example `KQkq` or `-`.
  String get fen {
    final text = '${whiteKingSide ? 'K' : ''}${whiteQueenSide ? 'Q' : ''}'
        '${blackKingSide ? 'k' : ''}${blackQueenSide ? 'q' : ''}';
    return text.isEmpty ? '-' : text;
  }

  /// Parses a FEN castling field. Unknown characters are ignored.
  factory CastlingRights.fromFen(String field) => CastlingRights(
        whiteKingSide: field.contains('K'),
        whiteQueenSide: field.contains('Q'),
        blackKingSide: field.contains('k'),
        blackQueenSide: field.contains('q'),
      );

  @override
  bool operator ==(Object other) =>
      other is CastlingRights &&
      other.whiteKingSide == whiteKingSide &&
      other.whiteQueenSide == whiteQueenSide &&
      other.blackKingSide == blackKingSide &&
      other.blackQueenSide == blackQueenSide;

  @override
  int get hashCode =>
      Object.hash(whiteKingSide, whiteQueenSide, blackKingSide, blackQueenSide);

  @override
  String toString() => 'CastlingRights($fen)';
}

/// The castling rights that the pieces on [board] make possible: a king on its
/// home square (e1 or e8) and a rook of the same colour on a1/h1 or a8/h8.
CastlingRights inferCastlingRights(Board board) {
  bool has(Square square, Side side, Role role) {
    final piece = board.pieceAt(square);
    return piece != null && piece.color == side && piece.role == role;
  }

  bool possible(Side side, Square king, Square rook) =>
      has(king, side, Role.king) && has(rook, side, Role.rook);

  return CastlingRights(
    whiteKingSide: possible(Side.white, Square.e1, Square.h1),
    whiteQueenSide: possible(Side.white, Square.e1, Square.a1),
    blackKingSide: possible(Side.black, Square.e8, Square.h8),
    blackQueenSide: possible(Side.black, Square.e8, Square.a8),
  );
}

/// The rook squares dartchess expects in a [Setup] for the given [rights].
SquareSet castlingRookSquares(CastlingRights rights) {
  return SquareSet.fromSquares([
    if (rights.whiteKingSide) Square.h1,
    if (rights.whiteQueenSide) Square.a1,
    if (rights.blackKingSide) Square.h8,
    if (rights.blackQueenSide) Square.a8,
  ]);
}
