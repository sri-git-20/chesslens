import 'dart:math' as math;

/// SSD anchor configuration options for SSD-style detection models.
///
/// Mirrors the Python SSDAnchorOptions namedtuple. Used internally for
/// generating anchor boxes in SSD-style TFLite detection models.
class SSDAnchorOptions {
  /// Number of feature map layers (typically 4 for detection models).
  final int numLayers;

  /// Minimum anchor scale (0.0-1.0).
  final double minScale;

  /// Maximum anchor scale (0.0-1.0).
  final double maxScale;

  /// Input image height in pixels.
  final int inputSizeHeight;

  /// Input image width in pixels.
  final int inputSizeWidth;

  /// X offset for anchor centers (typically 0.5).
  final double anchorOffsetX;

  /// Y offset for anchor centers (typically 0.5).
  final double anchorOffsetY;

  /// Feature map strides for each layer.
  final List<int> strides;

  /// Aspect ratios for anchor boxes.
  final List<double> aspectRatios;

  /// Whether to reduce boxes in the lowest layer.
  final bool reduceBoxesInLowestLayer;

  /// Interpolated scale aspect ratio (0 to disable).
  final double interpolatedScaleAspectRatio;

  /// Whether to use fixed anchor size (1x1).
  final bool fixedAnchorSize;

  /// Creates SSD anchor options.
  const SSDAnchorOptions({
    required this.numLayers,
    required this.minScale,
    required this.maxScale,
    required this.inputSizeHeight,
    required this.inputSizeWidth,
    required this.anchorOffsetX,
    required this.anchorOffsetY,
    required this.strides,
    required this.aspectRatios,
    required this.reduceBoxesInLowestLayer,
    required this.interpolatedScaleAspectRatio,
    required this.fixedAnchorSize,
  });
}

double _calculateScale(
  double minScale,
  double maxScale,
  int strideIndex,
  int numStrides,
) {
  if (numStrides == 1) {
    return (minScale + maxScale) / 2;
  } else {
    return minScale + (maxScale - minScale) * strideIndex / (numStrides - 1);
  }
}

/// Generates SSD anchors based on the given options.
///
/// Returns a list of anchors where each anchor is `[xCenter, yCenter, width, height]`
/// in normalized coordinates. For fixed-size anchors ([SSDAnchorOptions.fixedAnchorSize]
/// is true), width and height are always 1.0.
///
/// This is a direct port of the Python generate_anchors function.
List<List<double>> generateAnchors(SSDAnchorOptions options) {
  final anchors = <List<double>>[];
  int layerId = 0;
  final nStrides = options.strides.length;

  while (layerId < nStrides) {
    final anchorHeight = <double>[];
    final anchorWidth = <double>[];
    final aspectRatios = <double>[];
    final scales = <double>[];
    int lastSameStrideLayer = layerId;

    while (lastSameStrideLayer < nStrides &&
        options.strides[lastSameStrideLayer] == options.strides[layerId]) {
      final scale = _calculateScale(
        options.minScale,
        options.maxScale,
        lastSameStrideLayer,
        nStrides,
      );

      if (lastSameStrideLayer == 0 && options.reduceBoxesInLowestLayer) {
        aspectRatios.addAll([1.0, 2.0, 0.5]);
        scales.addAll([0.1, scale, scale]);
      } else {
        aspectRatios.addAll(options.aspectRatios);
        for (int i = 0; i < options.aspectRatios.length; i++) {
          scales.add(scale);
        }
        if (options.interpolatedScaleAspectRatio > 0) {
          double scaleNext;
          if (lastSameStrideLayer == nStrides - 1) {
            scaleNext = 1.0;
          } else {
            scaleNext = _calculateScale(
              options.minScale,
              options.maxScale,
              lastSameStrideLayer + 1,
              nStrides,
            );
          }
          scales.add(math.sqrt(scale * scaleNext));
          aspectRatios.add(options.interpolatedScaleAspectRatio);
        }
      }
      lastSameStrideLayer++;
    }

    for (int i = 0; i < aspectRatios.length; i++) {
      final ratioSqrt = math.sqrt(aspectRatios[i]);
      anchorHeight.add(scales[i] / ratioSqrt);
      anchorWidth.add(scales[i] * ratioSqrt);
    }

    final stride = options.strides[layerId];
    final featureMapHeight = (options.inputSizeHeight / stride).ceil();
    final featureMapWidth = (options.inputSizeWidth / stride).ceil();

    for (int y = 0; y < featureMapHeight; y++) {
      for (int x = 0; x < featureMapWidth; x++) {
        for (int anchorId = 0; anchorId < anchorHeight.length; anchorId++) {
          final xCenter = (x + options.anchorOffsetX) / featureMapWidth;
          final yCenter = (y + options.anchorOffsetY) / featureMapHeight;

          List<double> newAnchor;
          if (options.fixedAnchorSize) {
            newAnchor = [xCenter, yCenter, 1.0, 1.0];
          } else {
            newAnchor = [
              xCenter,
              yCenter,
              anchorWidth[anchorId],
              anchorHeight[anchorId],
            ];
          }
          anchors.add(newAnchor);
        }
      }
    }

    layerId = lastSameStrideLayer;
  }

  return anchors;
}
