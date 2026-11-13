import 'package:chesslens/src/analysis/move_tree.dart';
import 'package:chesslens/src/collections/models.dart';
import 'package:chesslens/src/export/pgn.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

const startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
const endgameFen = '8/8/8/4k3/8/8/4P3/4K3 b - - 3 40';

Puzzle puzzle(String fen) => Puzzle(
      id: 1,
      collectionId: 1,
      fen: fen,
      orientation: Side.white,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

void main() {
  group('pgnMovetext', () {
    test('numbers white moves and ends with the result', () {
      expect(
        pgnMovetext(sanMoves: ['e4', 'e5', 'Nf3']),
        '1. e4 e5 2. Nf3 *',
      );
    });

    test('starts with an ellipsis when black moves first', () {
      expect(
        pgnMovetext(sanMoves: ['Kd5', 'Kd2'], turn: Side.black, fullmoves: 40),
        '40... Kd5 41. Kd2 *',
      );
    });

    test('an empty line is just the result', () {
      expect(pgnMovetext(sanMoves: const []), '*');
    });

    test('wraps long lines at 80 characters', () {
      final text = pgnMovetext(sanMoves: List.filled(60, 'Nf3'));
      for (final line in text.split('\n')) {
        expect(line.length, lessThanOrEqualTo(80));
      }
      expect(text.split('\n').length, greaterThan(1));
    });
  });

  group('buildPgn', () {
    test('writes SetUp and FEN tags and the moves', () {
      final pgn = buildPgn(fen: endgameFen, sanMoves: ['Kd5']);
      expect(pgn, contains('[SetUp "1"]'));
      expect(pgn, contains('[FEN "$endgameFen"]'));
      expect(pgn, contains('[Annotator "ChessLens"]'));
      expect(pgn, contains('[Result "*"]'));
      expect(pgn.trimRight().endsWith('40... Kd5 *'), isTrue);
    });

    test('has a blank line between tags and moves and ends with a newline', () {
      final pgn = buildPgn(fen: startFen);
      expect(pgn, contains(']\n\n*\n'));
      expect(pgn.endsWith('\n'), isTrue);
    });

    test('escapes quotes and backslashes in tag values', () {
      final pgn = buildPgn(fen: startFen, headers: {'Event': r'The "Best" \ book'});
      expect(pgn, contains(r'[Event "The \"Best\" \\ book"]'));
    });
  });

  test('pgnFromTree uses the root position and the first child at each step', () {
    final tree = MoveTree(Chess.initial);
    tree.play(NormalMove(from: Square.e2, to: Square.e4));
    tree.play(NormalMove(from: Square.e7, to: Square.e5));
    tree.goToStart();
    // A variation does not appear in the main line.
    tree.play(NormalMove(from: Square.d2, to: Square.d4));
    tree.goToStart();

    final pgn = pgnFromTree(tree);
    expect(pgn, contains('[FEN "$startFen"]'));
    expect(pgn.trimRight().endsWith('1. e4 e5 *'), isTrue);
    expect(mainlineSan(tree.root), ['e4', 'e5']);
  });

  test('buildCollectionPgn writes one game per puzzle with Event and Round', () {
    final pgn = buildCollectionPgn('My "book"', [puzzle(startFen), puzzle(endgameFen)]);
    expect(RegExp(r'\[Event ').allMatches(pgn).length, 2);
    expect(pgn, contains(r'[Event "My \"book\""]'));
    expect(pgn, contains('[Round "1"]'));
    expect(pgn, contains('[Round "2"]'));
    expect(pgn, contains('[FEN "$endgameFen"]'));
    expect(pgn, contains('*\n\n[Event'));
  });

  test('safeFileName keeps simple characters', () {
    expect(safeFileName('Endgames: rook & pawn!'), 'Endgames_rook_pawn');
    expect(safeFileName('???'), 'collection');
  });

  test('lichessAnalysisUrl replaces spaces with underscores', () {
    expect(
      lichessAnalysisUrl(endgameFen),
      'https://lichess.org/analysis/standard/8/8/8/4k3/8/8/4P3/4K3_b_-_-_3_40',
    );
  });
}
