import 'package:dartchess/dartchess.dart';

/// Why a game ended.
enum GameEndReason {
  checkmate,
  stalemate,
  insufficientMaterial,
  threefoldRepetition,
  fiftyMoveRule,
  resignation,
}

/// The end of a game: [winner] is `null` for a draw.
class GameEnd {
  const GameEnd(this.reason, {this.winner});

  final GameEndReason reason;
  final Side? winner;

  bool get isDraw => winner == null;

  String get reasonLabel => switch (reason) {
        GameEndReason.checkmate => 'Checkmate',
        GameEndReason.stalemate => 'Stalemate',
        GameEndReason.insufficientMaterial => 'Insufficient material',
        GameEndReason.threefoldRepetition => 'Threefold repetition',
        GameEndReason.fiftyMoveRule => 'Fifty-move rule',
        GameEndReason.resignation => 'Resignation',
      };

  @override
  bool operator ==(Object other) =>
      other is GameEnd && other.reason == reason && other.winner == winner;

  @override
  int get hashCode => Object.hash(reason, winner);
}

/// Detects the end of a game after the last position in [history].
///
/// [history] holds every position of the game from the first to the current
/// one; it is needed for threefold repetition.
GameEnd? detectGameEnd(List<Position> history) {
  final position = history.last;
  if (position.isCheckmate) {
    return GameEnd(GameEndReason.checkmate, winner: position.turn.opposite);
  }
  if (position.isStalemate) return const GameEnd(GameEndReason.stalemate);
  if (position.isInsufficientMaterial) {
    return const GameEnd(GameEndReason.insufficientMaterial);
  }
  if (position.halfmoves >= 100) return const GameEnd(GameEndReason.fiftyMoveRule);
  final hash = position.zobristHash();
  var count = 0;
  for (final earlier in history) {
    if (earlier.zobristHash() == hash) count++;
  }
  if (count >= 3) return const GameEnd(GameEndReason.threefoldRepetition);
  return null;
}
