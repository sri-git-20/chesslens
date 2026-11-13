import 'package:flutter/foundation.dart';
import 'package:multistockfish/multistockfish.dart' show StockfishFlavor;

import 'uci.dart';

/// Which Stockfish build to run, and the network file for builds that need
/// one.
///
/// [StockfishFlavor.light] has a small network built in. [StockfishFlavor
/// .latestNoNNUE] needs [nnuePath] to point at a downloaded network file.
@immutable
class EngineSpec {
  const EngineSpec({this.flavor = StockfishFlavor.light, this.nnuePath})
      : assert(
          flavor != StockfishFlavor.latestNoNNUE || nnuePath != null,
          'latestNoNNUE needs an nnuePath',
        );

  /// The built-in light network. Works without any download.
  static const light = EngineSpec();

  final StockfishFlavor flavor;
  final String? nnuePath;

  /// The spec for a settings value: a path to a downloaded full network, or
  /// `null` for the light engine.
  factory EngineSpec.forNetworkPath(String? path) => path == null || path.isEmpty
      ? light
      : EngineSpec(flavor: StockfishFlavor.latestNoNNUE, nnuePath: path);

  @override
  bool operator ==(Object other) =>
      other is EngineSpec && other.flavor == flavor && other.nnuePath == nnuePath;

  @override
  int get hashCode => Object.hash(flavor, nnuePath);

  @override
  String toString() => 'EngineSpec(${flavor.name}, $nnuePath)';
}

/// Settings that apply to every search.
@immutable
class EngineSettings {
  const EngineSettings({this.threads = 1, this.hashMb = 64});

  final int threads;
  final int hashMb;

  @override
  bool operator ==(Object other) =>
      other is EngineSettings && other.threads == threads && other.hashMb == hashMb;

  @override
  int get hashCode => Object.hash(threads, hashMb);
}

/// Limits a strength-limited engine to roughly a given playing level.
///
/// Use [EngineStrength.full] for no limit. Otherwise set [elo] (the UCI_Elo
/// range of the engine) or [skillLevel] (0 to 19, for the weakest levels
/// below the UCI_Elo range).
@immutable
class EngineStrength {
  const EngineStrength.full()
      : elo = null,
        skillLevel = null;
  const EngineStrength.elo(int this.elo) : skillLevel = null;
  const EngineStrength.skill(int this.skillLevel) : elo = null;

  final int? elo;
  final int? skillLevel;

  bool get isFull => elo == null && skillLevel == null;

  @override
  bool operator ==(Object other) =>
      other is EngineStrength && other.elo == elo && other.skillLevel == skillLevel;

  @override
  int get hashCode => Object.hash(elo, skillLevel);

  @override
  String toString() => isFull ? 'full' : (elo != null ? 'elo $elo' : 'skill $skillLevel');
}

/// When a search stops by itself. Both limits apply when both are set; with
/// neither the search runs until stopped.
@immutable
class SearchLimit {
  const SearchLimit({this.depth, this.movetimeMs});

  static const infinite = SearchLimit();

  final int? depth;
  final int? movetimeMs;

  bool get isInfinite => depth == null && movetimeMs == null;
}

/// One search request. [fen] must be a legal position; the service refuses
/// anything else because Stockfish 19 ends its process on illegal input.
@immutable
class AnalysisRequest {
  const AnalysisRequest({
    required this.fen,
    this.limit = SearchLimit.infinite,
    this.multiPv = 1,
    this.strength = const EngineStrength.full(),
    this.searchMoves = const [],
    this.newGame = false,
  });

  final String fen;
  final SearchLimit limit;
  final int multiPv;
  final EngineStrength strength;

  /// Restricts the search to these root moves (UCI notation), to evaluate one
  /// particular move.
  final List<String> searchMoves;

  /// Send `ucinewgame` before this search.
  final bool newGame;
}

/// One line of a search: a score and the moves that go with it.
@immutable
class EngineLine {
  const EngineLine({
    required this.multiPv,
    required this.depth,
    required this.score,
    required this.pv,
    this.seldepth,
    this.nodes,
    this.nps,
    this.timeMs,
  });

  final int multiPv;
  final int depth;
  final int? seldepth;

  /// Score for the side to move at the root of the search.
  final UciScore score;

  /// Moves in UCI notation. May be empty only for mate/stalemate scores.
  final List<String> pv;
  final int? nodes;
  final int? nps;
  final int? timeMs;

  String? get firstMove => pv.isEmpty ? null : pv.first;
}

/// The state of a search after each new engine line.
@immutable
class AnalysisUpdate {
  const AnalysisUpdate({
    required this.lines,
    required this.depth,
    this.isFinal = false,
    this.bestMove,
    this.nodes,
    this.nps,
    this.timeMs,
  });

  /// Lines ordered by multipv index (best first). Never empty except for the
  /// final update of a position without legal moves.
  final List<EngineLine> lines;

  /// Depth reached by the best line.
  final int depth;

  /// True for the last update of a search (the engine sent `bestmove`).
  final bool isFinal;

  /// UCI move from the engine's `bestmove`, on the final update only.
  final String? bestMove;
  final int? nodes;
  final int? nps;
  final int? timeMs;

  EngineLine? get best => lines.isEmpty ? null : lines.first;
}

enum EngineStatus { idle, starting, ready, failed }

/// The range of UCI_Elo the engine accepts.
@immutable
class EloRange {
  const EloRange(this.min, this.max);

  /// Used when the engine does not report a range (Stockfish 19 default).
  static const fallback = EloRange(1320, 3190);

  final int min;
  final int max;
}

/// Thrown when a position that is not legal is handed to the engine.
class IllegalPositionException implements Exception {
  const IllegalPositionException(this.fen);
  final String fen;

  @override
  String toString() => 'Refusing to send an illegal position to the engine: $fen';
}

/// Thrown (as a stream error) when the engine could not be started or kept
/// failing during a search.
class EngineFailure implements Exception {
  const EngineFailure(this.message);
  final String message;

  @override
  String toString() => 'Engine problem: $message';
}

/// The chess engine, as the screens see it.
///
/// One search runs at a time. Starting a new search stops the one before it.
abstract interface class EngineService {
  /// Current state of the engine process.
  ValueListenable<EngineStatus> get status;

  /// The build that new searches run on.
  EngineSpec get spec;

  /// Starts the engine if it is not running. Completes when it is ready.
  /// Throws [EngineFailure] if it cannot start.
  Future<void> ensureStarted();

  /// Switches to another build, for example the full network once it has been
  /// downloaded. The running engine (if any) is stopped and disposed; the new
  /// one starts on the next search or [ensureStarted].
  Future<void> restart(EngineSpec spec);

  /// Threads and Hash, applied before the next search.
  void applySettings(EngineSettings settings);

  /// The UCI_Elo range of the engine. Starts it if needed; falls back to
  /// [EloRange.fallback] when the engine does not report one.
  Future<EloRange> eloRange();

  /// Searches [request.fen] and streams updates. The last update has
  /// `isFinal` set; then the stream closes. Cancelling the subscription
  /// stops the search. A new call stops the search before it (its stream
  /// closes without a final update).
  ///
  /// Throws [IllegalPositionException] for illegal positions. Failures while
  /// running arrive as [EngineFailure] stream errors.
  Stream<AnalysisUpdate> analyze(AnalysisRequest request);

  /// Stops the current search, if any.
  Future<void> stop();

  /// Stops everything and releases the engine process.
  Future<void> dispose();
}
