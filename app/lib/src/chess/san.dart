import 'package:dartchess/dartchess.dart';

/// Parses a UCI move such as `e2e4` or `e7e8q`, or returns `null`.
Move? parseUciMove(String uci) => Move.parse(uci);

/// Plays [uci] from [position] if it is legal, accepting both castling
/// notations (`e1g1` and king takes own rook).
(Position, String)? playUci(Position position, String uci) {
  final move = Move.parse(uci);
  if (move == null) return null;
  final normalized = move is NormalMove ? position.normalizeMove(move) : move;
  if (!position.isLegal(normalized)) return null;
  return position.makeSan(normalized);
}

/// Formats a principal variation, given as UCI moves, as SAN with move
/// numbers: `12. Nf3 Nc6 13. Bb5`. Black to move starts with `12...`.
///
/// Stops at the first move that is not legal and returns what it has.
String pvToSan(Position position, Iterable<String> uciMoves, {int maxPlies = 10}) {
  final parts = <String>[];
  var current = position;
  var first = true;
  var plies = 0;
  for (final uci in uciMoves) {
    if (plies >= maxPlies) break;
    final result = playUci(current, uci);
    if (result == null) break;
    final number = current.fullmoves;
    if (current.turn == Side.white) {
      parts.add('$number.');
    } else if (first) {
      parts.add('$number...');
    }
    parts.add(result.$2);
    current = result.$1;
    first = false;
    plies++;
  }
  return parts.join(' ');
}

/// The UCI string to send to an engine for [move] in [position]: castling is
/// written as the king moving two squares (`e1g1`), not as king takes rook.
String engineUci(Position position, Move move) {
  if (move is! NormalMove) return move.uci;
  final piece = position.board.pieceAt(move.from);
  final target = position.board.pieceAt(move.to);
  if (piece != null &&
      piece.role == Role.king &&
      target != null &&
      target.color == piece.color &&
      target.role == Role.rook) {
    final file = move.to.file > move.from.file ? File.g : File.c;
    return '${move.from.name}${file.name}${move.from.rank.name}';
  }
  return move.uci;
}
