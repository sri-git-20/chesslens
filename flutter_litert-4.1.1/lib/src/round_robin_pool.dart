import 'dart:async';

/// A generic round-robin pool with per-slot future-chain serialization locks.
///
/// Items are selected in round-robin order. Concurrent callers on the same
/// slot are serialized via a [Future] chain; callers on different slots
/// can run in parallel.
///
/// Example:
/// ```dart
/// final pool = RoundRobinPool([modelA, modelB, modelC]);
/// final result = await pool.withItem((model) async {
///   return model.run(input);
/// });
/// ```
class RoundRobinPool<T> {
  final List<T> _items;
  final List<Future<void>> _locks;
  int _counter = 0;

  RoundRobinPool(List<T> items)
    : _items = List.unmodifiable(items),
      _locks = List<Future<void>>.filled(
        items.length,
        Future.value(),
        growable: false,
      );

  /// Number of items in the pool.
  int get length => _items.length;

  /// Whether the pool contains no items.
  bool get isEmpty => _items.isEmpty;

  /// Runs [fn] with exclusive access to one item, selected round-robin.
  ///
  /// Throws [StateError] if the pool is empty.
  Future<R> withItem<R>(Future<R> Function(T) fn) async {
    if (_items.isEmpty) {
      throw StateError('RoundRobinPool is empty.');
    }

    final idx = _counter % _items.length;
    _counter = (_counter + 1) % _items.length;

    final prev = _locks[idx];
    final completer = Completer<void>();
    _locks[idx] = completer.future;

    try {
      await prev;
      return await fn(_items[idx]);
    } finally {
      completer.complete();
    }
  }
}
