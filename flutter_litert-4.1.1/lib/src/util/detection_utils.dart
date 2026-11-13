/// Transforms bounding box coordinates from letterbox space back to original image space.
///
/// Reverses the letterbox transformation by removing padding and unscaling coordinates.
///
/// Parameters:
/// - [xyxy]: Bounding box in letterbox space as `[x1, y1, x2, y2]`
/// - [ratio]: Scale ratio from letterbox preprocessing
/// - [dw]: Horizontal padding from letterbox preprocessing
/// - [dh]: Vertical padding from letterbox preprocessing
///
/// Returns the bounding box in original image space as `[x1, y1, x2, y2]`.
List<double> scaleFromLetterbox(
  List<double> xyxy,
  double ratio,
  int dw,
  int dh,
) {
  final double x1 = (xyxy[0] - dw) / ratio;
  final double y1 = (xyxy[1] - dh) / ratio;
  final double x2 = (xyxy[2] - dw) / ratio;
  final double y2 = (xyxy[3] - dh) / ratio;
  return [x1, y1, x2, y2];
}
