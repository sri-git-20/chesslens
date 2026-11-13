import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Gives [builder] the side of the biggest square board that fits: the full
/// width, but never taller than [maxHeightFraction] of the screen (so the
/// controls under the board stay visible, also in landscape).
class BoardSize extends StatelessWidget {
  const BoardSize({super.key, required this.builder, this.maxHeightFraction = 0.55});

  final Widget Function(BuildContext context, double size) builder;
  final double maxHeightFraction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenHeight = MediaQuery.sizeOf(context).height;
        var size = math.min(constraints.maxWidth, screenHeight * maxHeightFraction);
        if (constraints.hasBoundedHeight) size = math.min(size, constraints.maxHeight);
        if (!size.isFinite || size <= 0) size = 300;
        return Center(child: builder(context, size));
      },
    );
  }
}
