import 'dart:typed_data';

import 'geometry.dart';
import 'gray_image.dart';
import 'model_decode.dart';

/// Runs one model on a flat float32 input and returns the flat output.
typedef ModelFn = Float32List Function(Float32List input);

/// What the models say about one board.
class BoardProbs {
  const BoardProbs({required this.quad, required this.probs, this.score});

  /// Refined corners in original pixels.
  final Quad quad;

  /// 64 squares x 13 classes, row 0 = top of the board as drawn.
  final Float32List probs;

  /// Detector score, when the board came from the detector.
  final double? score;
}

/// The recognition steps of `docs/ARCHITECTURE.md`, independent of how the
/// three models are run.
class RecognitionPipeline {
  RecognitionPipeline({
    required this.detector,
    required this.corners,
    required this.squares,
  });

  final ModelFn detector;
  final ModelFn corners;
  final ModelFn squares;

  /// Finds every board on the page. Quads are coarse, in original pixels.
  List<Detection> detect(GrayImage gray, {double threshold = detectorThreshold}) {
    final (canvas, scale) = letterbox(gray);
    final out = detector(canvas.data);
    return decodeDetector(out, scale, threshold: threshold);
  }

  /// Refines a coarse quad with the corners model.
  Quad refine(GrayImage gray, Quad coarse) {
    final warp = warpRegion(gray, coarseSquare(coarse), cornersSize);
    final heat = corners(warp.image.data);
    final inverse = warp.homography.inverse();
    final points = decodeCorners(heat);
    if (inverse == null) return coarse;
    return Quad([for (final p in points) inverse.apply(p)]);
  }

  /// Reads the 64 squares inside [quad].
  Float32List readSquares(GrayImage gray, Quad quad) {
    final warp = warpRegion(gray, quad, squaresSize);
    return squares(warp.image.data);
  }

  /// Whole pipeline for one detection.
  BoardProbs readDetection(GrayImage gray, Detection detection) {
    final quad = refine(gray, detection.quad);
    return BoardProbs(
      quad: quad,
      probs: readSquares(gray, quad),
      score: detection.score,
    );
  }

  /// Reads a board whose corners the user has set.
  BoardProbs readQuad(GrayImage gray, Quad quad) =>
      BoardProbs(quad: quad, probs: readSquares(gray, quad));

  /// Reads a board inside a rectangle the user has drawn: the corners model
  /// finds the corners in it, then the squares model reads them.
  BoardProbs readRegion(GrayImage gray, Quad region) {
    final quad = refine(gray, region);
    return BoardProbs(quad: quad, probs: readSquares(gray, quad));
  }

  /// Every board on the page, in detector order.
  List<BoardProbs> readPage(GrayImage gray, {double threshold = detectorThreshold}) => [
        for (final d in detect(gray, threshold: threshold)) readDetection(gray, d),
      ];
}
