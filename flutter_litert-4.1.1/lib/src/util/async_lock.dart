/// A lightweight sequential async lock that serializes tasks through a future
/// chain, preventing concurrent access to shared mutable state that is not
/// thread-safe (e.g. a [CompiledModel] slot or interpreter input/output
/// buffers).
///
/// Tasks registered via [run] execute strictly first-in-first-out: each task
/// waits for every previously-registered task to settle before it starts, so no
/// two tasks ever overlap. A task that throws propagates its error to its own
/// caller but does not poison the chain: tasks registered after it still run.
///
/// Registration is synchronous, so calling [run] twice in a row (without
/// awaiting) reserves slots in call order.
///
/// ```dart
/// final lock = AsyncLock();
/// final a = lock.run(() => inferA()); // runs first
/// final b = lock.run(() => inferB()); // runs after a settles
/// ```
class AsyncLock {
  Future<void> _tail = Future<void>.value();

  /// Runs [task] after all previously-registered tasks have settled, and
  /// returns its result (or rethrows its error) to the caller.
  Future<T> run<T>(Future<T> Function() task) {
    final Future<T> result = _tail.then((_) => task());
    // Keep the chain alive but swallow errors so one failed task does not
    // poison every later call.
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
