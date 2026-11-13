import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../chess/game_status.dart';
import '../chess/san.dart';
import '../collections/collection_repository.dart';
import '../collections/models.dart';
import '../engine/engine_service.dart';
import 'solve_judge.dart';

/// Search limits used while solving.
class SolveSearch {
  const SolveSearch({
    this.evalLimit = const SearchLimit(depth: 22, movetimeMs: 3000),
    this.replyLimit = const SearchLimit(depth: 20, movetimeMs: 1000),
    this.solutionDelay = const Duration(milliseconds: 800),
  });

  /// For judging: the best move and the user's move get the same limit.
  final SearchLimit evalLimit;

  /// For the opponent's reply.
  final SearchLimit replyLimit;

  /// Pause between moves when the solution is shown.
  final Duration solutionDelay;
}

enum SolvePhase { yourMove, judging, wrong, opponent, solution, finished }

/// Solve mode: the user plays the side to move, the engine judges each move
/// and answers for the opponent, until mate or a draw by the rules.
class SolveController extends ChangeNotifier {
  SolveController({
    required Position start,
    required EngineService engine,
    this.puzzleId,
    CollectionRepository? repository,
    this.search = const SolveSearch(),
  })  : _engine = engine,
        _repository = repository,
        solver = start.turn,
        _positions = [start] {
    _enterYourMove();
  }

  final EngineService _engine;
  final CollectionRepository? _repository;
  final SolveSearch search;
  final int? puzzleId;

  /// The side the user plays.
  final Side solver;

  final List<Position> _positions;
  final List<NormalMove> _moves = [];

  SolvePhase _phase = SolvePhase.yourMove;
  Future<EngineLine?>? _bestFuture;
  int _generation = 0;
  bool _disposed = false;
  bool _usedSolution = false;
  bool _recorded = false;
  int _correctMoves = 0;
  Square? _hintSquare;
  String? _error;
  String? _resultText;
  StreamSubscription<AnalysisUpdate>? _subscription;

  Position get position => _positions.last;
  NormalMove? get lastMove => _moves.isEmpty ? null : _moves.last;
  SolvePhase get phase => _phase;
  Square? get hintSquare => _hintSquare;
  String? get error => _error;
  String? get resultText => _resultText;
  bool get usedSolution => _usedSolution;
  int get movesPlayed => _correctMoves;
  bool get canMove => _phase == SolvePhase.yourMove && position.turn == solver;

  // -------------------------------------------------------- user moves

  void _enterYourMove() {
    _phase = SolvePhase.yourMove;
    _hintSquare = null;
    final end = detectGameEnd(_positions);
    if (end != null) {
      _finish('Nothing to solve here: ${end.reasonLabel.toLowerCase()}.');
      return;
    }
    // A failed evaluation becomes null, which judging reports as an engine
    // problem. Without this an unobserved error would go unhandled.
    _bestFuture = _evaluate(position, search.evalLimit).catchError((Object _) => null);
    notifyListeners();
  }

  void userMove(NormalMove move) {
    if (!canMove) return;
    final before = position;
    final normalized = before.normalizeMove(move);
    if (normalized is! NormalMove || !before.isLegal(normalized)) return;
    _hintSquare = null;
    _error = null;
    _positions.add(before.playUnchecked(normalized));
    _moves.add(normalized);
    _phase = SolvePhase.judging;
    notifyListeners();
    _judge(before, normalized);
  }

  Future<void> _judge(Position before, NormalMove move) async {
    final generation = _generation;
    try {
      final best = await _bestFuture;
      if (_stale(generation)) return;
      if (best == null) throw const EngineFailure('The engine gave no answer.');

      final playedUci = engineUci(before, move);
      UciScore playedScore;
      if (best.firstMove == playedUci) {
        playedScore = best.score;
      } else {
        final line = await _evaluate(before, search.evalLimit, searchMoves: [playedUci]);
        if (_stale(generation)) return;
        if (line == null) throw const EngineFailure('The engine gave no answer.');
        playedScore = line.score;
      }

      final result = judgeSolverMove(best: best.score, played: playedScore);
      if (!result.isCorrect) {
        _phase = SolvePhase.wrong;
        notifyListeners();
        return;
      }
      _correctMoves++;
      final end = detectGameEnd(_positions);
      if (end != null) {
        _finish(_solvedText(end));
        return;
      }
      await _opponentReply(generation);
    } catch (error) {
      if (_stale(generation)) return;
      _error = error is EngineFailure ? error.message : '$error';
      // Let the user take the move back and try again.
      _phase = SolvePhase.wrong;
      notifyListeners();
    }
  }

  Future<void> _opponentReply(int generation) async {
    _phase = SolvePhase.opponent;
    notifyListeners();
    final line = await _evaluate(position, search.replyLimit);
    if (_stale(generation)) return;
    final uci = line?.firstMove;
    final played = uci == null ? null : playUci(position, uci);
    if (played == null) throw const EngineFailure('The engine gave no reply.');
    _positions.add(played.$1);
    _moves.add(_toNormal(Move.parse(uci!)!));
    final end = detectGameEnd(_positions);
    if (end != null) {
      _finish(_solvedText(end));
      return;
    }
    _enterYourMove();
  }

  NormalMove _toNormal(Move move) => move as NormalMove;

  String _solvedText(GameEnd end) => '${end.reasonLabel}. Puzzle solved!';

  // ---------------------------------------------------------- wrong moves

  /// Takes the wrong move back so the user can try again.
  void tryAgain() {
    if (_phase != SolvePhase.wrong) return;
    _undoUserMove();
    _error = null;
    _phase = SolvePhase.yourMove;
    notifyListeners();
  }

  void _undoUserMove() {
    if (_positions.length > 1) {
      _positions.removeLast();
      _moves.removeLast();
    }
  }

  /// Plays the engine's line from the position before the wrong move.
  Future<void> showSolution() async {
    if (_phase != SolvePhase.wrong && _phase != SolvePhase.yourMove) return;
    final generation = ++_generation;
    if (_phase == SolvePhase.wrong) _undoUserMove();
    _usedSolution = true;
    _hintSquare = null;
    _error = null;
    _phase = SolvePhase.solution;
    notifyListeners();
    try {
      final best = await _bestFuture;
      if (_stale(generation)) return;
      final line = best;
      if (line == null || line.pv.isEmpty) {
        throw const EngineFailure('The engine gave no solution.');
      }
      for (final uci in line.pv) {
        await Future<void>.delayed(search.solutionDelay);
        if (_stale(generation)) return;
        final played = playUci(position, uci);
        if (played == null) break;
        _positions.add(played.$1);
        _moves.add(_toNormal(Move.parse(uci)!));
        notifyListeners();
        if (detectGameEnd(_positions) != null) break;
      }
      _finish('Solution shown.');
    } catch (error) {
      if (_stale(generation)) return;
      _error = error is EngineFailure ? error.message : '$error';
      _finish('Solution shown.');
    }
  }

  // ------------------------------------------------------------- hints

  /// Highlights the piece to move.
  Future<void> showHint() async {
    if (_phase != SolvePhase.yourMove) return;
    final generation = _generation;
    final best = await _bestFuture;
    if (_stale(generation) || _phase != SolvePhase.yourMove) return;
    final uci = best?.firstMove;
    final move = uci == null ? null : Move.parse(uci);
    if (move is NormalMove) {
      _hintSquare = move.from;
      notifyListeners();
    }
  }

  // ----------------------------------------------------------- engine

  bool _stale(int generation) => _disposed || generation != _generation;

  /// Searches [pos]; completes with the best line, or `null` if the search was
  /// replaced or produced nothing.
  Future<EngineLine?> _evaluate(
    Position pos,
    SearchLimit limit, {
    List<String> searchMoves = const [],
  }) {
    final completer = Completer<EngineLine?>();
    final Stream<AnalysisUpdate> stream;
    try {
      stream = _engine.analyze(
        AnalysisRequest(fen: pos.fen, limit: limit, searchMoves: searchMoves),
      );
    } on IllegalPositionException catch (error) {
      completer.completeError(EngineFailure(error.toString()));
      return completer.future;
    }
    EngineLine? last;
    _subscription?.cancel();
    _subscription = stream.listen(
      (update) {
        if (update.lines.isNotEmpty) last = update.lines.first;
        if (update.isFinal && !completer.isCompleted) completer.complete(last);
      },
      onError: (Object error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(last);
      },
    );
    return completer.future;
  }

  // ----------------------------------------------------------- finish

  void _finish(String text) {
    _phase = SolvePhase.finished;
    _resultText = text;
    _hintSquare = null;
    notifyListeners();
  }

  /// Saves the outcome for a puzzle from a collection: solved when the user
  /// finished without using Show solution, failed otherwise. Does nothing when
  /// no move was tried. Safe to call more than once.
  Future<void> recordSession() async {
    final repository = _repository;
    final id = puzzleId;
    if (_recorded || repository == null || id == null) return;
    final PuzzleStatus status;
    if (_usedSolution || _phase == SolvePhase.wrong) {
      status = PuzzleStatus.failed;
    } else if (_correctMoves > 0) {
      status = PuzzleStatus.solved;
    } else {
      return;
    }
    _recorded = true;
    try {
      await repository.recordAttempt(id, status: status);
    } catch (error) {
      debugPrint('Could not record the attempt: $error');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _subscription?.cancel();
    _engine.stop();
    super.dispose();
  }
}
