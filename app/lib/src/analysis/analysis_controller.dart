import 'dart:async';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../engine/engine_service.dart';
import 'move_tree.dart';

/// Engine limits for Analysis, from settings.
@immutable
class AnalysisConfig {
  const AnalysisConfig({this.multiPv = 2, this.depthLimit = 30, this.timeLimitSeconds = 60});

  final int multiPv;

  /// 0 means no limit.
  final int depthLimit;

  /// 0 means no limit.
  final int timeLimitSeconds;

  SearchLimit get limit => SearchLimit(
        depth: depthLimit > 0 ? depthLimit : null,
        movetimeMs: timeLimitSeconds > 0 ? timeLimitSeconds * 1000 : null,
      );

  @override
  bool operator ==(Object other) =>
      other is AnalysisConfig &&
      other.multiPv == multiPv &&
      other.depthLimit == depthLimit &&
      other.timeLimitSeconds == timeLimitSeconds;

  @override
  int get hashCode => Object.hash(multiPv, depthLimit, timeLimitSeconds);
}

/// Why the engine is not searching.
enum AnalysisIdle { none, off, hidden, gameOver, limitReached, failed }

/// State of the Analysis screen: the move tree, and the engine search for the
/// current position.
class AnalysisController extends ChangeNotifier {
  AnalysisController({
    required Position start,
    required EngineService engine,
    AnalysisConfig config = const AnalysisConfig(),
    bool engineOn = true,
  })  : tree = MoveTree(start),
        _engine = engine,
        _config = config,
        _engineOn = engineOn;

  final MoveTree tree;
  final EngineService _engine;
  AnalysisConfig _config;

  bool _engineOn;
  bool _visible = true;
  bool _disposed = false;
  bool _searching = false;
  AnalysisIdle _idle = AnalysisIdle.none;
  List<EngineLine> _lines = const [];
  int _depth = 0;
  String? _error;
  StreamSubscription<AnalysisUpdate>? _subscription;
  int _generation = 0;

  Position get position => tree.current.position;
  NormalMove? get lastMove => tree.current.move;
  bool get engineOn => _engineOn;
  bool get isSearching => _searching;
  AnalysisIdle get idle => _idle;
  List<EngineLine> get lines => _lines;
  int get depth => _depth;
  String? get error => _error;
  AnalysisConfig get config => _config;

  /// Starts the first search. Call once after creating the controller.
  void start() => _restartSearch();

  // ------------------------------------------------------------ moves

  void makeMove(NormalMove move) {
    final node = tree.play(move);
    if (node == null) return;
    _restartSearch();
  }

  void back() {
    if (!tree.canGoBack) return;
    tree.back();
    _restartSearch();
  }

  void forward() {
    if (!tree.canGoForward) return;
    tree.forward();
    _restartSearch();
  }

  void goToStart() {
    if (!tree.canGoBack) return;
    tree.goToStart();
    _restartSearch();
  }

  void goToEnd() {
    if (!tree.canGoForward) return;
    tree.goToEnd();
    _restartSearch();
  }

  void goTo(MoveNode node) {
    if (identical(node, tree.current)) return;
    tree.goTo(node);
    _restartSearch();
  }

  // ----------------------------------------------------------- engine

  void setEngineOn(bool value) {
    if (_engineOn == value) return;
    _engineOn = value;
    _restartSearch();
  }

  /// Called with `false` while another screen covers this one or the app is in
  /// the background, so the engine does not keep running unseen.
  void setVisible(bool value) {
    if (_visible == value) return;
    _visible = value;
    _restartSearch();
  }

  void updateConfig(AnalysisConfig config) {
    if (config == _config) return;
    _config = config;
    _restartSearch();
  }

  /// Searches the current position again (after a failure, or to continue
  /// past a limit).
  void retry() => _restartSearch();

  void _stopSearch() {
    _generation++;
    _subscription?.cancel();
    _subscription = null;
  }

  void _restartSearch() {
    if (_disposed) return;
    _stopSearch();
    _lines = const [];
    _depth = 0;
    _error = null;
    _searching = false;

    if (!_engineOn) {
      _idle = AnalysisIdle.off;
    } else if (!_visible) {
      _idle = AnalysisIdle.hidden;
    } else if (position.isGameOver) {
      _idle = AnalysisIdle.gameOver;
    } else {
      _idle = AnalysisIdle.none;
      _beginSearch();
    }
    notifyListeners();
  }

  void _beginSearch() {
    final generation = _generation;
    final Stream<AnalysisUpdate> stream;
    try {
      stream = _engine.analyze(
        AnalysisRequest(
          fen: position.fen,
          limit: _config.limit,
          multiPv: _config.multiPv,
        ),
      );
    } on IllegalPositionException catch (error) {
      _idle = AnalysisIdle.failed;
      _error = error.toString();
      return;
    }
    _searching = true;
    _subscription = stream.listen(
      (update) {
        if (generation != _generation || _disposed) return;
        _lines = update.lines;
        _depth = update.depth;
        if (update.isFinal) {
          _searching = false;
          _idle = AnalysisIdle.limitReached;
        }
        notifyListeners();
      },
      onError: (Object error) {
        if (generation != _generation || _disposed) return;
        _searching = false;
        _idle = AnalysisIdle.failed;
        _error = error is EngineFailure ? error.message : '$error';
        notifyListeners();
      },
      onDone: () {
        if (generation != _generation || _disposed) return;
        if (_searching) {
          _searching = false;
          notifyListeners();
        }
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _stopSearch();
    // Cancelling the subscription stops the search; this also covers a search
    // that is still waiting to start.
    _engine.stop();
    super.dispose();
  }
}
