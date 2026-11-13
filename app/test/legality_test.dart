import 'package:chesslens/src/chess/board_utils.dart';
import 'package:chesslens/src/chess/castling.dart';
import 'package:chesslens/src/chess/fen_input.dart';
import 'package:chesslens/src/chess/legality.dart';
import 'package:chesslens/src/chess/san.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

LegalityReport check(String placement, {Side turn = Side.white, CastlingRights? castling}) {
  final board = Board.parseFen(placement);
  return checkLegality(board, turn, castling ?? inferCastlingRights(board));
}

void main() {
  group('legality report', () {
    test('the start position is legal', () {
      final report = check(startPlacement);
      expect(report.isLegal, isTrue);
      expect(report.problems, isEmpty);
      expect(report.position!.fen, 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1');
    });

    test('an empty board has no kings', () {
      final report = check(emptyPlacement);
      expect(report.isLegal, isFalse);
      expect(report.position, isNull);
      expect(report.problems, contains('White has no king.'));
      expect(report.problems, contains('Black has no king.'));
    });

    test('one missing king', () {
      final report = check('8/8/8/8/8/8/8/K7');
      expect(report.problems, ['Black has no king.']);
    });

    test('too many kings', () {
      final report = check('kk6/8/8/8/8/8/8/K7');
      expect(report.problems, ['Black has 2 kings. Only one is allowed.']);
    });

    test('pawns on the first or last rank', () {
      final report = check('k6P/8/8/8/8/8/8/Kp6');
      expect(report.isLegal, isFalse);
      expect(
        report.problems.single,
        allOf(contains('first or last rank'), contains('h8'), contains('b1')),
      );
    });

    test('more than eight pawns', () {
      final report = check('k7/pppppppp/p7/8/8/8/PPPPPPPP/K7');
      expect(report.problems, contains('Black has 9 pawns. The most is 8.'));
    });

    test('more than sixteen pieces', () {
      final report = check('kqqqqqqq/qqqqqqqq/q7/8/8/8/8/K7');
      expect(report.problems.any((p) => p.contains('17 pieces')), isTrue);
    });

    test('extra pieces need missing pawns', () {
      // White keeps all 8 pawns but has a second queen.
      final report = check('k7/8/8/8/8/8/PPPPPPPP/KQQ5');
      expect(report.isLegal, isFalse);
      expect(report.problems.single, contains('too many pieces'));
    });

    test('promotion explains extra pieces', () {
      // Seven pawns and two queens is fine.
      final report = check('k7/8/8/8/8/8/PPPPPPP1/KQQ5');
      expect(report.isLegal, isTrue);
    });

    test('the side not to move must not be in check', () {
      // Black king on e8 attacked by the rook on e1, White to move.
      final report = check('4k3/8/8/8/8/8/8/K3R3');
      expect(report.isLegal, isFalse);
      expect(report.problems.single, contains("Black's king is in check"));
      // The same position is fine with Black to move.
      expect(check('4k3/8/8/8/8/8/8/K3R3', turn: Side.black).isLegal, isTrue);
    });

    test('kings next to each other', () {
      final report = check('8/8/8/3kK3/8/8/8/8');
      expect(report.isLegal, isFalse);
    });

    test('checkmate and stalemate positions are legal positions', () {
      expect(check('7k/5Q2/6K1/8/8/8/8/8', turn: Side.black).isLegal, isTrue);
    });
  });

  group('castling', () {
    test('inferred from king and rook home squares', () {
      expect(inferCastlingRights(Board.parseFen(startPlacement)), CastlingRights.all);
      expect(
        inferCastlingRights(Board.parseFen('r3k2r/8/8/8/8/8/8/R3K2R')).fen,
        'KQkq',
      );
      expect(inferCastlingRights(Board.parseFen('4k2r/8/8/8/8/8/8/R3K3')).fen, 'Qk');
      expect(inferCastlingRights(Board.parseFen('r3k3/8/8/8/8/8/8/4K2R')).fen, 'Kq');
    });

    test('not inferred when the king or rook is elsewhere', () {
      expect(inferCastlingRights(Board.parseFen('8/8/8/8/8/8/8/R2K3R')), CastlingRights.none);
      expect(inferCastlingRights(Board.parseFen('4k3/8/8/8/8/8/8/R3K2N')).fen, 'Q');
      expect(inferCastlingRights(Board.parseFen('4k3/8/8/8/8/8/8/R3K2r')).fen, 'Q');
    });

    test('rights end up in the full FEN, and impossible ones are dropped', () {
      final board = Board.parseFen('r3k2r/8/8/8/8/8/8/R3K2R');
      final fen = buildFullFen(
        board: board,
        turn: Side.black,
        castling: const CastlingRights(whiteKingSide: true, blackQueenSide: true),
      );
      expect(fen, 'r3k2r/8/8/8/8/8/8/R3K2R b Kq - 0 1');
      final dropped = buildFullFen(
        board: Board.parseFen('4k3/8/8/8/8/8/8/4K3'),
        turn: Side.white,
        castling: CastlingRights.all,
      );
      expect(dropped, '4k3/8/8/8/8/8/8/4K3 w - - 0 1');
    });

    test('FEN field round trip', () {
      expect(CastlingRights.fromFen('Kq').fen, 'Kq');
      expect(CastlingRights.fromFen('-'), CastlingRights.none);
      expect(CastlingRights.none.fen, '-');
    });
  });

  group('board helpers', () {
    test('buildPosition returns null for illegal choices', () {
      expect(
        buildPosition(
          board: Board.empty,
          turn: Side.white,
          castling: CastlingRights.none,
        ),
        isNull,
      );
    });

    test('rotating twice is the identity', () {
      final board = Board.parseFen('r3k2r/ppp2ppp/8/8/8/8/PPPP1PPP/R3K2R');
      expect(rotateBoard(rotateBoard(board)), board);
      expect(rotateBoard(Board.standard).fen, 'RNBKQBNR/PPPPPPPP/8/8/8/8/pppppppp/rnbkqbnr');
    });

    test('chessFromFen', () {
      expect(chessFromFen('8/8/8/8/8/8/8/8 w - - 0 1'), isNull);
      expect(chessFromFen('not a fen'), isNull);
      expect(chessFromFen('4k3/8/8/8/8/8/8/4K3 w - - 0 1'), isNotNull);
    });
  });

  group('FEN input', () {
    test('placement only', () {
      final input = parseFenInput('  4k3/8/8/8/8/8/4P3/4K3 ');
      expect(input.isPlacementOnly, isTrue);
      expect(input.turn, Side.white);
      expect(input.placement, '4k3/8/8/8/8/8/4P3/4K3');
      expect(input.castling, CastlingRights.none);
    });

    test('placement only infers castling', () {
      expect(parseFenInput(startPlacement).castling, CastlingRights.all);
    });

    test('full fen', () {
      final input = parseFenInput('r3k2r/8/8/8/8/8/8/R3K2R b Kq - 3 20');
      expect(input.isPlacementOnly, isFalse);
      expect(input.turn, Side.black);
      expect(input.castling.fen, 'Kq');
    });

    test('a full fen without castling rights stays without them', () {
      expect(parseFenInput('r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1').castling, CastlingRights.none);
    });

    test('errors are readable', () {
      for (final bad in ['', 'hello', '8/8/8/8/8/8/8 w - - 0 1', '8/8/8/8/8/8/8/8 x - - 0 1']) {
        expect(
          () => parseFenInput(bad),
          throwsA(isA<FenInputException>()),
          reason: bad,
        );
      }
      try {
        parseFenInput('8/8/8/8/8/8/8/8 x - - 0 1');
      } on FenInputException catch (error) {
        expect(error.message, contains('w or b'));
      }
    });
  });

  group('SAN helpers', () {
    test('principal variation to SAN with numbers', () {
      final position = Chess.initial;
      expect(pvToSan(position, ['e2e4', 'e7e5', 'g1f3']), '1. e4 e5 2. Nf3');
      final afterE4 = position.playUnchecked(NormalMove.fromUci('e2e4'));
      expect(pvToSan(afterE4, ['e7e5', 'g1f3']), '1... e5 2. Nf3');
    });

    test('stops at an illegal move', () {
      expect(pvToSan(Chess.initial, ['e2e4', 'e2e4', 'g1f3']), '1. e4');
    });

    test('castling in both notations', () {
      final position = Chess.fromSetup(Setup.parseFen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1'));
      expect(playUci(position, 'e1g1')!.$2, 'O-O');
      expect(playUci(position, 'e1c1')!.$2, 'O-O-O');
      final move = NormalMove.fromUci('e1h1');
      expect(engineUci(position, move), 'e1g1');
      expect(engineUci(position, NormalMove.fromUci('e1d1')), 'e1d1');
      expect(engineUci(position, NormalMove.fromUci('a1a8')), 'a1a8');
    });
  });
}
