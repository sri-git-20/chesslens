import 'dart:async';

import 'package:multistockfish/multistockfish.dart';

import 'engine_service.dart';
import 'uci_engine_service.dart';

/// A [UciProcess] over a multistockfish engine.
class StockfishProcess implements UciProcess {
  StockfishProcess._(this._engine, this._log) {
    _subscription = _engine.stdout.listen(
      _controller.add,
      onDone: _end,
    );
    _engine.state.addListener(_onState);
  }

  /// Starts Stockfish for [spec]. Only one engine per flavor can exist at a
  /// time; the previous one must be disposed first (the service does that).
  static Future<StockfishProcess> start(
    EngineSpec spec, {
    void Function(String message)? log,
  }) async {
    final engine = await Stockfish.create(
      flavor: spec.flavor,
      nnuePath: spec.nnuePath,
    );
    return StockfishProcess._(engine, log ?? ((_) {}));
  }

  final Stockfish _engine;
  final void Function(String message) _log;
  final StreamController<String> _controller = StreamController<String>.broadcast();
  late final StreamSubscription<String> _subscription;
  bool _ended = false;

  @override
  Stream<String> get output => _controller.stream;

  void _onState() {
    final state = _engine.state.value;
    if (state == StockfishState.error || state == StockfishState.disposed) {
      _log('Stockfish state is now ${state.name}');
      _end();
    }
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _engine.state.removeListener(_onState);
    _subscription.cancel();
    _controller.close();
  }

  @override
  void send(String command) {
    if (_ended) throw StateError('The engine has ended');
    _engine.stdin = command;
  }

  @override
  Future<void> dispose() async {
    _end();
    await _engine.dispose();
  }
}

/// A [UciProcessFactory] that starts multistockfish.
UciProcessFactory stockfishProcessFactory({void Function(String message)? log}) =>
    (spec) => StockfishProcess.start(spec, log: log);
