import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

/// What a tap on the editor board does.
sealed class EditorTool {
  const EditorTool();
}

/// Pieces on the board can be dragged around (and off the board).
class MoveTool extends EditorTool {
  const MoveTool();
}

/// A tap puts [piece] on the square.
class PlaceTool extends EditorTool {
  const PlaceTool(this.piece);
  final Piece piece;

  @override
  bool operator ==(Object other) =>
      other is PlaceTool && other.piece.color == piece.color && other.piece.role == piece.role;

  @override
  int get hashCode => Object.hash(piece.color, piece.role);
}

/// A tap clears the square.
class EraseTool extends EditorTool {
  const EraseTool();
}

const List<Role> _paletteRoles = [
  Role.king,
  Role.queen,
  Role.rook,
  Role.bishop,
  Role.knight,
  Role.pawn,
];

/// The piece palette under the board: a row of white pieces with the move
/// tool, a row of black pieces with the eraser. Pieces can be tapped (to
/// stamp them on squares) or dragged onto the board.
class PiecePalette extends StatelessWidget {
  const PiecePalette({
    super.key,
    required this.tool,
    required this.onToolChanged,
    required this.pieceAssets,
  });

  final EditorTool tool;
  final ValueChanged<EditorTool> onToolChanged;
  final PieceAssets pieceAssets;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Six pieces and one tool button per row, each with 2 px of padding.
        final fit = (constraints.maxWidth - 7 * 2) / 7;
        final cell = fit > 52 ? 52.0 : (fit < 30 ? 30.0 : fit);
        return _buildRows(context, cell);
      },
    );
  }

  Widget _buildRows(BuildContext context, double cell) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _row(context, Side.white, cell,
            trailing: _ToolButton(
              tooltip: 'Move pieces',
              icon: Icons.open_with,
              selected: tool is MoveTool,
              size: cell,
              onTap: () => onToolChanged(const MoveTool()),
            )),
        const SizedBox(height: 6),
        _row(context, Side.black, cell,
            trailing: _ToolButton(
              tooltip: 'Eraser',
              icon: Icons.backspace_outlined,
              selected: tool is EraseTool,
              size: cell,
              onTap: () => onToolChanged(const EraseTool()),
            )),
      ],
    );
  }

  Widget _row(BuildContext context, Side side, double cell, {required Widget trailing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final role in _paletteRoles)
          _PaletteSlot(
            piece: Piece(color: side, role: role),
            selected: tool == PlaceTool(Piece(color: side, role: role)),
            size: cell,
            pieceAssets: pieceAssets,
            onTap: () {
              final piece = Piece(color: side, role: role);
              // Tapping the selected piece again goes back to moving pieces.
              onToolChanged(tool == PlaceTool(piece) ? const MoveTool() : PlaceTool(piece));
            },
          ),
        trailing,
      ],
    );
  }
}

class _PaletteSlot extends StatelessWidget {
  const _PaletteSlot({
    required this.piece,
    required this.selected,
    required this.size,
    required this.pieceAssets,
    required this.onTap,
  });

  final Piece piece;
  final bool selected;
  final double size;
  final PieceAssets pieceAssets;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Draggable<Piece>(
            data: piece,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: PieceDragFeedback(
              piece: piece,
              squareSize: size,
              pieceAssets: pieceAssets,
            ),
            child: PieceWidget(piece: piece, size: size, pieceAssets: pieceAssets),
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.size,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(1),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: SizedBox.square(
              dimension: size,
              child: Icon(
                icon,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
