import 'dart:io';

/// Two marker files that tell the next launch whether the last session ended
/// badly:
///
/// * `session.open` exists while the app is in the foreground. It is removed
///   when the app goes to the background, so a normal exit leaves no marker.
/// * `errors.pending` exists after a Dart error was logged, until a report has
///   been sent.
class SessionState {
  SessionState(this.directory);

  final Directory directory;

  File get _open => File('${directory.path}${Platform.pathSeparator}session.open');
  File get _errors => File('${directory.path}${Platform.pathSeparator}errors.pending');

  bool get wasOpen => _exists(_open);
  bool get hasErrors => _exists(_errors);

  void markOpen() => _create(_open);
  void markClosed() => _delete(_open);
  void markErrors() => _create(_errors);
  void clearErrors() => _delete(_errors);

  static bool _exists(File file) {
    try {
      return file.existsSync();
    } catch (_) {
      return false;
    }
  }

  static void _create(File file) {
    try {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('1', flush: true);
    } catch (_) {}
  }

  static void _delete(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}
