import 'dart:async';
import 'dart:isolate';

/// RPC client that sends requests to and receives responses from an isolate.
class IsolateRpcClient {
  final Map<int, Completer<dynamic>> _pending = {};
  int _nextId = 0;

  SendPort? sendPort;
  Isolate? isolate;
  final ReceivePort receivePort = ReceivePort();

  /// Sends an RPC request to the isolate and returns the typed response future.
  Future<T> sendRequest<T>(
    String operation,
    Map<String, dynamic> params,
  ) async {
    if (sendPort == null) {
      throw StateError('IsolateRpcClient not ready: sendPort is null');
    }

    final int id = _nextId++;
    final Completer<T> completer = Completer<T>();
    _pending[id] = completer;

    try {
      sendPort!.send({'id': id, 'op': operation, ...params});
      return await completer.future;
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }
  }

  /// Dispatches an incoming isolate message to the matching pending completer.
  void handleResponse(
    dynamic message, {
    Object Function(String)? errorWrapper,
  }) {
    if (message is! Map) return;

    final int? id = message['id'] as int?;
    if (id == null) return;

    final Completer<dynamic>? completer = _pending.remove(id);
    if (completer == null) return;

    if (message['error'] != null) {
      final errorMsg = message['error'] as String;
      final error = errorWrapper != null
          ? errorWrapper(errorMsg)
          : StateError(errorMsg);
      completer.completeError(error);
    } else {
      completer.complete(message['result']);
    }
  }

  /// Fails all pending requests, optionally sends a dispose op, and kills the isolate.
  void failAllAndDispose({String? disposeOp}) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(StateError('IsolateRpcClient disposed'));
      }
    }
    _pending.clear();

    if (disposeOp != null && sendPort != null) {
      try {
        sendPort!.send({'id': -1, 'op': disposeOp});
      } catch (_) {}
    }

    isolate?.kill(priority: Isolate.immediate);
    receivePort.close();

    isolate = null;
    sendPort = null;
  }

  /// Gracefully disposes: sends [disposeOp] as a request and awaits the
  /// isolate's ack (so it can free native resources) before force-killing via
  /// [failAllAndDispose].
  ///
  /// The raw-client analogue of `IsolateWorkerBase.disposeGracefully`, for
  /// isolates managed directly via an [IsolateRpcClient] rather than a worker.
  ///
  /// Best-effort: if [disposeOp] is null, the client is not ready, or the ack
  /// does not arrive within [timeout], it falls through to [failAllAndDispose].
  /// The isolate's dispose handler must reply `{'id': id, 'result': ...}`.
  Future<void> disposeGracefully({
    String? disposeOp,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (disposeOp != null && sendPort != null) {
      try {
        await sendRequest<dynamic>(
          disposeOp,
          const <String, dynamic>{},
        ).timeout(timeout);
      } catch (_) {
        // Best-effort; fall through to the synchronous force-kill below.
      }
    }
    failAllAndDispose();
  }
}

/// Performs the initial SendPort handshake with a newly spawned isolate.
Future<SendPort> setupIsolateHandshake({
  required ReceivePort receivePort,
  required void Function(dynamic) onResponse,
  required Duration timeout,
  required String timeoutMessage,
}) async {
  final Completer<SendPort> initCompleter = Completer<SendPort>();
  late final StreamSubscription<dynamic> subscription;

  subscription = receivePort.listen((message) {
    if (!initCompleter.isCompleted) {
      if (message is SendPort) {
        initCompleter.complete(message);
      } else if (message is Map && message['error'] != null) {
        initCompleter.completeError(StateError(message['error'] as String));
      } else {
        initCompleter.completeError(
          StateError('Expected SendPort, got ${message.runtimeType}'),
        );
      }
      return;
    }
    onResponse(message);
  });

  return initCompleter.future.timeout(
    timeout,
    onTimeout: () {
      subscription.cancel();
      throw TimeoutException(timeoutMessage);
    },
  );
}
