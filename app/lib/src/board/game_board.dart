import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'board_providers.dart';
import 'board_size.dart';

/// An interactive board for a dartchess [Position], themed from settings.
///
/// The widget does not own the position: when the user moves, [onMove] is
/// called and the parent decides what to do (usually: play the move and pass
/// the new position back in).
class GameBoard extends ConsumerStatefulWidget {
  const GameBoard({
    super.key,
    required this.position,
    required this.orientation,
    this.playerSide = PlayerSide.both,
    this.lastMove,
    this.shapes = const {},
    this.onMove,
    this.maxHeightFraction = 0.55,
  });

  final Position position;
  final Side orientation;
  final PlayerSide playerSide;
  final Move? lastMove;
  final Set<Shape> shapes;
  final void Function(NormalMove move)? onMove;
  final double maxHeightFraction;

  @override
  ConsumerState<GameBoard> createState() => _GameBoardState();
}

class _GameBoardState extends ConsumerState<GameBoard> {
  late final ChessboardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ChessboardController(game: _gameData(widget));
  }

  static GameData _gameData(GameBoard widget) {
    final position = widget.position;
    return GameData(
      fen: position.fen,
      lastMove: widget.lastMove,
      playerSide: widget.playerSide,
      sideToMove: position.turn,
      validMoves: makeLegalMoves(position),
      kingSquareInCheck: position.isCheck ? position.board.kingOf(position.turn) : null,
    );
  }

  @override
  void didUpdateWidget(GameBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final positionChanged = oldWidget.position.fen != widget.position.fen;
    final changed = positionChanged ||
        oldWidget.lastMove != widget.lastMove ||
        oldWidget.playerSide != widget.playerSide;
    if (changed) {
      _controller.updatePosition(_gameData(widget), animate: positionChanged);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(chessboardSettingsProvider);
    return BoardSize(
      maxHeightFraction: widget.maxHeightFraction,
      builder: (context, size) => Chessboard(
        size: size,
        controller: _controller,
        orientation: widget.orientation,
        settings: settings,
        shapes: widget.shapes,
        onMove: (move, {bool? viaDragAndDrop}) {
          if (move is NormalMove) widget.onMove?.call(move);
        },
      ),
    );
  }
}
