import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';

import 'move_tree.dart';

/// The moves played so far as text you can tap: the mainline, with variations
/// in parentheses.
class MoveList extends StatelessWidget {
  const MoveList({super.key, required this.tree, required this.onSelect});

  final MoveTree tree;
  final ValueChanged<MoveNode> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (tree.root.children.isEmpty) {
      return Text(
        'Make a move on the board to start a line.',
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    final items = <Widget>[];
    _emitLine(context, tree.root, false, items, 0);
    return Wrap(spacing: 2, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: items);
  }

  void _emitLine(
    BuildContext context,
    MoveNode from,
    bool forceNumber,
    List<Widget> out,
    int level,
  ) {
    var node = from;
    var force = forceNumber;
    while (node.children.isNotEmpty) {
      final main = node.children.first;
      _emitMove(context, main, force, out, level);
      for (final variation in node.children.skip(1)) {
        out.add(_Muted('('));
        _emitMove(context, variation, true, out, level + 1);
        _emitLine(context, variation, false, out, level + 1);
        out.add(_Muted(')'));
      }
      force = node.children.length > 1;
      node = main;
    }
  }

  void _emitMove(BuildContext context, MoveNode node, bool forceNumber, List<Widget> out, int level) {
    final parent = node.parent!;
    final whiteMoved = parent.position.turn == Side.white;
    final number = parent.position.fullmoves;
    if (whiteMoved) {
      out.add(_Muted('$number.'));
    } else if (forceNumber) {
      out.add(_Muted('$number...'));
    }
    out.add(_MoveChip(
      label: node.san ?? '',
      selected: identical(node, tree.current),
      muted: level > 0,
      onTap: () => onSelect(node),
    ));
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

class _MoveChip extends StatelessWidget {
  const _MoveChip({
    required this.label,
    required this.selected,
    required this.muted,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? scheme.onPrimaryContainer
                : (muted ? scheme.onSurfaceVariant : scheme.onSurface),
          ),
        ),
      ),
    );
  }
}
