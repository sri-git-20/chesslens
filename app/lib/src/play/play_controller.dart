import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../chess/game_status.dart';
import '../chess/san.dart';
import '../engine/engine_service.dart';
import '../engine/play_levels.dart';

/// A game against the engine from a given start position.
class PlayController extends ChangeNotifier {
  PlayController({required Position start, required EngineService engine})
      : _start = start,
        _engine = engine,
        _history = [start];

  final Position _start;
  final EngineService _engine;
  final List<Position> _history;
  final List<NormalMove> _moves = [];

  Side _userSide = Side.white;
  PlayLevel _level = PlayLevel.fullStrength;
  EngineStrength _strength = const EngineStrength.full();
  EloRange _range = EloRange.fallback;
  bool _started = false;
  bool _thinking = false;
  bool _hintLoading = false;
  bool _disposed = false;
  bool _newEngineGame = true;
  GameEnd? _end;
  NormalMove? _hint;
  String? _error;
  int _generation = 0;
  int _gameId = 0;
  StreamSubscription<AnalysisUpdate>? _engineSub;
  StreamSubscription<AnalysisUpdate>? _hintSub;

  Position get position => _history.last;
  Position get startPosition => _start;
  List<NormalMove> get moves => List.unmodifiable(_moves);
  NormalMove? get lastMove => _moves.isEmpty ? null : _moves.last;
  Side get userSide => _userSide;
  PlayLevel get level => _level;
  bool get started => _started;
  bool get isThinking => _thinking;
  bool get isHintLoading => _hintLoading;
  GameEnd? get end => _end;
  NormalMove? get hint => _hint;
  String? get error => _error;
  bool get isUserTurn => _started && _end == null && position.turn == _userSide;

  /// Whether Takeback does anything: the user has made at least one move.
  bool get canTakeback {
    if (!_started) return false;
    final firstUserPly = _start.turn == _userSide ? 1 : 2;
    return _history.length > firstUserPly;
  }

  /// The UCI_Elo range of the engine, for describing the levels.
  Future<EloRange> loadEloRange() async {
    try {
      _range = await _engine.eloRange();
    } catch (_) {
      _range = EloRange.fallback;
    }
    return _range;
  }

  /// Text for the end of the game, from the user's point of view.
  String? get resultText {
    final end = _end;
    if (end == null) return null;
    if (end.reason == GameEndReason.resignation) return 'You resigned. The engine wins.';
    if (end.winner == null) return '${end.reasonLabel}. The game is a draw.';
    final userWon = end.winner == _userSide;
    return '${end.reasonLabel}. ${userWon ? 'You win!' : 'The engine wins.'}';
  }

  Future<void> startGame({required Side userSide, required PlayLevel level}) async {
    _cancelSearches();
    _userSide = userSide;
    _level = level;
    _history
      ..clear()
      ..add(_start);
    _moves.clear();
    _end = null;
    _hint = null;
    _error = null;
    _started = true;
    _newEngineGame = true;
    // A position that is already over (mate, stalemate) has nothing to play.
    _end = detectGameEnd(_history);
    final game = ++_gameId;
    notifyListeners();
    final range = await loadEloRange();
    // Another game was started, or the user went back to the setup, meanwhile.
    if (_disposed || game != _gameId) return;
    _strength = level.strength(range);
    _afterMove();
  }

  /// Back to the setup screen.
  void newGame() {
    _gameId++;
    _cancelSearches();
    _started = false;
    _end = null;
    _hint = null;
    _error = null;
    _history
      ..clear()
      ..add(_start);
    _moves.clear();
    notifyListeners();
  }

  void userMove(NormalMove move) {
    if (!isUserTurn || _thinking) return;
    _hint = null;
    if (!_apply(move)) return;
    _afterMove();
  }

  bool _apply(Move move) {
    final current = position;
    final normalized = move is NormalMove ? current.normalizeMove(move) : move;
    if (normalized is! NormalMove || !current.isLegal(normalized)) return false;
    _history.add(current.playUnchecked(normalized));
    _moves.add(normalized);
    _end = detectGameEnd(_history);
    notifyListeners();
    return true;
  }

  void _afterMove() {
    if (_disposed || _end != null) {
      notifyListeners();
      return;
    }
    if (position.turn != _userSide) {
      _engineMove();
    } else {
      notifyListeners();
    }
  }

  void _cancelSearches() {
    _generation++;
    _engineSub?.cancel();
    _engineSub = null;
    _hintSub?.cancel();
    _hintSub = null;
    _thinking = false;
    _hintLoading = false;
    _engine.stop();
  }

  void _engineMove() {
    final generation = ++_generation;
    _thinking = true;
    _error = null;
    _hint = null;
    notifyListeners();
    final Stream<AnalysisUpdate> stream;
    try {
      stream = _engine.analyze(
        AnalysisRequest(
          fen: position.fen,
          limit: SearchLimit(movetimeMs: _level.thinkTimeMs),
          strength: _strength,
          newGame: _newEngineGame,
        ),
      );
    } on IllegalPositionException catch (error) {
      _thinking = false;
      _error = error.toString();
      notifyListeners();
      return;
    }
    _newEngineGame = false;
    _engineSub = stream.listen(
      (update) {
        if (generation != _generation || !update.isFinal) return;
        _thinking = false;
        final best = update.bestMove;
        final played = best == null ? null : playUci(position, best);
        if (played == null) {
          _error = 'The engine did not return a move.';
          notifyListeners();
          return;
        }
        _apply(Move.parse(best!)!);
      },
      onError: (Object error) {
        if (generation != _generation) return;
        _thinking = false;
        _error = error is EngineFailure ? error.message : '$error';
        notifyListeners();
      },
      onDone: () {
        if (generation != _generation) return;
        if (_thinking) {
          _thinking = false;
          notifyListeners();
        }
      },
    );
  }

  /// Asks the engine (at full strength) for a move to suggest.
  void showHint() {
    if (!isUserTurn || _thinking || _hintLoading) return;
    _hintLoading = true;
    _error = null;
    notifyListeners();
    final generation = ++_generation;
    final Stream<AnalysisUpdate> stream;
    try {
      stream = _engine.analyze(
        AnalysisRequest(fen: position.fen, limit: const SearchLimit(movetimeMs: 1000)),
      );
    } on IllegalPositionException catch (error) {
      _hintLoading = false;
      _error = error.toString();
      notifyListeners();
      return;
    }
    _hintSub = stream.listen(
      (update) {
        if (generation != _generation || !update.isFinal) return;
        _hintLoading = false;
        final best = update.bestMove;
        final move = best == null ? null : Move.parse(best);
        if (move is NormalMove) _hint = move;
        notifyListeners();
      },
      onError: (Object error) {
        if (generation != _generation) return;
        _hintLoading = false;
        _error = error is EngineFailure ? error.message : '$error';
        notifyListeners();
      },
      onDone: () {
        if (generation != _generation) return;
        if (_hintLoading) {
          _hintLoading = false;
          notifyListeners();
        }
      },
    );
  }

  /// Asks the engine for its move again, after a failure.
  void retryEngineMove() {
    if (!_started || _end != null || _thinking || position.turn == _userSide) return;
    _engineMove();
  }

  /// Takes back the last move of the user (and the engine's reply).
  void takeback() {
    if (!canTakeback) return;
    _cancelSearches();
    _hint = null;
    _error = null;
    _end = null;
    do {
      _history.removeLast();
      _moves.removeLast();
    } while (_history.length > 1 && _history.last.turn != _userSide);
    _end = detectGameEnd(_history);
    notifyListeners();
    _afterMove();
  }

  void resign() {
    if (_end != null || !_started) return;
    _cancelSearches();
    _hint = null;
    _end = GameEnd(GameEndReason.resignation, winner: _userSide.opposite);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelSearches();
    super.dispose();
  }
}
