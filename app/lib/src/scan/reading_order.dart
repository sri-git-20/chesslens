import 'dart:math' as math;

import 'geometry.dart';

/// Reading order of boards on a page: boards that overlap horizontally form a
/// column; columns go left to right and boards top to bottom inside a column.
///
/// Returns indices into [quads].
List<int> readingOrder(List<Quad> quads) {
  final byLeft = List<int>.generate(quads.length, (i) => i)
    ..sort((a, b) => quads[a].minX.compareTo(quads[b].minX));

  final columns = <_Column>[];
  for (final i in byLeft) {
    final q = quads[i];
    _Column? best;
    var bestOverlap = 0.0;
    for (final column in columns) {
      final overlap = math.min(column.maxX, q.maxX) - math.max(column.minX, q.minX);
      final needed = 0.5 * math.min(column.maxX - column.minX, q.width);
      if (overlap > 0 && overlap >= needed && overlap > bestOverlap) {
        best = column;
        bestOverlap = overlap;
      }
    }
    if (best == null) {
      columns.add(_Column(q.minX, q.maxX)..members.add(i));
    } else {
      best.members.add(i);
      best.minX = math.min(best.minX, q.minX);
      best.maxX = math.max(best.maxX, q.maxX);
    }
  }

  columns.sort((a, b) => a.minX.compareTo(b.minX));
  return [
    for (final column in columns)
      ...(column.members..sort((a, b) => quads[a].center.y.compareTo(quads[b].center.y))),
  ];
}

class _Column {
  _Column(this.minX, this.maxX);
  double minX;
  double maxX;
  final List<int> members = [];
}
