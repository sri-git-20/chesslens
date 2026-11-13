import 'dart:ui' show Canvas, Offset, Paint, Rect;

import '../bounding_box.dart';

/// Draw a standard "glow + point + center dot" triple-circle landmark marker
/// at ([x], [y]) in canvas coordinates.
///
/// Any of the three layers can be omitted by passing a `null` Paint. The
/// radii default to the conventional 8/5/2 used across the detector example
/// overlays; tweak for pixel-perfect parity with a custom design.
///
/// Callers typically pre-scale the landmark coordinate before calling, e.g.
/// ```dart
/// drawLandmarkMarker(
///   canvas,
///   landmark.x * scaleX + offsetX,
///   landmark.y * scaleY + offsetY,
///   glowPaint: _glow, pointPaint: _point, centerPaint: _dot,
/// );
/// ```
void drawLandmarkMarker(
  Canvas canvas,
  double x,
  double y, {
  double glowRadius = 8,
  double pointRadius = 5,
  double centerRadius = 2,
  Paint? glowPaint,
  Paint? pointPaint,
  Paint? centerPaint,
}) {
  final center = Offset(x, y);
  if (glowPaint != null) canvas.drawCircle(center, glowRadius, glowPaint);
  if (pointPaint != null) canvas.drawCircle(center, pointRadius, pointPaint);
  if (centerPaint != null) canvas.drawCircle(center, centerRadius, centerPaint);
}

/// Draw straight-line connections between pre-scaled landmark points.
///
/// [scaledPoints] should already have the detector-to-viewport transform
/// applied (`x * scaleX + offsetX`, `y * scaleY + offsetY`) so this helper
/// can skip the inner-loop math. [connections] is a list of index pairs
/// `(fromIdx, toIdx)` into that list, typically a constant bone topology
/// like a hand or pose skeleton.
///
/// Out-of-range indices are silently skipped so callers can share one
/// topology list across different landmark slices.
void drawSkeletonConnections({
  required Canvas canvas,
  required List<Offset> scaledPoints,
  required List<(int, int)> connections,
  required Paint paint,
}) {
  final int n = scaledPoints.length;
  for (final (from, to) in connections) {
    if (from < 0 || from >= n || to < 0 || to >= n) continue;
    canvas.drawLine(scaledPoints[from], scaledPoints[to], paint);
  }
}

/// Draw the axis-aligned outline of a [BoundingBox] transformed by a linear
/// scale + offset. Use a stroked [Paint] for an outline, or a filled one to
/// tint the interior.
void drawBoundingBoxOutline({
  required Canvas canvas,
  required BoundingBox bbox,
  required double scaleX,
  required double scaleY,
  required double offsetX,
  required double offsetY,
  required Paint paint,
}) {
  canvas.drawRect(
    Rect.fromLTRB(
      bbox.left * scaleX + offsetX,
      bbox.top * scaleY + offsetY,
      bbox.right * scaleX + offsetX,
      bbox.bottom * scaleY + offsetY,
    ),
    paint,
  );
}
