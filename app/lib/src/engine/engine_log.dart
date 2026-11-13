/// The last engine messages (start-up, crashes, restarts), kept in memory so
/// a bug report can include them.
class EngineLog {
  EngineLog({this.capacity = 200});

  final int capacity;
  final List<String> _lines = [];

  List<String> get lines => List.unmodifiable(_lines);

  void add(String message) {
    _lines.add('${DateTime.now().toIso8601String()} $message');
    if (_lines.length > capacity) _lines.removeAt(0);
  }
}
