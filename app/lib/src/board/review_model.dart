import 'package:chessground/chessground.dart' show Pieces;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../chess/castling.dart';
import '../chess/legality.dart';
import 'review_args.dart';

/// Squares with a confidence below this are outlined in Review.
const double lowConfidenceThreshold = 0.85;

/// The position being reviewed and every choice the user can make about it.
///
/// A plain [ChangeNotifier], so it can be tested without widgets.
class ReviewModel extends ChangeNotifier {
  ReviewModel({
    required Board board,
    Side turn = Side.white,
    CastlingRights? castling,
    Side orientation = Side.white,
    Set<Square> flagged = const {},
  })  : _board = board,
        _turn = turn,
        _orientation = orientation,
        _flagged = {...flagged} {
    _castling = (castling ?? inferCastlingRights(board)).intersect(inferCastlingRights(board));
    _report = checkLegality(_board, _turn, _castling);
  }

  /// Builds the model from [args]. Returns the model and an error message when
  /// the FEN in [args] could not be read (the board is then empty).
  static (ReviewModel, String?) fromArgs(ReviewArgs args) {
    Board board;
    String? error;
    try {
      board = Board.parseFen(args.boardFen.trim().split(RegExp(r'\s+')).first);
    } catch (_) {
      board = Board.empty;
      error = 'The position could not be read. Set it up on the board.';
    }
    final flagged = <Square>{};
    final confidence = args.confidence;
    if (confidence != null && confidence.length == 64) {
      for (var index = 0; index < 64; index++) {
        if (confidence[index] < lowConfidenceThreshold) {
          flagged.add(squareFromFenIndex(index));
        }
      }
    }
    final model = ReviewModel(
      board: board,
      turn: args.sideToMove,
      orientation: args.orientation,
      flagged: flagged,
    );
    return (model, error);
  }

  /// Index 0 = a8 ... 63 = h1.
  static Square squareFromFenIndex(int index) =>
      Square.fromCoords(File(index % 8), Rank(7 - index ~/ 8));

  Board _board;
  Side _turn;
  Side _orientation;
  late CastlingRights _castling;
  Set<Square> _flagged;
  late LegalityReport _report;

  Board get board => _board;
  Side get turn => _turn;
  Side get orientation => _orientation;
  CastlingRights get castling => _castling;

  /// Squares the recognizer was unsure about and the user has not touched.
  Set<Square> get flagged => Set.unmodifiable(_flagged);

  LegalityReport get report => _report;

  /// Castling rights that the pieces on the board allow.
  CastlingRights get availableCastling => inferCastlingRights(_board);

  /// The full FEN, or `null` while the position is not legal.
  String? get fullFen => _report.position?.fen;

  /// The pieces in the form chessground's board editor wants.
  Pieces get pieces => {
        for (final (square, piece) in _board.pieces) square: piece,
      };

  void _setBoard(Board next, Iterable<Square> touched) {
    final before = inferCastlingRights(_board);
    _board = next;
    _flagged = {..._flagged}..removeAll(touched);
    final after = inferCastlingRights(next);
    // A right that just became possible is switched on; one that stopped being
    // possible is switched off. Choices on unaffected rights stay.
    var result = _castling.intersect(after);
    for (final side in Side.values) {
      for (final castlingSide in CastlingSide.values) {
        if (after.has(side, castlingSide) && !before.has(side, castlingSide)) {
          result = result.withRight(side, castlingSide, true);
        }
      }
    }
    _castling = result;
    _recheck();
  }

  void _recheck() {
    _report = checkLegality(_board, _turn, _castling);
    notifyListeners();
  }

  void putPiece(Square square, Piece piece) {
    _setBoard(_board.setPieceAt(square, Piece(color: piece.color, role: piece.role)), [square]);
  }

  void removePiece(Square square) {
    if (_board.pieceAt(square) == null) {
      _flagged = {..._flagged}..remove(square);
      notifyListeners();
      return;
    }
    _setBoard(_board.removePieceAt(square), [square]);
  }

  /// Handles a drop from [origin] (or from the palette when `null`).
  void dropPiece(Square? origin, Square destination, Piece piece) {
    var next = _board;
    final touched = <Square>[destination];
    if (origin != null && origin != destination) {
      next = next.removePieceAt(origin);
      touched.add(origin);
    }
    next = next.setPieceAt(destination, Piece(color: piece.color, role: piece.role));
    _setBoard(next, touched);
  }

  void clear() {
    _flagged = {};
    _setBoard(Board.empty, const []);
  }

  void startPosition() {
    _flagged = {};
    _setBoard(Board.standard, const []);
    _castling = CastlingRights.all;
    _recheck();
  }

  void setTurn(Side side) {
    if (side == _turn) return;
    _turn = side;
    _recheck();
  }

  void setCastling(Side side, CastlingSide castlingSide, bool value) {
    if (value && !availableCastling.has(side, castlingSide)) return;
    _castling = _castling.withRight(side, castlingSide, value);
    _recheck();
  }

  void flip() {
    _orientation = _orientation.opposite;
    notifyListeners();
  }

  /// Applies castling rights read from a saved puzzle's FEN.
  void applyCastling(CastlingRights rights) {
    _castling = rights.intersect(availableCastling);
    _recheck();
  }
}
