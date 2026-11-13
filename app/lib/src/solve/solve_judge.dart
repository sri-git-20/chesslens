import '../engine/uci.dart';

/// A move is accepted when it is within this many centipawns of the best move.
const int solveToleranceCp = 50;

/// At or above this score the solver counts as winning.
const int solveWinningCp = 150;

enum MoveVerdict { correct, notBest }

class JudgeResult {
  const JudgeResult(this.verdict, this.reason);

  final MoveVerdict verdict;

  /// A short explanation, for logs and tests.
  final String reason;

  bool get isCorrect => verdict == MoveVerdict.correct;

  @override
  String toString() => '${verdict.name}: $reason';
}

/// Decides whether the solver's move is acceptable.
///
/// [best] is the engine's score for the best move and [played] its score for
/// the move the user played, both from the solver's point of view and
/// measured at the same depth.
///
/// Rules:
///  - If the best move keeps a forced mate for the solver, the move is correct
///    only if it keeps a forced mate too (any length).
///  - If the solver is being mated whatever he does, a move is correct unless
///    it gets mated sooner than the best defence.
///  - In a drawn position (best within +-0.50), a move is correct while it
///    stays within that band.
///  - Otherwise a move is correct if it is within 0.50 pawns of the best move
///    and does not drop from winning (+1.50 or more) to not winning.
JudgeResult judgeSolverMove({required UciScore best, required UciScore played}) {
  if (best.isMating) {
    return played.isMating
        ? const JudgeResult(MoveVerdict.correct, 'keeps the forced mate')
        : const JudgeResult(MoveVerdict.notBest, 'loses the forced mate');
  }

  if (best.isMated) {
    if (!played.isMated) {
      return const JudgeResult(MoveVerdict.correct, 'avoids being mated');
    }
    return played.mate!.abs() >= best.mate!.abs()
        ? const JudgeResult(MoveVerdict.correct, 'resists as long as the best defence')
        : const JudgeResult(MoveVerdict.notBest, 'gets mated sooner');
  }

  // The best move is a centipawn score from here on.
  final bestCp = best.cp!;
  if (played.isMating) {
    return const JudgeResult(MoveVerdict.correct, 'finds a forced mate');
  }
  if (played.isMated) {
    return const JudgeResult(MoveVerdict.notBest, 'allows a forced mate');
  }
  final playedCp = played.cp!;

  if (bestCp.abs() <= solveToleranceCp) {
    return playedCp >= -solveToleranceCp
        ? const JudgeResult(MoveVerdict.correct, 'keeps the draw')
        : const JudgeResult(MoveVerdict.notBest, 'drops out of the drawn band');
  }
  if (bestCp >= solveWinningCp && playedCp < solveWinningCp) {
    return const JudgeResult(MoveVerdict.notBest, 'throws away the win');
  }
  return playedCp >= bestCp - solveToleranceCp
      ? const JudgeResult(MoveVerdict.correct, 'within 0.5 pawns of the best move')
      : const JudgeResult(MoveVerdict.notBest, 'more than 0.5 pawns worse than the best move');
}
