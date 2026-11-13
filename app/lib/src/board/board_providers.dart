import 'package:chessground/chessground.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../settings/settings_controller.dart';

/// Board look from settings: colours, piece set, coordinates.
final chessboardSettingsProvider = Provider<ChessboardSettings>((ref) {
  final settings = ref.watch(settingsProvider);
  return ChessboardSettings(
    colorScheme: settings.boardTheme.colors,
    pieceAssets: settings.pieceSet.assets,
    enableCoordinates: settings.showCoordinates,
    enablePremoves: false,
    animationDuration: const Duration(milliseconds: 180),
  );
});

/// The same look for the non-interactive board (thumbnails, previews).
final staticBoardSettingsProvider = Provider<StaticChessboardSettings>((ref) {
  final settings = ref.watch(settingsProvider);
  return StaticChessboardSettings(
    colorScheme: settings.boardTheme.colors,
    pieceAssets: settings.pieceSet.assets,
    enableCoordinates: settings.showCoordinates,
    animationDuration: Duration.zero,
  );
});
