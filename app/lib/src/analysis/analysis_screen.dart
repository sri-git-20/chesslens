import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/game_board.dart';
import '../chess/board_utils.dart';
import '../engine/engine_providers.dart';
import '../engine/engine_service.dart';
import '../navigation.dart';
import '../settings/settings_controller.dart';
import 'analysis_controller.dart';
import 'engine_lines.dart';
import 'eval_bar.dart';
import 'move_list.dart';

/// Analyze a position: move pieces on the board, see the engine's lines, and
/// walk back and forth through the moves played.
class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key, required this.fen, this.orientation = Side.white});

  /// A legal full FEN. Review only opens this screen for legal positions.
  final String fen;
  final Side orientation;

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
              IconButton(
                tooltip: controller.engineOn ? 'Turn engine off' : 'Turn engine on',
                isSelected: controller.engineOn,
                icon: const Icon(Icons.memory_outlined),
                selectedIcon: const Icon(Icons.memory),
                onPressed: () => controller.setEngineOn(!controller.engineOn),
              ),
              IconButton(
                tooltip: 'Flip board',
                icon: const Icon(Icons.swap_vert),
                onPressed: () => setState(() => _orientation = _orientation.opposite),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
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
                ),
                _NavigationBar(controller: controller),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      EngineLines(controller: controller, onRetry: controller.retry),
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
  const _NavigationBar({required this.controller});

  final AnalysisController controller;

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
      ],
    );
  }
}
