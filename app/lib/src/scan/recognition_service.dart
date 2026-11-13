import 'dart:async';
import 'dart:isolate';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'geometry.dart';
import 'interpreter_models.dart';
import 'scan_engine.dart';

/// Reads chess diagrams from images. The app uses [IsolateRecognitionService];
/// tests use fakes.
abstract interface class RecognitionService {
  /// Decodes a page and finds and reads every board on it. [pageKey] names the
  /// page in later calls.
  Future<PageAnalysis> analyzePage(int pageKey, ScanInput input);

  /// Reads the board inside [quad] on a page returned by [analyzePage].
  Future<RawBoard> readQuad(int pageKey, Uint8List pageJpeg, Quad quad);

  /// Finds the board inside [region] and reads it.
  Future<RawBoard> readRegion(int pageKey, Uint8List pageJpeg, Quad region);

  Future<void> dispose();
}

/// The shared recognition service. Models load on first use and stay loaded.
final recognitionServiceProvider = Provider<RecognitionService>((ref) {
  final service = IsolateRecognitionService();
  ref.onDispose(service.dispose);
  return service;
});

const _modelFolder = 'assets/models';

/// Runs the whole pipeline on a long-lived worker isolate, so the UI stays
/// responsive. The models are read from assets on the main isolate and the
/// worker creates its interpreters from the bytes.
class IsolateRecognitionService implements RecognitionService {
  IsolateRecognitionService({Future<ByteData> Function(String)? loadAsset})
      : _loadAsset = loadAsset ?? rootBundle.load;

  final Future<ByteData> Function(String) _loadAsset;

  Future<SendPort>? _starting;
  Isolate? _isolate;
  ReceivePort? _replies;
  final Map<int, Completer<Object?>> _pending = {};
  int _nextId = 1;
  bool _disposed = false;

  Future<SendPort> _start() {
    return _starting ??= _spawn().catchError((Object error) {
      _starting = null;
      throw error;
    });
  }

  Future<Uint8List> _bytes(String name) async {
    try {
      final data = await _loadAsset('$_modelFolder/$name.tflite');
      return Uint8List.fromList(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    } catch (_) {
      throw const ScanException('The recognition models are missing from this build.');
    }
  }

  Future<SendPort> _spawn() async {
    final detector = await _bytes('detector');
    final corners = await _bytes('corners');
    final squares = await _bytes('squares');

    final ready = ReceivePort();
    final replies = ReceivePort();
    final exit = ReceivePort();
    _replies = replies;
    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _workerMain,
        _WorkerInit(ready.sendPort, replies.sendPort, detector, corners, squares),
        debugName: 'chesslens-recognition',
        onExit: exit.sendPort,
      );
    } catch (error) {
      ready.close();
      exit.close();
      replies.close();
      _replies = null;
      throw ScanException('The recognition worker could not start. $error');
    }
    _isolate = isolate;
    // If the worker dies (for example out of memory on a huge page), nobody
    // would ever answer: fail the waiting calls so the screen can show an
    // error, and start a fresh worker on the next call.
    exit.listen((_) {
      exit.close();
      ready.sendPort.send(_WorkerFailed('The recognition worker stopped.'));
      _onWorkerGone(isolate);
    });
    replies.listen(_onReply);
    final Object? first;
    try {
      first = await ready.first.timeout(const Duration(seconds: 60));
    } catch (_) {
      ready.close();
      isolate.kill(priority: Isolate.immediate);
      _onWorkerGone(isolate);
      throw const ScanException('The recognition worker did not start.');
    }
    ready.close();
    if (first is _WorkerFailed) {
      isolate.kill(priority: Isolate.immediate);
      _onWorkerGone(isolate);
      throw ScanException(first.message);
    }
    return first as SendPort;
  }

  void _onWorkerGone(Isolate isolate) {
    if (!identical(isolate, _isolate)) return;
    _isolate = null;
    _replies?.close();
    _replies = null;
    _starting = null;
    if (_disposed) return;
    final waiting = List<Completer<Object?>>.of(_pending.values);
    _pending.clear();
    for (final completer in waiting) {
      if (!completer.isCompleted) {
        completer.completeError(
          const ScanException('The recognition stopped unexpectedly. Please try again.'),
        );
      }
    }
  }

  void _onReply(Object? message) {
    if (message is! _Reply) return;
    final completer = _pending.remove(message.id);
    if (completer == null) return;
    final error = message.error;
    if (error != null) {
      completer.completeError(ScanException(error));
    } else {
      completer.complete(message.value);
    }
  }

  Future<T> _call<T>(_Request Function(int id) build) async {
    if (_disposed) throw const ScanException('Scanning was closed.');
    final port = await _start();
    if (_disposed) throw const ScanException('Scanning was closed.');
    if (_isolate == null) {
      throw const ScanException('The recognition stopped unexpectedly. Please try again.');
    }
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    port.send(build(id));
    return await completer.future as T;
  }

  @override
  Future<PageAnalysis> analyzePage(int pageKey, ScanInput input) =>
      _call((id) => _AnalyzeRequest(id, pageKey, input));

  @override
  Future<RawBoard> readQuad(int pageKey, Uint8List pageJpeg, Quad quad) =>
      _call((id) => _QuadRequest(id, pageKey, pageJpeg, quad.toList(), region: false));

  @override
  Future<RawBoard> readRegion(int pageKey, Uint8List pageJpeg, Quad region) =>
      _call((id) => _QuadRequest(id, pageKey, pageJpeg, region.toList(), region: true));

  @override
  Future<void> dispose() async {
    _disposed = true;
    final port = _starting == null ? null : await _starting!.then<SendPort?>((p) => p, onError: (_) => null);
    port?.send(null);
    _isolate?.kill();
    _isolate = null;
    _replies?.close();
    _replies = null;
    for (final c in _pending.values) {
      c.completeError(const ScanException('Scanning was closed.'));
    }
    _pending.clear();
  }
}

class _WorkerInit {
  _WorkerInit(this.ready, this.replies, this.detector, this.corners, this.squares);
  final SendPort ready;
  final SendPort replies;
  final Uint8List detector;
  final Uint8List corners;
  final Uint8List squares;
}

class _WorkerFailed {
  _WorkerFailed(this.message);
  final String message;
}

sealed class _Request {
  _Request(this.id);
  final int id;
}

class _AnalyzeRequest extends _Request {
  _AnalyzeRequest(super.id, this.pageKey, this.input);
  final int pageKey;
  final ScanInput input;
}

class _QuadRequest extends _Request {
  _QuadRequest(super.id, this.pageKey, this.jpeg, this.corners, {required this.region});
  final int pageKey;
  final Uint8List jpeg;
  final List<double> corners;
  final bool region;
}

class _Reply {
  _Reply(this.id, {this.value, this.error});
  final int id;
  final Object? value;
  final String? error;
}

void _workerMain(_WorkerInit init) {
  final InterpreterModels models;
  try {
    models = InterpreterModels.fromBytes(
      detector: init.detector,
      corners: init.corners,
      squares: init.squares,
    );
  } catch (error) {
    init.ready.send(_WorkerFailed('The recognition models could not be loaded. $error'));
    return;
  }
  final engine = ScanEngine(models.pipeline);
  final port = ReceivePort();
  init.ready.send(port.sendPort);
  port.listen((Object? message) {
    if (message == null) {
      models.close();
      port.close();
      return;
    }
    final request = message as _Request;
    try {
      final Object value;
      switch (request) {
        case _AnalyzeRequest():
          value = engine.analyze(request.pageKey, request.input);
        case _QuadRequest(:final region):
          final quad = Quad.fromList(request.corners);
          value = region
              ? engine.readRegion(request.pageKey, request.jpeg, quad)
              : engine.readQuad(request.pageKey, request.jpeg, quad);
      }
      init.replies.send(_Reply(request.id, value: value));
    } catch (error) {
      final text = error is ScanException ? error.message : 'Reading failed. $error';
      init.replies.send(_Reply(request.id, error: text));
    }
  });
}
