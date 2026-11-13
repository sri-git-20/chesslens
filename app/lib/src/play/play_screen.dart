import 'dart:math';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/game_board.dart';
import '../chess/board_utils.dart';
import '../chess/san.dart';
import '../engine/engine_providers.dart';
import '../engine/engine_service.dart';
import '../engine/play_levels.dart';
import 'play_controller.dart';

enum _ColorChoice { white, black, random }

/// Play the position against the engine.
class PlayScreen extends ConsumerStatefulWidget {
  const PlayScreen({super.key, required this.fen, this.orientation = Side.white});

  /// A legal full FEN.
  final String fen;
  final Side orientation;

  @override
  ConsumerState<PlayScreen> createState() => _PlayScreenState();
}

class _PlayScreenState extends ConsumerState<PlayScreen> {
  late final PlayController _controller;
  _ColorChoice _color = _ColorChoice.white;
  PlayLevel _level = PlayLevel.levels[4];
  EloRange _range = EloRange.fallback;
  Side? _boardSide;

  @override
  void initState() {
    super.initState();
    _color = widget.orientation == Side.white ? _ColorChoice.white : _ColorChoice.black;
    _controller = PlayController(
      start: chessFromFen(widget.fen) ?? Chess.initial,
      engine: ref.read(engineServiceProvider),
    );
    _controller.loadEloRange().then((range) {
      if (mounted) setState(() => _range = range);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final side = switch (_color) {
      _ColorChoice.white => Side.white,
      _ColorChoice.black => Side.black,
      _ColorChoice.random => Random().nextBool() ? Side.white : Side.black,
    };
    setState(() => _boardSide = side);
    await _controller.startGame(userSide: side, level: _level);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Play'),
            actions: [
              if (_controller.started)
                IconButton(
                  tooltip: 'New game',
                  icon: const Icon(Icons.restart_alt),
                  onPressed: _controller.newGame,
                ),
            ],
          ),
          body: SafeArea(
            child: _controller.started
                ? _GameView(controller: _controller, orientation: _boardSide ?? _controller.userSide)
                : _SetupView(
                    color: _color,
                    level: _level,
                    range: _range,
                    onColor: (value) => setState(() => _color = value),
                    onLevel: (value) => setState(() => _level = value),
                    onStart: _start,
                  ),
          ),
        );
      },
    );
  }
}

class _SetupView extends StatelessWidget {
  const _SetupView({
    required this.color,
    required this.level,
    required this.range,
    required this.onColor,
    required this.onLevel,
    required this.onStart,
  });

  final _ColorChoice color;
  final PlayLevel level;
  final EloRange range;
  final ValueChanged<_ColorChoice> onColor;
  final ValueChanged<PlayLevel> onLevel;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final levels = [...PlayLevel.levels, PlayLevel.fullStrength];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('You play', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SegmentedButton<_ColorChoice>(
          segments: const [
            ButtonSegment(value: _ColorChoice.white, label: Text('White')),
            ButtonSegment(value: _ColorChoice.black, label: Text('Black')),
            ButtonSegment(value: _ColorChoice.random, label: Text('Random')),
          ],
          selected: {color},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onColor(selection.first),
        ),
        const SizedBox(height: 24),
        Text('Engine strength', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final item in levels)
              ChoiceChip(
                label: Text(item.label),
                selected: item == level,
                onSelected: (_) => onLevel(item),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '${level.label}: ${level.describe(range)}. The engine thinks for '
          '${(level.thinkTimeMs / 1000).toStringAsFixed(level.thinkTimeMs % 1000 == 0 ? 0 : 1)} '
          's per move.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start game'),
          onPressed: onStart,
        ),
      ],
    );
  }
}

class _GameView extends StatelessWidget {
  const _GameView({required this.controller, required this.orientation});

  final PlayController controller;
  final Side orientation;

  Set<Shape> _shapes() {
    final hint = controller.hint;
    if (hint == null || hint.from == hint.to) return const {};
    return {
      Arrow(
        color: const Color(0xCC1B8A3A),
        orig: hint.from,
        dest: hint.to,
        scale: 0.9,
      ),
    };
  }

  String _status() {
    if (controller.resultText != null) return controller.resultText!;
    if (controller.error != null) return controller.error!;
    if (controller.isThinking) return 'The engine is thinking...';
    if (controller.isHintLoading) return 'Looking for a hint...';
    final check = controller.position.isCheck ? ' Check.' : '';
    return 'Your move.$check';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ended = controller.end != null;
    final failed = controller.error != null && controller.end == null;
    final movesText = pvToSan(
      controller.startPosition,
      controller.moves.map((move) => move.uci),
      maxPlies: 400,
    );
    return Column(
      children: [
        GameBoard(
          position: controller.position,
          orientation: orientation,
          playerSide: ended
              ? PlayerSide.none
              : (controller.userSide == Side.white ? PlayerSide.white : PlayerSide.black),
          lastMove: controller.lastMove,
          shapes: _shapes(),
          maxHeightFraction: 0.5,
          onMove: controller.userMove,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              if (controller.isThinking || controller.isHintLoading)
                const Padding(
                  padding: EdgeInsets.only(right: 10),
                  child: SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              Expanded(
                child: Text(
                  _status(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: failed ? theme.colorScheme.error : null,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('Takeback'),
                onPressed: controller.canTakeback ? controller.takeback : null,
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.lightbulb_outline),
                label: const Text('Hint'),
                onPressed: controller.isUserTurn && !controller.isThinking && !controller.isHintLoading
                    ? controller.showHint
                    : null,
              ),
              if (failed && controller.position.turn != controller.userSide)
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                  onPressed: controller.retryEngineMove,
                ),
              if (!ended)
                OutlinedButton.icon(
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Resign'),
                  onPressed: controller.resign,
                )
              else
                FilledButton.icon(
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('New game'),
                  onPressed: controller.newGame,
                ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                movesText.isEmpty ? 'No moves yet.' : movesText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
