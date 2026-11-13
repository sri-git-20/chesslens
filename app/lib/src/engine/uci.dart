import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// Whether a score is exact or only a bound (aspiration window fail).
enum ScoreBound { exact, lower, upper }

/// A UCI score, from the point of view of the side to move.
@immutable
class UciScore {
  const UciScore.cp(int this.cp, {this.bound = ScoreBound.exact}) : mate = null;
  const UciScore.mate(int this.mate, {this.bound = ScoreBound.exact}) : cp = null;

  /// Centipawns, or `null` for a mate score.
  final int? cp;

  /// Moves to mate: positive when the side to move mates, negative when it is
  /// being mated. `null` for a centipawn score.
  final int? mate;

  final ScoreBound bound;

  bool get isMate => mate != null;

  /// True when the side to move has a forced mate.
  bool get isMating => mate != null && mate! > 0;

  /// True when the side to move is being mated.
  bool get isMated => mate != null && mate! <= 0;

  /// The same score seen from the other side.
  UciScore get negated => isMate ? UciScore.mate(-mate!, bound: bound) : UciScore.cp(-cp!, bound: bound);

  /// Centipawns for ordering and bars; mate scores map to large values that
  /// are closer to zero the longer the mate is.
  int get orderingCp {
    if (mate == null) return cp!;
    final distance = math.min(mate!.abs(), 1000);
    return mate! > 0 ? 100000 - distance : -100000 + distance;
  }

  @override
  bool operator ==(Object other) =>
      other is UciScore && other.cp == cp && other.mate == mate && other.bound == bound;

  @override
  int get hashCode => Object.hash(cp, mate, bound);

  @override
  String toString() => isMate ? 'mate $mate' : 'cp $cp';
}

/// One parsed `info` line that carries a score or a principal variation.
@immutable
class UciInfo {
  const UciInfo({
    this.depth,
    this.seldepth,
    this.multipv = 1,
    this.score,
    this.nodes,
    this.nps,
    this.timeMs,
    this.pv = const [],
  });

  final int? depth;
  final int? seldepth;

  /// 1-based index of the line when MultiPV is above 1.
  final int multipv;
  final UciScore? score;
  final int? nodes;
  final int? nps;
  final int? timeMs;

  /// Moves in UCI notation.
  final List<String> pv;
}

/// Parses an `info ...` line. Returns `null` for lines that carry neither a
/// score nor a PV (`info string`, `info currmove`, `info hashfull`, ...).
UciInfo? parseInfoLine(String line) {
  final tokens = line.trim().split(RegExp(r'\s+'));
  if (tokens.isEmpty || tokens.first != 'info') return null;
  if (tokens.length > 1 && tokens[1] == 'string') return null;

  int? depth;
  int? seldepth;
  var multipv = 1;
  UciScore? score;
  int? nodes;
  int? nps;
  int? timeMs;
  var pv = <String>[];

  var i = 1;
  while (i < tokens.length) {
    final token = tokens[i];
    switch (token) {
      case 'depth':
        depth = _intAt(tokens, i + 1);
        i += 2;
      case 'seldepth':
        seldepth = _intAt(tokens, i + 1);
        i += 2;
      case 'multipv':
        multipv = _intAt(tokens, i + 1) ?? 1;
        i += 2;
      case 'nodes':
        nodes = _intAt(tokens, i + 1);
        i += 2;
      case 'nps':
        nps = _intAt(tokens, i + 1);
        i += 2;
      case 'time':
        timeMs = _intAt(tokens, i + 1);
        i += 2;
      case 'score':
        final kind = i + 1 < tokens.length ? tokens[i + 1] : '';
        final value = _intAt(tokens, i + 2);
        i += 3;
        var bound = ScoreBound.exact;
        if (i < tokens.length && tokens[i] == 'lowerbound') {
          bound = ScoreBound.lower;
          i++;
        } else if (i < tokens.length && tokens[i] == 'upperbound') {
          bound = ScoreBound.upper;
          i++;
        }
        if (value != null) {
          if (kind == 'cp') {
            score = UciScore.cp(value, bound: bound);
          } else if (kind == 'mate') {
            score = UciScore.mate(value, bound: bound);
          }
        }
      case 'pv':
        pv = tokens.sublist(i + 1);
        i = tokens.length;
      case 'refutation' || 'currline':
        i = tokens.length;
      default:
        i++;
    }
  }
  if (score == null && pv.isEmpty) return null;
  return UciInfo(
    depth: depth,
    seldepth: seldepth,
    multipv: multipv,
    score: score,
    nodes: nodes,
    nps: nps,
    timeMs: timeMs,
    pv: pv,
  );
}

int? _intAt(List<String> tokens, int index) =>
    index < tokens.length ? int.tryParse(tokens[index]) : null;

/// A parsed `bestmove` line. [move] is `null` for `bestmove (none)`.
@immutable
class UciBestMove {
  const UciBestMove(this.move, {this.ponder});
  final String? move;
  final String? ponder;
}

/// Parses `bestmove e2e4` and `bestmove e2e4 ponder e7e5`.
UciBestMove? parseBestMove(String line) {
  final tokens = line.trim().split(RegExp(r'\s+'));
  if (tokens.length < 2 || tokens.first != 'bestmove') return null;
  final move = tokens[1];
  String? ponder;
  final ponderIndex = tokens.indexOf('ponder');
  if (ponderIndex != -1 && ponderIndex + 1 < tokens.length) {
    ponder = tokens[ponderIndex + 1];
  }
  final none = move == '(none)' || move == '0000';
  return UciBestMove(none ? null : move, ponder: ponder);
}

/// A numeric UCI option announced by the engine, for example UCI_Elo.
@immutable
class UciSpinOption {
  const UciSpinOption({required this.name, this.min, this.max, this.defaultValue});
  final String name;
  final int? min;
  final int? max;
  final int? defaultValue;
}

/// Parses `option name UCI_Elo type spin default 1320 min 1320 max 3190`.
/// Returns `null` for options that are not of type spin.
UciSpinOption? parseSpinOption(String line) {
  final match = RegExp(r'^option\s+name\s+(.+?)\s+type\s+spin(.*)$').firstMatch(line.trim());
  if (match == null) return null;
  final rest = match.group(2)!;
  int? read(String key) {
    final m = RegExp('$key\\s+(-?\\d+)').firstMatch(rest);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  return UciSpinOption(
    name: match.group(1)!,
    min: read('min'),
    max: read('max'),
    defaultValue: read('default'),
  );
}

/// Win probability for White in percent (0 to 100), from a score and the side
/// to move. Same curve lichess uses for its evaluation bar.
double whiteWinPercent(UciScore score, Side turn) {
  final whiteScore = turn == Side.white ? score : score.negated;
  if (whiteScore.isMate) {
    return whiteScore.mate! > 0 ? 100 : 0;
  }
  final cp = whiteScore.cp!.clamp(-1000, 1000);
  return 50 + 50 * (2 / (1 + math.exp(-0.00368208 * cp)) - 1);
}

/// Formats a score from White's point of view: `+0.35`, `-1.20`, `M3`, `-M3`.
String formatScore(UciScore score, Side turn) {
  final whiteScore = turn == Side.white ? score : score.negated;
  if (whiteScore.isMate) {
    final n = whiteScore.mate!;
    return n >= 0 ? 'M$n' : '-M${n.abs()}';
  }
  final pawns = whiteScore.cp! / 100;
  final text = pawns.abs().toStringAsFixed(2);
  if (whiteScore.cp! > 0) return '+$text';
  if (whiteScore.cp! < 0) return '-$text';
  return '0.00';
}
