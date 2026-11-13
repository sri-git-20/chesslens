import 'package:flutter/material.dart';

import 'share_actions.dart';

enum _ExportAction { copyFen, copyPgn, shareImage, openLichess, reportRecognition }

/// The "Share and export" menu of Review and Analysis.
///
/// [fen] and [pgn] are read when the menu opens, so they are always current.
/// A `null` [fen] (an illegal position in Review) disables the entries.
class ExportMenuButton extends StatelessWidget {
  const ExportMenuButton({
    super.key,
    required this.fen,
    required this.pgn,
    required this.boardKey,
    this.onReportRecognition,
  });

  final String? Function() fen;
  final String? Function() pgn;

  /// Key of the [RepaintBoundary] around the board.
  final GlobalKey boardKey;

  /// Adds "Report wrong recognition" when set.
  final VoidCallback? onReportRecognition;

  Future<void> _onSelected(BuildContext context, _ExportAction action) async {
    final currentFen = fen();
    switch (action) {
      case _ExportAction.copyFen:
        if (currentFen != null) await copyToClipboard(context, currentFen, 'FEN');
      case _ExportAction.copyPgn:
        final text = pgn();
        if (text != null) await copyToClipboard(context, text, 'PGN');
      case _ExportAction.shareImage:
        await shareBoardImage(context, boardKey);
      case _ExportAction.openLichess:
        if (currentFen != null) await openInLichess(context, currentFen);
      case _ExportAction.reportRecognition:
        onReportRecognition?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ExportAction>(
      tooltip: 'Share and export',
      icon: const Icon(Icons.ios_share),
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) {
        final enabled = fen() != null;
        return [
          PopupMenuItem(
            value: _ExportAction.copyFen,
            enabled: enabled,
            child: const Text('Copy FEN'),
          ),
          PopupMenuItem(
            value: _ExportAction.copyPgn,
            enabled: enabled,
            child: const Text('Copy PGN'),
          ),
          const PopupMenuItem(
            value: _ExportAction.shareImage,
            child: Text('Share board image'),
          ),
          PopupMenuItem(
            value: _ExportAction.openLichess,
            enabled: enabled,
            child: const Text('Open in Lichess'),
          ),
          if (onReportRecognition != null) ...[
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: _ExportAction.reportRecognition,
              child: Text('Report wrong recognition'),
            ),
          ],
        ];
      },
    );
  }
}
