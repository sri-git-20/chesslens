import 'package:chesslens/src/analysis/move_tree.dart';
import 'package:chesslens/src/chess/game_status.dart';
import 'package:chesslens/src/engine/engine_service.dart';
import 'package:chesslens/src/engine/play_levels.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

List<Position> play(Position start, List<String> moves) {
  final history = [start];
  for (final uci in moves) {
    history.add(history.last.play(NormalMove.fromUci(uci)));
  }
  return history;
}

void main() {
  group('play levels', () {
    const range = EloRange(1320, 3190);

    test('the weakest levels use Skill Level, the others Elo', () {
      expect(PlayLevel.levels[0].strength(range), const EngineStrength.skill(0));
      expect(PlayLevel.levels[1].strength(range), const EngineStrength.skill(5));
      expect(PlayLevel.levels[2].strength(range), const EngineStrength.elo(1320));
      expect(PlayLevel.fullStrength.strength(range).isFull, isTrue);
    });

    test('Elo grows with the level and stays in range', () {
      final elos = [for (final level in PlayLevel.levels.skip(2)) level.strength(range).elo!];
      for (var i = 1; i < elos.length; i++) {
        expect(elos[i], greaterThan(elos[i - 1]));
      }
      expect(elos.first, range.min);
      expect(elos.last, lessThanOrEqualTo(range.max));
      expect(PlayLevel.levels, hasLength(8));
    });

    test('think time grows with the level', () {
      final times = [...PlayLevel.levels, PlayLevel.fullStrength].map((l) => l.thinkTimeMs).toList();
      for (var i = 1; i < times.length; i++) {
        expect(times[i], greaterThan(times[i - 1]));
      }
    });
  });

  group('game end', () {
    test('no end at the start', () {
      expect(detectGameEnd([Chess.initial]), isNull);
    });

    test('checkmate (fool\'s mate)', () {
      final history = play(Chess.initial, ['f2f3', 'e7e5', 'g2g4', 'd8h4']);
      final end = detectGameEnd(history)!;
      expect(end.reason, GameEndReason.checkmate);
      expect(end.winner, Side.black);
    });

    test('stalemate', () {
      final position = Chess.fromSetup(Setup.parseFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'));
      final end = detectGameEnd([position])!;
      expect(end.reason, GameEndReason.stalemate);
      expect(end.isDraw, isTrue);
    });

    test('insufficient material', () {
      final position = Chess.fromSetup(Setup.parseFen('8/8/4k3/8/8/3BK3/8/8 w - - 0 1'));
      expect(detectGameEnd([position])!.reason, GameEndReason.insufficientMaterial);
      final rook = Chess.fromSetup(Setup.parseFen('8/8/4k3/8/8/3RK3/8/8 w - - 0 1'));
      expect(detectGameEnd([rook]), isNull);
    });

    test('fifty-move rule', () {
      final position = Chess.fromSetup(Setup.parseFen('8/8/4k3/8/8/3RK3/8/8 w - - 100 80'));
      expect(detectGameEnd([position])!.reason, GameEndReason.fiftyMoveRule);
      final almost = Chess.fromSetup(Setup.parseFen('8/8/4k3/8/8/3RK3/8/8 w - - 99 80'));
      expect(detectGameEnd([almost]), isNull);
    });

    test('threefold repetition needs the third occurrence', () {
      const shuffle = ['g1f3', 'g8f6', 'f3g1', 'f6g8'];
      expect(detectGameEnd(play(Chess.initial, shuffle)), isNull);
      final end = detectGameEnd(play(Chess.initial, [...shuffle, ...shuffle]))!;
      expect(end.reason, GameEndReason.threefoldRepetition);
      expect(end.isDraw, isTrue);
    });
  });

  group('move tree', () {
    NormalMove move(String uci) => NormalMove.fromUci(uci);

    test('plays moves, goes back and forward', () {
      final tree = MoveTree(Chess.initial);
      expect(tree.canGoBack, isFalse);
      tree.play(move('e2e4'));
      tree.play(move('e7e5'));
      expect(tree.current.san, 'e5');
      expect(tree.current.depth, 2);

      tree.back();
      expect(tree.current.san, 'e4');
      expect(tree.canGoForward, isTrue);
      tree.forward();
      expect(tree.current.san, 'e5');
      tree.goToStart();
      expect(tree.current, same(tree.root));
      tree.goToEnd();
      expect(tree.current.san, 'e5');
    });

    test('a different move at the same place makes a variation', () {
      final tree = MoveTree(Chess.initial);
      final e4 = tree.play(move('e2e4'))!;
      tree.back();
      final d4 = tree.play(move('d2d4'))!;

      expect(tree.root.children, [e4, d4]);
      expect(tree.current, same(d4));
      // Playing the first move again selects it instead of adding a copy.
      tree.back();
      expect(tree.play(move('e2e4')), same(e4));
      expect(tree.root.children, hasLength(2));
    });

    test('illegal moves are refused', () {
      final tree = MoveTree(Chess.initial);
      expect(tree.play(move('e2e5')), isNull);
      expect(tree.current, same(tree.root));
    });

    test('castling is the same move in either notation', () {
      final start = Chess.fromSetup(Setup.parseFen('4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1'));
      final tree = MoveTree(start);
      final a = tree.play(move('e1g1'))!;
      tree.back();
      final b = tree.play(move('e1h1'))!;
      expect(a, same(b));
      expect(a.san, 'O-O');
    });
  });
}
