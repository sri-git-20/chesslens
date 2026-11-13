import 'package:chesslens/src/engine/uci.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseInfoLine', () {
    test('reads a centipawn line with all the usual fields', () {
      final info = parseInfoLine(
        'info depth 18 seldepth 24 multipv 1 score cp 34 nodes 1234567 nps 987654 '
        'hashfull 12 tbhits 0 time 1250 pv e2e4 e7e5 g1f3 b8c6',
      )!;
      expect(info.depth, 18);
      expect(info.seldepth, 24);
      expect(info.multipv, 1);
      expect(info.score, const UciScore.cp(34));
      expect(info.nodes, 1234567);
      expect(info.nps, 987654);
      expect(info.timeMs, 1250);
      expect(info.pv, ['e2e4', 'e7e5', 'g1f3', 'b8c6']);
    });

    test('reads negative centipawns and a mate score', () {
      expect(parseInfoLine('info depth 5 score cp -120 pv a2a3')!.score, const UciScore.cp(-120));
      final mate = parseInfoLine('info depth 12 multipv 2 score mate 3 pv d1h5 g6h5 d3h7')!;
      expect(mate.score, const UciScore.mate(3));
      expect(mate.score!.isMating, isTrue);
      expect(mate.multipv, 2);
      final mated = parseInfoLine('info depth 9 score mate -2 pv a1a2')!;
      expect(mated.score!.isMated, isTrue);
      expect(mated.score!.mate, -2);
    });

    test('reads lower and upper bounds', () {
      final lower = parseInfoLine('info depth 20 score cp 55 lowerbound nodes 100 pv e2e4')!;
      expect(lower.score!.bound, ScoreBound.lower);
      expect(lower.score!.cp, 55);
      expect(lower.nodes, 100);
      final upper = parseInfoLine('info depth 20 score cp -7 upperbound pv e2e4')!;
      expect(upper.score!.bound, ScoreBound.upper);
      final exact = parseInfoLine('info depth 20 score mate 4 pv e2e4')!;
      expect(exact.score!.bound, ScoreBound.exact);
    });

    test('multipv defaults to 1 and the pv may be absent', () {
      final info = parseInfoLine('info depth 1 score cp 10 nodes 20')!;
      expect(info.multipv, 1);
      expect(info.pv, isEmpty);
    });

    test('takes promotions and castling in the pv', () {
      final info = parseInfoLine('info depth 3 score cp 0 pv e7e8q e1g1')!;
      expect(info.pv, ['e7e8q', 'e1g1']);
    });

    test('ignores lines without a score or pv', () {
      expect(parseInfoLine('info string NNUE evaluation using nn-xxxx.nnue'), isNull);
      expect(parseInfoLine('info depth 5 currmove e2e4 currmovenumber 1'), isNull);
      expect(parseInfoLine('info hashfull 100'), isNull);
      expect(parseInfoLine('bestmove e2e4'), isNull);
    });
  });

  group('parseBestMove', () {
    test('without ponder', () {
      final best = parseBestMove('bestmove e2e4')!;
      expect(best.move, 'e2e4');
      expect(best.ponder, isNull);
    });

    test('with ponder', () {
      final best = parseBestMove('bestmove e2e4 ponder e7e5')!;
      expect(best.move, 'e2e4');
      expect(best.ponder, 'e7e5');
    });

    test('none when there is no legal move', () {
      expect(parseBestMove('bestmove (none)')!.move, isNull);
    });

    test('other lines are not best moves', () {
      expect(parseBestMove('readyok'), isNull);
      expect(parseBestMove('bestmove'), isNull);
    });
  });

  group('parseSpinOption', () {
    test('reads the Elo range', () {
      final option = parseSpinOption(
        'option name UCI_Elo type spin default 1320 min 1320 max 3190',
      )!;
      expect(option.name, 'UCI_Elo');
      expect(option.min, 1320);
      expect(option.max, 3190);
      expect(option.defaultValue, 1320);
    });

    test('names with spaces, and other option types', () {
      final skill = parseSpinOption('option name Skill Level type spin default 20 min 0 max 20')!;
      expect(skill.name, 'Skill Level');
      expect(skill.max, 20);
      expect(parseSpinOption('option name UCI_LimitStrength type check default false'), isNull);
    });
  });

  group('score display', () {
    test('formats from White\'s point of view', () {
      expect(formatScore(const UciScore.cp(35), Side.white), '+0.35');
      expect(formatScore(const UciScore.cp(35), Side.black), '-0.35');
      expect(formatScore(const UciScore.cp(0), Side.white), '0.00');
      expect(formatScore(const UciScore.mate(3), Side.white), 'M3');
      expect(formatScore(const UciScore.mate(3), Side.black), '-M3');
      expect(formatScore(const UciScore.mate(-2), Side.white), '-M2');
    });

    test('win percentage is 50 for 0.00 and 100 or 0 for mate', () {
      expect(whiteWinPercent(const UciScore.cp(0), Side.white), closeTo(50, 0.001));
      expect(whiteWinPercent(const UciScore.mate(2), Side.white), 100);
      expect(whiteWinPercent(const UciScore.mate(2), Side.black), 0);
      expect(whiteWinPercent(const UciScore.cp(300), Side.white), greaterThan(70));
      expect(whiteWinPercent(const UciScore.cp(300), Side.black), lessThan(30));
    });
  });
}
