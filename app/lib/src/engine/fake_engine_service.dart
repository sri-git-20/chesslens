import 'package:flutter/foundation.dart';

import '../chess/board_utils.dart';
import 'engine_service.dart';
import 'uci.dart';

/// What a [FakeEngineService] answers for one request.
class FakeResult {
  const FakeResult({required this.lines, this.bestMove});
  final List<EngineLine> lines;
  final String? bestMove;
}

typedef FakeEvaluator = FakeResult Function(AnalysisRequest request);

/// An [EngineService] for tests: no process, scripted answers.
///
/// By default every position evaluates to 0.00 and the best move is the first
/// legal move found (or the first of `searchMoves`).
class FakeEngineService implements EngineService {
  FakeEngineService({
    this.evaluator,
    this.range = EloRange.fallback,
    EngineSpec spec = EngineSpec.light,
  }) : _spec = spec;

  final FakeEvaluator? evaluator;
  final EloRange range;
  EngineSpec _spec;

  /// Every request received, oldest first.
  final List<AnalysisRequest> requests = [];

  /// Settings last passed to [applySettings].
  EngineSettings? lastSettings;

  int restarts = 0;
  int stops = 0;
  bool disposed = false;

  final ValueNotifier<EngineStatus> _status = ValueNotifier(EngineStatus.ready);

  @override
  ValueListenable<EngineStatus> get status => _status;

  @override
  EngineSpec get spec => _spec;

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<void> restart(EngineSpec spec) async {
    restarts++;
    _spec = spec;
  }

  @override
  void applySettings(EngineSettings settings) => lastSettings = settings;

  @override
  Future<EloRange> eloRange() async => range;

  @override
  Stream<AnalysisUpdate> analyze(AnalysisRequest request) {
    final position = chessFromFen(request.fen);
    if (position == null) throw IllegalPositionException(request.fen);
    requests.add(request);
    final result = (evaluator ?? _defaultEvaluator)(request);
    final depth = result.lines.isEmpty ? 0 : result.lines.first.depth;
    return Stream<AnalysisUpdate>.fromIterable([
      AnalysisUpdate(lines: result.lines, depth: depth),
      AnalysisUpdate(
        lines: result.lines,
        depth: depth,
        isFinal: true,
        bestMove: result.bestMove,
      ),
    ]);
  }

  FakeResult _defaultEvaluator(AnalysisRequest request) {
    final position = chessFromFen(request.fen)!;
    String? move;
    if (request.searchMoves.isNotEmpty) {
      move = request.searchMoves.first;
    } else {
      for (final entry in position.legalMoves.entries) {
        final to = entry.value.squares.firstOrNull;
        if (to != null) {
          move = '${entry.key.name}${to.name}';
          break;
        }
      }
    }
    if (move == null) return const FakeResult(lines: []);
    return FakeResult(
      lines: [
        EngineLine(
          multiPv: 1,
          depth: request.limit.depth ?? 10,
          score: const UciScore.cp(0),
          pv: [move],
        ),
      ],
      bestMove: move,
    );
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> dispose() async => disposed = true;
}
