import 'package:chesslens/src/engine/uci.dart';
import 'package:chesslens/src/solve/solve_judge.dart';
import 'package:flutter_test/flutter_test.dart';

JudgeResult judge(UciScore best, UciScore played) => judgeSolverMove(best: best, played: played);

void main() {
  group('forced mate for the solver', () {
    test('a move that keeps a forced mate is correct, whatever its length', () {
      expect(judge(const UciScore.mate(2), const UciScore.mate(2)).isCorrect, isTrue);
      expect(judge(const UciScore.mate(2), const UciScore.mate(5)).isCorrect, isTrue);
    });

    test('a move that loses the mate is not the best move', () {
      expect(judge(const UciScore.mate(2), const UciScore.cp(900)).isCorrect, isFalse);
      expect(judge(const UciScore.mate(2), const UciScore.cp(0)).isCorrect, isFalse);
      expect(judge(const UciScore.mate(1), const UciScore.mate(-3)).isCorrect, isFalse);
    });
  });

  group('no forced mate', () {
    test('within half a pawn of the best move is correct', () {
      expect(judge(const UciScore.cp(100), const UciScore.cp(100)).isCorrect, isTrue);
      expect(judge(const UciScore.cp(100), const UciScore.cp(60)).isCorrect, isTrue);
      expect(judge(const UciScore.cp(100), const UciScore.cp(50)).isCorrect, isTrue);
      expect(judge(const UciScore.cp(-80), const UciScore.cp(-120)).isCorrect, isTrue);
    });

    test('more than half a pawn worse is wrong', () {
      expect(judge(const UciScore.cp(100), const UciScore.cp(49)).isCorrect, isFalse);
      expect(judge(const UciScore.cp(100), const UciScore.cp(-40)).isCorrect, isFalse);
      expect(judge(const UciScore.cp(-80), const UciScore.cp(-200)).isCorrect, isFalse);
    });

    test('dropping from winning to not winning is wrong', () {
      expect(judge(const UciScore.cp(160), const UciScore.cp(140)).isCorrect, isFalse);
      expect(judge(const UciScore.cp(300), const UciScore.cp(120)).isCorrect, isFalse);
      expect(judge(const UciScore.cp(150), const UciScore.cp(149)).isCorrect, isFalse);
    });

    test('staying winning with a slightly worse move is fine', () {
      expect(judge(const UciScore.cp(300), const UciScore.cp(270)).isCorrect, isTrue);
      expect(judge(const UciScore.cp(160), const UciScore.cp(150)).isCorrect, isTrue);
    });

    test('finding a mate when the best line was only winning is correct', () {
      expect(judge(const UciScore.cp(400), const UciScore.mate(6)).isCorrect, isTrue);
    });

    test('walking into a mate is wrong', () {
      expect(judge(const UciScore.cp(0), const UciScore.mate(-2)).isCorrect, isFalse);
      expect(judge(const UciScore.cp(400), const UciScore.mate(-4)).isCorrect, isFalse);
    });
  });

  group('drawn study', () {
    test('moves that keep the draw are accepted', () {
      expect(judge(const UciScore.cp(0), const UciScore.cp(0)).isCorrect, isTrue);
      expect(judge(const UciScore.cp(0), const UciScore.cp(-50)).isCorrect, isTrue);
      expect(judge(const UciScore.cp(30), const UciScore.cp(-20)).isCorrect, isTrue);
      expect(judge(const UciScore.cp(-40), const UciScore.cp(-45)).isCorrect, isTrue);
    });

    test('moves that leave the band are wrong', () {
      expect(judge(const UciScore.cp(0), const UciScore.cp(-51)).isCorrect, isFalse);
      expect(judge(const UciScore.cp(0), const UciScore.cp(-300)).isCorrect, isFalse);
      expect(judge(const UciScore.cp(20), const UciScore.mate(-5)).isCorrect, isFalse);
    });
  });

  group('the solver is being mated', () {
    test('any move that avoids mate is fine, resisting less long is not', () {
      expect(judge(const UciScore.mate(-3), const UciScore.cp(-900)).isCorrect, isTrue);
      expect(judge(const UciScore.mate(-3), const UciScore.mate(-3)).isCorrect, isTrue);
      expect(judge(const UciScore.mate(-3), const UciScore.mate(-5)).isCorrect, isTrue);
      expect(judge(const UciScore.mate(-3), const UciScore.mate(-1)).isCorrect, isFalse);
    });
  });
}
