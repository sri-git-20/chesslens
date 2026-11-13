import 'dart:io' show Directory, File, Platform;

import 'package:chessground/chessground.dart' show PieceSet;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/board_themes.dart';

/// Provided in `main()` (and in tests) with an already-loaded instance, so
/// settings are available synchronously on the first frame.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a loaded instance',
  ),
);

/// Hash sizes offered in Settings, in MB.
const List<int> hashOptionsMb = [32, 64, 128, 256];

/// Depth limits offered in Settings. 0 means no limit.
const List<int> depthLimitOptions = [0, 20, 25, 30, 35, 40];

/// Time limits offered in Settings, in seconds. 0 means no limit.
const List<int> timeLimitOptions = [0, 10, 30, 60, 120, 300];

/// Processors minus one, at least 1 and at most 4.
int defaultEngineThreads() {
  final cores = Platform.numberOfProcessors;
  return clampInt(cores - 1, 1, 4);
}

int clampInt(int value, int low, int high) =>
    value < low ? low : (value > high ? high : value);

/// Run once at start-up, before the engine is created.
///
/// The stored path of the downloaded network is absolute. If the file is not
/// there any more (the app folder moved after an update, or the file was
/// removed), look for the same file name in [networkDirectory]; when it is not
/// there either, forget the setting so the engine runs the built-in network
/// instead of failing to start every time.
Future<void> repairNetworkPath(SharedPreferences prefs, Directory networkDirectory) async {
  const key = SettingsController.engineNetworkPathKey;
  final stored = prefs.getString(key);
  if (stored == null || stored.isEmpty) return;
  if (await File(stored).exists()) return;
  final moved = p.join(networkDirectory.path, p.basename(stored));
  if (await File(moved).exists()) {
    await prefs.setString(key, moved);
  } else {
    await prefs.remove(key);
  }
}

const Object _unset = Object();

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.trueBlack = false,
    this.boardTheme = BoardTheme.green,
    this.pieceSet = PieceSet.cburnett,
    this.showCoordinates = true,
    this.engineThreads = 1,
    this.engineHashMb = 64,
    this.multiPv = 2,
    this.depthLimit = 30,
    this.timeLimitSeconds = 60,
    this.engineNetworkPath,
  });

  /// Follow the phone (system), or force light or dark.
  final ThemeMode themeMode;

  /// Pure black backgrounds whenever the dark theme is showing.
  final bool trueBlack;

  final BoardTheme boardTheme;
  final PieceSet pieceSet;
  final bool showCoordinates;

  /// Engine threads (1 to 4).
  final int engineThreads;

  /// Engine hash table size in MB.
  final int engineHashMb;

  /// Number of lines in Analysis (1 to 3).
  final int multiPv;

  /// Analysis stops at this depth. 0 means no limit.
  final int depthLimit;

  /// Analysis stops after this many seconds. 0 means no limit.
  final int timeLimitSeconds;

  /// Path of a downloaded full network file. When set, the engine runs the
  /// full-network build; `null` means the built-in light network.
  final String? engineNetworkPath;

  AppSettings copyWith({
    ThemeMode? themeMode,
    bool? trueBlack,
    BoardTheme? boardTheme,
    PieceSet? pieceSet,
    bool? showCoordinates,
    int? engineThreads,
    int? engineHashMb,
    int? multiPv,
    int? depthLimit,
    int? timeLimitSeconds,
    Object? engineNetworkPath = _unset,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      trueBlack: trueBlack ?? this.trueBlack,
      boardTheme: boardTheme ?? this.boardTheme,
      pieceSet: pieceSet ?? this.pieceSet,
      showCoordinates: showCoordinates ?? this.showCoordinates,
      engineThreads: engineThreads ?? this.engineThreads,
      engineHashMb: engineHashMb ?? this.engineHashMb,
      multiPv: multiPv ?? this.multiPv,
      depthLimit: depthLimit ?? this.depthLimit,
      timeLimitSeconds: timeLimitSeconds ?? this.timeLimitSeconds,
      engineNetworkPath: identical(engineNetworkPath, _unset)
          ? this.engineNetworkPath
          : engineNetworkPath as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.themeMode == themeMode &&
      other.trueBlack == trueBlack &&
      other.boardTheme == boardTheme &&
      other.pieceSet == pieceSet &&
      other.showCoordinates == showCoordinates &&
      other.engineThreads == engineThreads &&
      other.engineHashMb == engineHashMb &&
      other.multiPv == multiPv &&
      other.depthLimit == depthLimit &&
      other.timeLimitSeconds == timeLimitSeconds &&
      other.engineNetworkPath == engineNetworkPath;

  @override
  int get hashCode => Object.hash(
        themeMode,
        trueBlack,
        boardTheme,
        pieceSet,
        showCoordinates,
        engineThreads,
        engineHashMb,
        multiPv,
        depthLimit,
        timeLimitSeconds,
        engineNetworkPath,
      );
}

class SettingsController extends Notifier<AppSettings> {
  static const String themeModeKey = 'settings.themeMode';
  static const String trueBlackKey = 'settings.trueBlack';
  static const String boardThemeKey = 'settings.boardTheme';
  static const String pieceSetKey = 'settings.pieceSet';
  static const String showCoordinatesKey = 'settings.showCoordinates';
  static const String engineThreadsKey = 'settings.engineThreads';
  static const String engineHashKey = 'settings.engineHashMb';
  static const String multiPvKey = 'settings.multiPv';
  static const String depthLimitKey = 'settings.depthLimit';
  static const String timeLimitKey = 'settings.timeLimitSeconds';
  static const String engineNetworkPathKey = 'settings.engineNetworkPath';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final storedMode = prefs.getString(themeModeKey);
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere(
        (mode) => mode.name == storedMode,
        orElse: () => ThemeMode.system,
      ),
      trueBlack: prefs.getBool(trueBlackKey) ?? false,
      boardTheme: BoardTheme.fromName(prefs.getString(boardThemeKey)),
      pieceSet: pieceSetFromName(prefs.getString(pieceSetKey)),
      showCoordinates: prefs.getBool(showCoordinatesKey) ?? true,
      engineThreads: clampInt(
        prefs.getInt(engineThreadsKey) ?? defaultEngineThreads(),
        1,
        4,
      ),
      engineHashMb: _oneOf(prefs.getInt(engineHashKey), hashOptionsMb, 64),
      multiPv: clampInt(prefs.getInt(multiPvKey) ?? 2, 1, 3),
      depthLimit: _oneOf(prefs.getInt(depthLimitKey), depthLimitOptions, 30),
      timeLimitSeconds:
          _oneOf(prefs.getInt(timeLimitKey), timeLimitOptions, 60),
      engineNetworkPath: prefs.getString(engineNetworkPathKey),
    );
  }

  static int _oneOf(int? value, List<int> allowed, int fallback) =>
      value != null && allowed.contains(value) ? value : fallback;

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(themeModeKey, mode.name);
  }

  Future<void> setTrueBlack(bool value) async {
    state = state.copyWith(trueBlack: value);
    await _prefs.setBool(trueBlackKey, value);
  }

  Future<void> setBoardTheme(BoardTheme theme) async {
    state = state.copyWith(boardTheme: theme);
    await _prefs.setString(boardThemeKey, theme.name);
  }

  Future<void> setPieceSet(PieceSet pieceSet) async {
    state = state.copyWith(pieceSet: pieceSet);
    await _prefs.setString(pieceSetKey, pieceSet.name);
  }

  Future<void> setShowCoordinates(bool value) async {
    state = state.copyWith(showCoordinates: value);
    await _prefs.setBool(showCoordinatesKey, value);
  }

  Future<void> setEngineThreads(int value) async {
    final threads = clampInt(value, 1, 4);
    state = state.copyWith(engineThreads: threads);
    await _prefs.setInt(engineThreadsKey, threads);
  }

  Future<void> setEngineHashMb(int value) async {
    state = state.copyWith(engineHashMb: value);
    await _prefs.setInt(engineHashKey, value);
  }

  Future<void> setMultiPv(int value) async {
    final lines = clampInt(value, 1, 3);
    state = state.copyWith(multiPv: lines);
    await _prefs.setInt(multiPvKey, lines);
  }

  Future<void> setDepthLimit(int value) async {
    state = state.copyWith(depthLimit: value);
    await _prefs.setInt(depthLimitKey, value);
  }

  Future<void> setTimeLimitSeconds(int value) async {
    state = state.copyWith(timeLimitSeconds: value);
    await _prefs.setInt(timeLimitKey, value);
  }

  /// Chooses the engine build: a network file path for the full-network
  /// engine, or `null` for the built-in light network.
  Future<void> setEngineNetworkPath(String? path) async {
    state = state.copyWith(engineNetworkPath: path);
    if (path == null) {
      await _prefs.remove(engineNetworkPathKey);
    } else {
      await _prefs.setString(engineNetworkPathKey, path);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);
