import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/game_board.dart';
import '../chess/board_utils.dart';
import '../collections/collection_providers.dart';
import '../engine/engine_providers.dart';
import 'solve_controller.dart';

/// Solve a puzzle: you play the side to move, the engine checks each move.
class SolveScreen extends ConsumerStatefulWidget {
  const SolveScreen({
    super.key,
    required this.fen,
    this.orientation = Side.white,
    this.puzzleId,
  });

  /// A legal full FEN.
  final String fen;
  final Side orientation;

  /// Set when the puzzle comes from a collection: the result is stored.
  final int? puzzleId;

  @override
  ConsumerState<SolveScreen> createState() => _SolveScreenState();
}

class _SolveScreenState extends ConsumerState<SolveScreen> {
  late final SolveController _controller;
  late Side _orientation;

  @override
  void initState() {
    super.initState();
    _orientation = widget.orientation;
    _controller = SolveController(
      start: chessFromFen(widget.fen) ?? Chess.initial,
      engine: ref.read(engineServiceProvider),
      puzzleId: widget.puzzleId,
      repository: widget.puzzleId == null ? null : ref.read(collectionRepositoryProvider),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    await _controller.recordSession();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _done();
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final controller = _controller;
          final hint = controller.hintSquare;
          return Scaffold(
            appBar: AppBar(
              title: const Text('Solve'),
              actions: [
                IconButton(
                  tooltip: 'Flip board',
                  icon: const Icon(Icons.swap_vert),
                  onPressed: () => setState(() => _orientation = _orientation.opposite),
                ),
                TextButton(onPressed: _done, child: const Text('Done')),
              ],
            ),
            body: SafeArea(
              child: Column(
                children: [
                  GameBoard(
                    position: controller.position,
                    orientation: _orientation,
                    playerSide: controller.canMove
                        ? (controller.solver == Side.white ? PlayerSide.white : PlayerSide.black)
                        : PlayerSide.none,
                    lastMove: controller.lastMove,
                    shapes: {
                      if (hint != null)
                        Circle(color: const Color(0xCC1B8A3A), orig: hint, scale: 1),
                    },
                    maxHeightFraction: 0.5,
                    onMove: controller.userMove,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _StatusPanel(controller: controller),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.controller});

  final SolveController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final side = controller.solver == Side.white ? 'White' : 'Black';

    Widget busy(String text) => Row(
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: theme.textTheme.titleMedium)),
          ],
        );

    switch (controller.phase) {
      case SolvePhase.yourMove:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your move. Find the best move for $side.',
                style: theme.textTheme.titleMedium),
            if (controller.error != null) ...[
              const SizedBox(height: 8),
              Text(controller.error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.lightbulb_outline),
              label: const Text('Hint'),
              onPressed: controller.showHint,
            ),
          ],
        );
      case SolvePhase.judging:
        return busy('Checking your move...');
      case SolvePhase.opponent:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Good move.', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            busy('The opponent is replying...'),
          ],
        );
      case SolvePhase.wrong:
        return Card(
          elevation: 0,
          color: scheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.error ?? 'Not the best move',
                  style: theme.textTheme.titleMedium?.copyWith(color: scheme.onErrorContainer),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: controller.tryAgain,
                      child: const Text('Try again'),
                    ),
                    OutlinedButton(
                      onPressed: controller.showSolution,
                      child: const Text('Show solution'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      case SolvePhase.solution:
        return busy('Showing the solution...');
      case SolvePhase.finished:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  controller.usedSolution ? Icons.info_outline : Icons.check_circle_outline,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    controller.resultText ?? 'Finished.',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 8),
              Text(controller.error!, style: TextStyle(color: scheme.error)),
            ],
          ],
        );
    }
  }
}
