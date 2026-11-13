import 'package:dartchess/dartchess.dart';

import 'castling.dart';

/// The result of checking a position that the user is editing.
///
/// [problems] are short sentences for the user. [position] is set only when
/// the position is legal, and is the only way to get a [Position] that is
/// safe to send to the engine.
class LegalityReport {
  const LegalityReport._(this.problems, this.position);

  final List<String> problems;
  final Chess? position;

  bool get isLegal => problems.isEmpty && position != null;
}

String _sideName(Side side) => side == Side.white ? 'White' : 'Black';

String _plural(int count, String noun) => count == 1 ? '1 $noun' : '$count ${noun}s';

String _squareList(Iterable<Square> squares) {
  final names = squares.map((s) => s.name).toList();
  return names.length <= 4
      ? names.join(', ')
      : '${names.take(4).join(', ')} and more';
}

/// Checks [board] with [turn] to move and [castling] rights.
///
/// Reports missing or extra kings, too many pieces, pawns on the first or
/// last rank and the side not to move being in check. Castling rights that
/// the pieces do not allow are dropped silently (Review greys them out).
LegalityReport checkLegality(
  Board board,
  Side turn,
  CastlingRights castling,
) {
  final problems = <String>[];

  for (final side in Side.values) {
    final name = _sideName(side);
    final kings = board.piecesOf(side, Role.king).size;
    if (kings == 0) {
      problems.add('$name has no king.');
    } else if (kings > 1) {
      problems.add('$name has $kings kings. Only one is allowed.');
    }
  }

  for (final side in Side.values) {
    final name = _sideName(side);
    final pawns = board.piecesOf(side, Role.pawn).size;
    final knights = board.piecesOf(side, Role.knight).size;
    final bishops = board.piecesOf(side, Role.bishop).size;
    final rooks = board.piecesOf(side, Role.rook).size;
    final queens = board.piecesOf(side, Role.queen).size;
    final total = board.bySide(side).size;

    if (pawns > 8) {
      problems.add('$name has ${_plural(pawns, 'pawn')}. The most is 8.');
    }
    if (total > 16) {
      problems.add('$name has $total pieces. The most is 16.');
    } else {
      // Every piece beyond the starting set must come from a promoted pawn.
      final extra = (knights > 2 ? knights - 2 : 0) +
          (bishops > 2 ? bishops - 2 : 0) +
          (rooks > 2 ? rooks - 2 : 0) +
          (queens > 1 ? queens - 1 : 0);
      final missingPawns = 8 - pawns;
      if (pawns <= 8 && extra > missingPawns) {
        problems.add(
          '$name has too many pieces: $extra extra '
          '${extra == 1 ? 'piece needs' : 'pieces need'} promoted pawns, but '
          'only ${_plural(missingPawns, 'pawn')} ${missingPawns == 1 ? 'is' : 'are'} missing.',
        );
      }
    }
  }

  final badPawns = board.pawns.intersect(SquareSet.backranks);
  if (badPawns.isNotEmpty) {
    problems.add(
      'Pawns can\'t stand on the first or last rank '
      '(${_squareList(badPawns.squares)}).',
    );
  }

  final whiteKing = board.kingOf(Side.white);
  final blackKing = board.kingOf(Side.black);
  final oneKingEach = board.piecesOf(Side.white, Role.king).size == 1 &&
      board.piecesOf(Side.black, Role.king).size == 1 &&
      whiteKing != null &&
      blackKing != null;

  Chess? position;
  if (oneKingEach) {
    final setup = Setup(
      board: board,
      turn: turn,
      castlingRights: castlingRookSquares(castling),
      halfmoves: 0,
      fullmoves: 1,
    );
    // Built without validation so each problem can be reported on its own.
    final candidate = Chess(
      board: board,
      turn: turn,
      castles: Castles.fromSetup(setup),
      halfmoves: 0,
      fullmoves: 1,
    );
    final other = turn.opposite;
    final otherKing = board.kingOf(other)!;
    if (candidate.kingAttackers(otherKing, turn).isNotEmpty) {
      problems.add(
        '${_sideName(other)}\'s king is in check, but it is '
        '${_sideName(turn)}\'s move. Change the side to move or move a piece.',
      );
    } else if (problems.isEmpty) {
      try {
        candidate.validate();
        position = candidate;
      } on PositionSetupException catch (error) {
        problems.add(_describeSetupCause(error.cause, turn));
      }
    }
  }

  if (problems.isEmpty && position == null) {
    // Defensive: anything dartchess rejects that is not covered above.
    problems.add('This position is not legal.');
  }
  return LegalityReport._(List.unmodifiable(problems), position);
}

String _describeSetupCause(IllegalSetupCause cause, Side turn) {
  return switch (cause) {
    IllegalSetupCause.empty => 'The board is empty.',
    IllegalSetupCause.kings => 'Each side needs exactly one king.',
    IllegalSetupCause.oppositeCheck =>
      '${_sideName(turn.opposite)}\'s king is in check, but it is '
          '${_sideName(turn)}\'s move.',
    IllegalSetupCause.pawnsOnBackrank =>
      'Pawns can\'t stand on the first or last rank.',
    IllegalSetupCause.impossibleCheck =>
      '${_sideName(turn)}\'s king is in check from more pieces than is '
          'possible.',
    IllegalSetupCause.variant => 'This position is not legal.',
  };
}
