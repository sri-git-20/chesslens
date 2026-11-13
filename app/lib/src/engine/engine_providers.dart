import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_controller.dart';
import 'engine_log.dart';
import 'engine_service.dart';
import 'stockfish_process.dart';
import 'uci_engine_service.dart';

/// In-memory log of engine events, for bug reports.
final engineLogProvider = Provider<EngineLog>((ref) => EngineLog());

/// The engine build chosen in settings. Changing it restarts the engine.
final engineSpecProvider = Provider<EngineSpec>((ref) {
  final path = ref.watch(settingsProvider.select((s) => s.engineNetworkPath));
  return EngineSpec.forNetworkPath(path);
});

/// Threads and hash from settings.
final engineSettingsProvider = Provider<EngineSettings>((ref) {
  final threads = ref.watch(settingsProvider.select((s) => s.engineThreads));
  final hash = ref.watch(settingsProvider.select((s) => s.engineHashMb));
  return EngineSettings(threads: threads, hashMb: hash);
});

/// Creates the engine service. Tests override [engineServiceProvider] with a
/// fake instead.
final engineServiceProvider = Provider<EngineService>((ref) {
  final log = ref.read(engineLogProvider);
  void logMessage(String message) {
    log.add(message);
    debugPrint('[engine] $message');
  }

  final service = UciEngineService(
    processFactory: stockfishProcessFactory(log: logMessage),
    spec: ref.read(engineSpecProvider),
    settings: ref.read(engineSettingsProvider),
    log: logMessage,
  );
  ref.listen<EngineSpec>(engineSpecProvider, (previous, next) {
    if (previous != next) {
      logMessage('Switching engine to $next');
      service.restart(next);
    }
  });
  ref.listen<EngineSettings>(engineSettingsProvider, (previous, next) {
    service.applySettings(next);
  });
  ref.onDispose(service.dispose);
  return service;
});
