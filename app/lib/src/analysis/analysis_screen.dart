import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/game_board.dart';
import '../board/review_args.dart';
import '../board/review_screen.dart';
import '../chess/board_utils.dart';
import '../export/export_menu.dart';
import '../export/pgn.dart';
import '../engine/engine_providers.dart';
import '../navigation.dart';
import '../settings/settings_controller.dart';
import 'analysis_controller.dart';
import 'engine_lines.dart';
import 'eval_bar.dart';
import 'move_list.dart';

/// Analyze a position: move pieces on the board, see the engine's lines, and
/// walk back and forth through the moves played.
class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({
    super.key,
    required this.fen,
    this.orientation = Side.white,
    this.editArgs,
  });

  /// A legal full FEN. Review only opens this screen for legal positions.
  final String fen;
  final Side orientation;

  /// Set when the position comes straight from a scan: shows Edit position,
  /// which replaces this screen with Review for these arguments.
  final ReviewArgs? editArgs;

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen>
    with RouteAware, WidgetsBindingObserver {
  late final AnalysisController _controller;
  late Side _orientation;
  ModalRoute<void>? _route;
  bool _covered = false;
  bool _inBackground = false;
  final GlobalKey _boardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _orientation = widget.orientation;
    final start = chessFromFen(widget.fen) ?? Chess.initial;
    final settings = ref.read(settingsProvider);
    _controller = AnalysisController(
      start: start,
      engine: ref.read(engineServiceProvider),
      config: _configFrom(settings),
      // The board opens with the engine off; the switch at the top turns it on.
      engineOn: false,
    )..start();
    WidgetsBinding.instance.addObserver(this);
  }

  static AnalysisConfig _configFrom(AppSettings settings) => AnalysisConfig(
        multiPv: settings.multiPv,
        depthLimit: settings.depthLimit,
        timeLimitSeconds: settings.timeLimitSeconds,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null && route != _route) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  void _updateVisibility() => _controller.setVisible(!_covered && !_inBackground);

  @override
  void didPushNext() {
    _covered = true;
    _updateVisibility();
  }

  @override
  void didPopNext() {
    _covered = false;
    _updateVisibility();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inBackground = state != AppLifecycleState.resumed;
    _updateVisibility();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    _controller.dispose();
    super.dispose();
  }

  Set<Shape> _shapes() {
    if (!_controller.engineOn || _controller.lines.isEmpty) return const {};
    final move = _controller.lines.first.firstMove;
    final parsed = move == null ? null : Move.parse(move);
    if (parsed is! NormalMove || parsed.from == parsed.to) return const {};
    return {
      Arrow(
        color: const Color(0xCC1B8A3A),
        orig: parsed.from,
        dest: parsed.to,
        scale: 0.9,
      ),
    };
  }

  void _editPosition() {
    final args = widget.editArgs;
    if (args == null) return;
    Navigator.of(context).pushReplacement<void, void>(
      MaterialPageRoute(builder: (_) => ReviewScreen(args: args)),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSettings>(settingsProvider, (previous, next) {
      _controller.updateConfig(_configFrom(next));
    });
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final controller = _controller;
        final best = controller.lines.isEmpty ? null : controller.lines.first;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Analysis'),
            actions: [
              EngineSwitch(
                value: controller.engineOn,
                onChanged: controller.setEngineOn,
              ),
              ExportMenuButton(
                fen: () => controller.position.fen,
                pgn: () => pgnFromTree(controller.tree),
                boardKey: _boardKey,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (widget.editArgs != null)
                  _ScannedNote(
                    sideToMove: widget.editArgs!.sideToMove,
                    onEdit: _editPosition,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: EvalBar(
                    score: controller.engineOn ? best?.score : null,
                    turn: controller.position.turn,
                  ),
                ),
                GameBoard(
                  position: controller.position,
                  orientation: _orientation,
                  lastMove: controller.lastMove,
                  shapes: _shapes(),
                  maxHeightFraction: 0.45,
                  onMove: controller.makeMove,
                  boundaryKey: _boardKey,
                ),
                _NavigationBar(
                  controller: controller,
                  onFlip: () => setState(() => _orientation = _orientation.opposite),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      if (controller.engineOn)
                        EngineLines(controller: controller, onRetry: controller.retry)
                      else
                        const _EngineOffHint(),
                      const Divider(height: 24),
                      MoveList(tree: controller.tree, onSelect: controller.goTo),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NavigationBar extends StatelessWidget {
  const _NavigationBar({required this.controller, required this.onFlip});

  final AnalysisController controller;
  final VoidCallback onFlip;

  @override
  Widget build(BuildContext context) {
    final tree = controller.tree;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Start',
          icon: const Icon(Icons.first_page),
          onPressed: tree.canGoBack ? controller.goToStart : null,
        ),
        IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.chevron_left),
          onPressed: tree.canGoBack ? controller.back : null,
        ),
        IconButton(
          tooltip: 'Forward',
          icon: const Icon(Icons.chevron_right),
          onPressed: tree.canGoForward ? controller.forward : null,
        ),
        IconButton(
          tooltip: 'End',
          icon: const Icon(Icons.last_page),
          onPressed: tree.canGoForward ? controller.goToEnd : null,
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Flip board',
          icon: const Icon(Icons.swap_vert),
          onPressed: onFlip,
        ),
      ],
    );
  }
}

/// One line above the board when the position was read from a photo.
class _ScannedNote extends StatelessWidget {
  const _ScannedNote({required this.sideToMove, required this.onEdit});

  final Side sideToMove;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(
        children: [
          Icon(
            Icons.photo_camera_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Read from your photo. '
              '${sideToMove == Side.white ? 'White' : 'Black'} to move.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(onPressed: onEdit, child: const Text('Edit position')),
        ],
      ),
    );
  }
}

/// Engine on/off switch for the app bar, styled like a video autoplay toggle:
/// a short label and a switch whose knob shows play (on) or pause (off).
class EngineSwitch extends StatelessWidget {
  const EngineSwitch({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Engine',
      toggled: value,
      child: Tooltip(
        message: value ? 'Engine on. Tap to turn off.' : 'Engine off. Tap to turn on.',
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Text(
                    'Engine',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: value
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                ExcludeSemantics(
                  child: Switch(
                    value: value,
                    onChanged: onChanged,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    thumbIcon: WidgetStateProperty.resolveWith<Icon?>(
                      (states) => states.contains(WidgetState.selected)
                          ? const Icon(Icons.play_arrow_rounded)
                          : const Icon(Icons.pause_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown in place of the engine lines while the engine is off.
class _EngineOffHint extends StatelessWidget {
  const _EngineOffHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.pause_circle_outline, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Engine is off. Turn on Engine at the top to see the best moves.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
