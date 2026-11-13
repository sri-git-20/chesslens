import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'board_providers.dart';

/// A small non-interactive board from a FEN (placement is enough), themed from
/// settings. Used for thumbnails and the settings preview.
class StaticBoard extends ConsumerWidget {
  const StaticBoard({
    super.key,
    required this.fen,
    required this.size,
    this.orientation = Side.white,
    this.showCoordinates,
  });

  final String fen;
  final double size;
  final Side orientation;

  /// Overrides the coordinates setting (thumbnails hide them).
  final bool? showCoordinates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var settings = ref.watch(staticBoardSettingsProvider);
    if (showCoordinates != null) {
      settings = StaticChessboardSettings(
        colorScheme: settings.colorScheme,
        pieceAssets: settings.pieceAssets,
        enableCoordinates: showCoordinates!,
        animationDuration: Duration.zero,
      );
    }
    return StaticChessboard(
      size: size,
      orientation: orientation,
      fen: fen,
      settings: settings,
    );
  }
}
