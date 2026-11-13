import 'dart:async';

import 'package:flutter/foundation.dart';

import '../chess/board_utils.dart';
import 'engine_service.dart';
import 'uci.dart';

/// A running UCI engine process. [UciEngineService] talks to the engine only
/// through this interface, so it can be tested with a scripted fake.
abstract interface class UciProcess {
  /// Engine output, one line per event. Broadcast. Closes when the process
  /// ends, whatever the reason.
  Stream<String> get output;

  /// Sends one UCI command. Throws [StateError] when the process is not
  /// running.
  void send(String command);

  /// Quits the engine and frees it.
  Future<void> dispose();
}

typedef UciProcessFactory = Future<UciProcess> Function(EngineSpec spec);

class _Waiter {
  _Waiter(this.test) : completer = Completer<String>();
  final bool Function(String line) test;
  final Completer<String> completer;
}

class _Search {
  _Search(this.request) {
    controller = StreamController<AnalysisUpdate>();
  }

  final AnalysisRequest request;
  late final StreamController<AnalysisUpdate> controller;
  final Map<int, EngineLine> lines = {};
  Completer<void> done = Completer<void>();
  bool cancelled = false;
  bool closed = false;
  int restarts = 0;

  void restartState() {
    lines.clear();
    if (done.isCompleted) done = Completer<void>();
  }

  void emit(AnalysisUpdate update) {
    if (!closed) controller.add(update);
  }

  void closeSilently() {
    if (!done.isCompleted) done.complete();
    if (!closed) {
      closed = true;
      controller.close();
    }
  }

  void fail(Object error) {
    if (!done.isCompleted) done.complete();
    if (!closed) {
      closed = true;
      controller.addError(error);
      controller.close();
    }
  }
}

/// [EngineService] for any UCI engine.
///
/// Commands are serialized: a new search first sends `stop` and waits for the
/// old `bestmove`, then `isready` / `readyok`, and only then `position` and
/// `go`. Only legal positions are ever sent. If the process ends, it is
/// recreated on the next use, and a search that was running is restarted once.
class UciEngineService implements EngineService {
  UciEngineService({
    required UciProcessFactory processFactory,
    EngineSpec spec = EngineSpec.light,
    EngineSettings settings = const EngineSettings(),
    Duration readyTimeout = const Duration(seconds: 15),
    Duration stopTimeout = const Duration(seconds: 3),
    void Function(String message)? log,
  })  : _processFactory = processFactory,
        _spec = spec,
        _settings = settings,
        _readyTimeout = readyTimeout,
        _stopTimeout = stopTimeout,
        _log = log ?? ((_) {});

  final UciProcessFactory _processFactory;
  final Duration _readyTimeout;
  final Duration _stopTimeout;
  final void Function(String message) _log;

  final ValueNotifier<EngineStatus> _status = ValueNotifier(EngineStatus.idle);
  EngineSpec _spec;
  EngineSettings _settings;

  UciProcess? _process;
  StreamSubscription<String>? _subscription;
  final Map<String, String> _applied = {};
  final List<_Waiter> _waiters = [];
  EloRange? _eloRange;
  int? _maxThreads;
  int? _maxHash;

  _Search? _active;
  final List<_Search> _queued = [];
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  @override
  ValueListenable<EngineStatus> get status => _status;

  @override
  EngineSpec get spec => _spec;

  // ---------------------------------------------------------------- queue

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await task());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Queues [task] and logs instead of throwing, for callers that do not wait.
  void _fire(Future<void> Function() task) {
    _enqueue(task).then<void>(
      (_) {},
      onError: (Object error) => _log('Engine task failed: $error'),
    );
  }

  // -------------------------------------------------------------- process

  Future<UciProcess> _ensureProcess() async {
    final existing = _process;
    if (existing != null) return existing;
    if (_disposed) throw const EngineFailure('The engine was shut down.');

    _status.value = EngineStatus.starting;
    final UciProcess process;
    try {
      process = await _processFactory(_spec);
    } catch (error) {
      _log('Could not start the engine ($_spec): $error');
      _status.value = EngineStatus.failed;
      throw EngineFailure('Stockfish could not start. $error');
    }
    _process = process;
    _applied.clear();
    _subscription = process.output.listen(
      _onLine,
      onDone: () => _onProcessEnded(process),
    );
    try {
      final uciok = _expect((line) => line == 'uciok', 'uciok');
      process.send('uci');
      await uciok;
      await _isReady(process);
    } catch (error) {
      _log('The engine did not answer the UCI handshake: $error');
      await _killProcess();
      _status.value = EngineStatus.failed;
      throw EngineFailure('Stockfish did not respond. $error');
    }
    _status.value = EngineStatus.ready;
    return process;
  }

  Future<void> _isReady(UciProcess process) async {
    final ready = _expect((line) => line == 'readyok', 'readyok');
    process.send('isready');
    await ready;
  }

  Future<String> _expect(bool Function(String line) test, String what) {
    final waiter = _Waiter(test);
    _waiters.add(waiter);
    return waiter.completer.future.timeout(
      _readyTimeout,
      onTimeout: () {
        _waiters.remove(waiter);
        throw EngineFailure('Timed out waiting for $what.');
      },
    );
  }

  void _failWaiters(String message) {
    final waiters = List<_Waiter>.of(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      if (!waiter.completer.isCompleted) {
        waiter.completer.completeError(EngineFailure(message));
      }
    }
  }

  Future<void> _killProcess() async {
    final process = _process;
    _process = null;
    await _subscription?.cancel();
    _subscription = null;
    _applied.clear();
    _failWaiters('The engine stopped.');
    final active = _active;
    _active = null;
    active?.closeSilently();
    if (process != null) {
      try {
        await process.dispose();
      } catch (error) {
        _log('Error while disposing the engine: $error');
      }
    }
    if (_status.value != EngineStatus.failed) _status.value = EngineStatus.idle;
  }

  void _onProcessEnded(UciProcess process) {
    if (!identical(process, _process)) return;
    _log('The engine process ended unexpectedly ($_spec). It is recreated on '
        'the next use.');
    _process = null;
    _subscription?.cancel();
    _subscription = null;
    _applied.clear();
    _failWaiters('The engine stopped unexpectedly.');
    _status.value = EngineStatus.failed;

    final search = _active;
    _active = null;
    if (search == null) return;
    if (!search.done.isCompleted) search.done.complete();
    if (search.cancelled) {
      search.closeSilently();
    } else if (search.restarts < 1 && !_disposed) {
      search.restarts++;
      search.restartState();
      _log('Restarting the interrupted search.');
      _queued.add(search);
      _fire(() => _runSearch(search));
    } else {
      search.fail(const EngineFailure('The engine stopped unexpectedly.'));
    }
  }

  // ---------------------------------------------------------------- lines

  void _onLine(String line) {
    for (final waiter in List<_Waiter>.of(_waiters)) {
      if (waiter.test(line)) {
        _waiters.remove(waiter);
        if (!waiter.completer.isCompleted) waiter.completer.complete(line);
      }
    }
    if (line.startsWith('info')) {
      _onInfo(line);
    } else if (line.startsWith('bestmove')) {
      _onBestMove(line);
    } else if (line.startsWith('option ')) {
      _onOption(line);
    }
  }

  void _onOption(String line) {
    final option = parseSpinOption(line);
    if (option == null) return;
    switch (option.name) {
      case 'UCI_Elo':
        if (option.min != null && option.max != null) {
          _eloRange = EloRange(option.min!, option.max!);
        }
      case 'Threads':
        _maxThreads = option.max;
      case 'Hash':
        _maxHash = option.max;
    }
  }

  void _onInfo(String line) {
    final search = _active;
    if (search == null || search.cancelled) return;
    final info = parseInfoLine(line);
    if (info == null || info.score == null || info.depth == null) return;
    if (info.score!.bound != ScoreBound.exact) return;
    if (info.multipv > search.request.multiPv) return;
    search.lines[info.multipv] = EngineLine(
      multiPv: info.multipv,
      depth: info.depth!,
      seldepth: info.seldepth,
      score: info.score!,
      pv: info.pv,
      nodes: info.nodes,
      nps: info.nps,
      timeMs: info.timeMs,
    );
    search.emit(_updateFor(search, isFinal: false));
  }

  AnalysisUpdate _updateFor(_Search search, {required bool isFinal, String? bestMove}) {
    final keys = search.lines.keys.toList()..sort();
    final lines = [for (final key in keys) search.lines[key]!];
    final best = lines.isEmpty ? null : lines.first;
    return AnalysisUpdate(
      lines: lines,
      depth: best?.depth ?? 0,
      isFinal: isFinal,
      bestMove: bestMove,
      nodes: best?.nodes,
      nps: best?.nps,
      timeMs: best?.timeMs,
    );
  }

  void _onBestMove(String line) {
    final search = _active;
    if (search == null) return;
    _active = null;
    final parsed = parseBestMove(line);
    if (!search.done.isCompleted) search.done.complete();
    if (search.cancelled) {
      search.closeSilently();
      return;
    }
    search.emit(_updateFor(search, isFinal: true, bestMove: parsed?.move));
    search.closeSilently();
  }

  // ------------------------------------------------------------- API

  @override
  Future<void> ensureStarted() => _enqueue(() async {
        await _ensureProcess();
      });

  @override
  Future<void> restart(EngineSpec spec) => _enqueue(() async {
        for (final search in List<_Search>.of(_queued)) {
          search.cancelled = true;
          search.closeSilently();
        }
        _queued.clear();
        _active?.cancelled = true;
        final changed = spec != _spec;
        _spec = spec;
        if (changed || _process != null) {
          _eloRange = null;
          await _killProcess();
        }
      });

  @override
  void applySettings(EngineSettings settings) {
    _settings = settings;
  }

  @override
  Future<EloRange> eloRange() => _enqueue(() async {
        await _ensureProcess();
        return _eloRange ?? EloRange.fallback;
      });

  @override
  Stream<AnalysisUpdate> analyze(AnalysisRequest request) {
    if (chessFromFen(request.fen) == null) {
      throw IllegalPositionException(request.fen);
    }
    for (final search in List<_Search>.of(_queued)) {
      search.cancelled = true;
      search.closeSilently();
    }
    _queued.clear();

    final search = _Search(request);
    search.controller.onCancel = () => _onSearchCancelled(search);
    _queued.add(search);
    _fire(() => _runSearch(search));
    return search.controller.stream;
  }

  void _onSearchCancelled(_Search search) {
    if (search.closed && search.done.isCompleted) return;
    search.cancelled = true;
    if (identical(_active, search)) {
      _fire(() => _stopIfActive(search));
    }
  }

  Future<void> _stopIfActive(_Search search) async {
    if (identical(_active, search)) await _stopActive();
  }

  @override
  Future<void> stop() {
    for (final search in List<_Search>.of(_queued)) {
      search.cancelled = true;
      search.closeSilently();
    }
    _queued.clear();
    final active = _active;
    if (active != null) active.cancelled = true;
    return _enqueue(() async {
      await _stopActive();
    });
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final search in List<_Search>.of(_queued)) {
      search.cancelled = true;
      search.closeSilently();
    }
    _queued.clear();
    await _enqueue(() async {
      await _stopActive();
      await _killProcess();
    });
    _status.value = EngineStatus.idle;
  }

  // ------------------------------------------------------------- search

  /// Stops the running search, if any, and waits for its `bestmove`. Returns
  /// whether there was a search to stop.
  Future<bool> _stopActive() async {
    final active = _active;
    final process = _process;
    if (active == null) return false;
    active.cancelled = true;
    if (process == null) {
      active.closeSilently();
      _active = null;
      return true;
    }
    try {
      process.send('stop');
    } catch (error) {
      _log('Could not send stop: $error');
    }
    try {
      await active.done.future.timeout(_stopTimeout);
    } on TimeoutException {
      _log('The engine did not stop in time. It is restarted.');
      await _killProcess();
    }
    return true;
  }

  Future<void> _runSearch(_Search search) async {
    _queued.remove(search);
    if (search.cancelled || _disposed) {
      search.closeSilently();
      return;
    }
    try {
      final stopped = await _stopActive();
      final process = await _ensureProcess();
      if (search.cancelled) {
        search.closeSilently();
        return;
      }
      final request = search.request;

      if (request.newGame) process.send('ucinewgame');
      final changed = _sendOptions(process, request);
      // After a stop, and after changing options, wait until the engine is
      // idle again before sending the position.
      if (stopped || changed || request.newGame) await _isReady(process);
      if (search.cancelled) {
        search.closeSilently();
        return;
      }

      process.send('position fen ${request.fen}');
      final go = StringBuffer('go');
      final limit = request.limit;
      if (limit.depth != null) go.write(' depth ${limit.depth}');
      if (limit.movetimeMs != null) go.write(' movetime ${limit.movetimeMs}');
      if (limit.isInfinite) go.write(' infinite');
      if (request.searchMoves.isNotEmpty) {
        // searchmoves swallows everything after it, so it must come last.
        go.write(' searchmoves ${request.searchMoves.join(' ')}');
      }
      _active = search;
      process.send(go.toString());
    } catch (error) {
      _log('Search failed: $error');
      if (identical(_active, search)) _active = null;
      search.fail(error is EngineFailure ? error : EngineFailure('$error'));
    }
  }

  /// Sends the options that differ from what the engine has. Returns whether
  /// anything was sent.
  bool _sendOptions(UciProcess process, AnalysisRequest request) {
    var threads = _settings.threads;
    if (_maxThreads != null && threads > _maxThreads!) threads = _maxThreads!;
    if (threads < 1) threads = 1;
    var hash = _settings.hashMb;
    if (_maxHash != null && hash > _maxHash!) hash = _maxHash!;

    final strength = request.strength;
    final wanted = <String, String>{
      'Threads': '$threads',
      'Hash': '$hash',
      'MultiPV': '${request.multiPv < 1 ? 1 : request.multiPv}',
      'UCI_LimitStrength': strength.elo != null ? 'true' : 'false',
      if (strength.elo != null) 'UCI_Elo': '${strength.elo}',
      'Skill Level': '${strength.skillLevel ?? 20}',
    };
    var sent = false;
    for (final entry in wanted.entries) {
      if (_applied[entry.key] == entry.value) continue;
      process.send('setoption name ${entry.key} value ${entry.value}');
      _applied[entry.key] = entry.value;
      sent = true;
    }
    return sent;
  }
}
