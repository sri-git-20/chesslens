import 'point.dart';

/// Mixin providing normalized coordinate utilities for landmarks with x/y pixel coordinates.
mixin LandmarkMixin {
  double get x;
  double get y;

  /// Returns the x coordinate normalized to `0.0..1.0` relative to [imageWidth].
  double xNorm(int imageWidth) => (x / imageWidth).clamp(0.0, 1.0);

  /// Returns the y coordinate normalized to `0.0..1.0` relative to [imageHeight].
  double yNorm(int imageHeight) => (y / imageHeight).clamp(0.0, 1.0);

  /// Converts this landmark to a [Point] in pixel coordinates.
  Point toPixel(int imageWidth, int imageHeight) => Point(x, y);
}
