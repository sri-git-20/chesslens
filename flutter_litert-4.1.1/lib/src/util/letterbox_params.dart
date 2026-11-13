import 'dart:math' as math;

/// Parameters for aspect-preserving resize with centered padding.
///
/// Returned by [computeLetterboxParams].
class LetterboxParams {
  /// Scale factor applied to the source image.
  final double scale;

  /// Width of the scaled image before padding.
  final int newWidth;

  /// Height of the scaled image before padding.
  final int newHeight;

  /// Left padding in pixels.
  final int padLeft;

  /// Top padding in pixels.
  final int padTop;

  /// Right padding in pixels.
  final int padRight;

  /// Bottom padding in pixels.
  final int padBottom;

  const LetterboxParams({
    required this.scale,
    required this.newWidth,
    required this.newHeight,
    required this.padLeft,
    required this.padTop,
    required this.padRight,
    required this.padBottom,
  });
}

/// Computes letterbox parameters for resizing [srcWidth]x[srcHeight] to fit
/// within [targetWidth]x[targetHeight] while preserving aspect ratio.
///
/// The scale factor is `min(targetWidth/srcWidth, targetHeight/srcHeight)`.
/// The image is resized to `newWidth` x `newHeight` and then padded symmetrically
/// to exactly [targetWidth]x[targetHeight]. Any remainder pixel goes to the
/// right/bottom pad.
///
/// Set [roundDimensions] to `false` to truncate (`.toInt()`) instead of
/// rounding the scaled dimensions. Defaults to `true` (`.round()`).
LetterboxParams computeLetterboxParams({
  required int srcWidth,
  required int srcHeight,
  required int targetWidth,
  required int targetHeight,
  bool roundDimensions = true,
}) {
  final double scale = math.min(
    targetWidth / srcWidth,
    targetHeight / srcHeight,
  );
  final int newWidth = roundDimensions
      ? (srcWidth * scale).round()
      : (srcWidth * scale).toInt();
  final int newHeight = roundDimensions
      ? (srcHeight * scale).round()
      : (srcHeight * scale).toInt();
  final (padLeft, padRight) = _centeredPad(targetWidth, newWidth);
  final (padTop, padBottom) = _centeredPad(targetHeight, newHeight);

  return LetterboxParams(
    scale: scale,
    newWidth: newWidth,
    newHeight: newHeight,
    padLeft: padLeft,
    padTop: padTop,
    padRight: padRight,
    padBottom: padBottom,
  );
}

(int, int) _centeredPad(int total, int used) {
  final int before = (total - used) ~/ 2;
  return (before, total - used - before);
}
