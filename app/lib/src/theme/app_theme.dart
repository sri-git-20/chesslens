import 'package:flutter/material.dart';

/// Material 3 themes for ChessLens: light, dark and true-black dark.
abstract final class AppTheme {
  /// A muted chess-board green used to derive both colour schemes.
  static const Color seed = Color(0xFF3A6B4F);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return _base(scheme);
  }

  /// Dark theme. With [trueBlack], backgrounds are pure black so OLED
  /// screens switch those pixels off, saving battery.
  static ThemeData dark({required bool trueBlack}) {
    var scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    if (trueBlack) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF111111),
        surfaceContainerHigh: const Color(0xFF181818),
        surfaceContainerHighest: const Color(0xFF202020),
      );
    }
    return _base(scheme).copyWith(
      scaffoldBackgroundColor: trueBlack ? Colors.black : scheme.surface,
    );
  }

  static ThemeData _base(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        centerTitle: false,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20),
      ),
    );
  }
}
