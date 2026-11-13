import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../engine/uci.dart';

/// A horizontal evaluation bar from White's point of view: white on the left,
/// black on the right, with the score as text (`+0.35`, `M3`).
class EvalBar extends StatelessWidget {
  const EvalBar({super.key, required this.score, required this.turn});

  /// Score for the side to move, or `null` when there is no evaluation yet.
  final UciScore? score;
  final Side turn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = score == null ? 50.0 : whiteWinPercent(score!, turn);
    final label = score == null ? '' : formatScore(score!, turn);
    final whiteIsAhead = percent >= 50;
    const white = Color(0xFFF2F2F2);
    const black = Color(0xFF2B2B2B);

    return Semantics(
      label: label.isEmpty ? 'No evaluation yet' : 'Evaluation $label',
      child: Container(
        height: 24,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: scheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: black),
            Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: percent / 100,
                heightFactor: 1,
                child: const ColoredBox(color: white),
              ),
            ),
            Align(
              alignment: whiteIsAhead ? Alignment.centerLeft : Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: whiteIsAhead ? black : white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
