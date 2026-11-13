import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../chess/san.dart';
import '../engine/engine_service.dart';
import '../engine/uci.dart';
import 'analysis_controller.dart';

/// The engine's lines for the current position: score, moves in SAN, depth.
class EngineLines extends StatelessWidget {
  const EngineLines({super.key, required this.controller, this.onRetry});

  final AnalysisController controller;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final position = controller.position;
    final lines = controller.lines;

    Widget status(String text, {Color? color, Widget? trailing}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color ?? theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        );

    if (controller.idle == AnalysisIdle.failed) {
      return status(
        controller.error ?? 'The engine stopped.',
        color: theme.colorScheme.error,
        trailing: onRetry == null
            ? null
            : TextButton(onPressed: onRetry, child: const Text('Try again')),
      );
    }
    if (controller.idle == AnalysisIdle.off) return status('Engine off.');
    if (controller.idle == AnalysisIdle.hidden) return status('Engine paused.');
    if (controller.idle == AnalysisIdle.gameOver) {
      return status(_gameOverText(position));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Text(
                controller.depth > 0 ? 'Depth ${controller.depth}' : 'Starting the engine',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              if (controller.isSearching)
                const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  'Finished',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              const Spacer(),
              if (!controller.isSearching && controller.idle == AnalysisIdle.limitReached)
                TextButton(onPressed: onRetry, child: const Text('Continue')),
            ],
          ),
        ),
        for (final line in lines) _LineRow(line: line, position: position),
      ],
    );
  }
}

String _gameOverText(Position position) {
  if (position.isCheckmate) {
    final winner = position.turn.opposite == Side.white ? 'White' : 'Black';
    return 'Checkmate. $winner wins.';
  }
  if (position.isStalemate) return 'Stalemate. The game is a draw.';
  return 'Draw by insufficient material.';
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.position});

  final EngineLine line;
  final Position position;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final whiteScore = position.turn == Side.white ? line.score : line.score.negated;
    final whiteAhead = whiteScore.orderingCp >= 0;
    final moves = pvToSan(position, line.pv, maxPlies: 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 58,
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: whiteAhead ? const Color(0xFFF2F2F2) : const Color(0xFF2B2B2B),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Text(
              formatScore(line.score, position.turn),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: whiteAhead ? const Color(0xFF2B2B2B) : const Color(0xFFF2F2F2),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              moves,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'd${line.depth}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
