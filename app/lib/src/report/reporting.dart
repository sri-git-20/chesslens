import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../app_info.dart';
import 'app_log.dart';
import 'session_state.dart';

/// The error log and crash detection of this run.
class Reporting {
  Reporting({
    required this.log,
    required this.session,
    required this.previousSessionProblem,
  });

  final AppLog log;
  final SessionState session;

  /// The last session ended without a clean exit, or logged Dart errors that
  /// were never reported.
  bool previousSessionProblem;

  /// Set by [initReporting]. `null` in tests and when start-up failed.
  static Reporting? instance;

  /// Called when a report was sent: the errors in the log are now reported.
  void reportSent(String kind) {
    log.info('Report sent: $kind');
    session.clearErrors();
    previousSessionProblem = false;
  }

  /// The user chose "Not now".
  void promptDismissed() {
    previousSessionProblem = false;
  }

  void recordError(String where, Object error, StackTrace? stack) {
    log.error(where, error, stack);
    session.markErrors();
  }
}

final reportingProvider = Provider<Reporting?>((ref) => Reporting.instance);

/// Starts the log, installs the error handlers and writes the session marker.
/// Never throws; if anything fails the app simply runs without a log.
Future<void> initReporting() async {
  try {
    final directory = Directory(
      '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}reports',
    );
    await directory.create(recursive: true);
    final session = SessionState(directory);
    final problem = session.wasOpen || session.hasErrors;
    final log = AppLog(File('${directory.path}${Platform.pathSeparator}chesslens.log'));
    final reporting = Reporting(
      log: log,
      session: session,
      previousSessionProblem: problem,
    );
    Reporting.instance = reporting;

    log.info('Session started: $appName $appVersion (build $buildNumber)');
    if (problem) {
      log.warn(
        session.wasOpen
            ? 'The previous session did not end cleanly.'
            : 'The previous session logged errors.',
      );
    }
    session.markOpen();
    _installHandlers(reporting);
    WidgetsBinding.instance.addObserver(_LifecycleMarker(reporting));
  } catch (error) {
    debugPrint('Could not start the error log: $error');
  }
}

void _installHandlers(Reporting reporting) {
  final previousFlutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    reporting.recordError('Flutter error', details.exception, details.stack);
    if (previousFlutterHandler != null) {
      previousFlutterHandler(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  final previousDispatcher = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    reporting.recordError('Uncaught error', error, stack);
    return previousDispatcher?.call(error, stack) ?? true;
  };

  // Errors that escape from other isolates arrive as [error, stack] pairs.
  final port = RawReceivePort((Object? pair) {
    if (pair is List && pair.length == 2) {
      reporting.recordError(
        'Isolate error',
        '${pair[0]}',
        StackTrace.fromString('${pair[1]}'),
      );
    }
  });
  Isolate.current.addErrorListener(port.sendPort);
}

/// Removes the "session open" marker when the app goes to the background and
/// sets it again on resume, so only a crash or a kill in the foreground
/// leaves it behind.
class _LifecycleMarker with WidgetsBindingObserver {
  _LifecycleMarker(this._reporting);

  final Reporting _reporting;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _reporting.session.markClosed();
      case AppLifecycleState.resumed:
        _reporting.session.markOpen();
      default:
        break;
    }
  }
}
