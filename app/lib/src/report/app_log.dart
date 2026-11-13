import 'dart:convert';
import 'dart:io';

/// A small rolling log file. Lines are timestamped; when the file grows past
/// [maxBytes] the oldest lines are dropped.
///
/// Writing never throws: a broken log must not break the app. Do not log
/// personal data (names, e-mail addresses, photos, file names of the user).
class AppLog {
  AppLog(this.file, {this.maxBytes = defaultMaxBytes, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    try {
      if (file.existsSync()) _size = file.lengthSync();
    } catch (_) {
      _size = 0;
    }
  }

  static const int defaultMaxBytes = 500 * 1024;

  /// Longest single entry, so one huge error cannot fill the log.
  static const int maxEntryChars = 4000;

  final File file;
  final int maxBytes;
  final DateTime Function() _clock;
  int _size = 0;

  int get size => _size;

  void info(String message) => _write('I', message);

  void warn(String message) => _write('W', message);

  void error(String message, [Object? error, StackTrace? stack]) {
    final text = StringBuffer(message);
    if (error != null) text.write(': $error');
    if (stack != null) text.write('\n$stack');
    _write('E', text.toString());
  }

  /// The whole log, or an empty string.
  String read() {
    try {
      return file.existsSync() ? file.readAsStringSync() : '';
    } catch (_) {
      return '';
    }
  }

  void clear() {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
    _size = 0;
  }

  /// One log entry: a timestamp, a level and the text. Extra lines are
  /// indented so every entry starts at the beginning of a line.
  String format(String level, String message) {
    var text = message.trimRight();
    if (text.length > maxEntryChars) {
      text = '${text.substring(0, maxEntryChars)} ...[cut]';
    }
    final lines = text.split('\n');
    final buffer = StringBuffer('${_clock().toUtc().toIso8601String()} [$level] ${lines.first}');
    for (final line in lines.skip(1)) {
      buffer.write('\n    $line');
    }
    buffer.write('\n');
    return buffer.toString();
  }

  void _write(String level, String message) {
    try {
      final entry = format(level, message);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry, mode: FileMode.append, flush: true);
      _size += utf8.encode(entry).length;
      if (_size > maxBytes) _trim();
    } catch (_) {
      // Logging must never throw.
    }
  }

  /// Keeps about the newest 60% of the file, starting at a line boundary.
  void _trim() {
    final content = read();
    final keep = (maxBytes * 0.6).floor();
    if (content.length <= keep) {
      _size = utf8.encode(content).length;
      return;
    }
    var cut = content.length - keep;
    final newline = content.indexOf('\n', cut);
    cut = newline < 0 ? content.length : newline + 1;
    final kept = content.substring(cut);
    file.writeAsStringSync(kept, flush: true);
    _size = utf8.encode(kept).length;
  }
}
