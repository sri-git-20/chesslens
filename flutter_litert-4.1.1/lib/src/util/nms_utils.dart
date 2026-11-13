import 'dart:math' as math;

import 'math_utils.dart';

/// Non-Maximum Suppression over XYXY-format bounding boxes.
///
/// Returns the indices of kept detections, sorted by descending score and
/// capped at [maxDet] results. Boxes whose IoU with an already-kept box
/// exceeds [iouThres] are suppressed.
///
/// Parameters:
/// - [boxes]: List of bounding boxes in `[x1, y1, x2, y2]` format.
/// - [scores]: Confidence score for each box.
/// - [iouThres]: IoU threshold above which a box is suppressed (default 0.45).
/// - [maxDet]: Maximum number of detections to return (default 100).
List<int> nms(
  List<List<double>> boxes,
  List<double> scores, {
  double iouThres = 0.45,
  int maxDet = 100,
}) {
  if (boxes.isEmpty) return <int>[];

  final List<int> order = argSortDesc(scores);
  final List<int> keep = <int>[];

  double area(List<double> b) =>
      math.max(0.0, b[2] - b[0]) * math.max(0.0, b[3] - b[1]);

  final List<double> areas = boxes.map(area).toList();
  final List<bool> suppressed = List<bool>.filled(order.length, false);

  for (int m = 0; m < order.length; m++) {
    if (suppressed[m]) continue;
    final int i = order[m];
    keep.add(i);
    if (keep.length >= maxDet) break;
    for (int n = m + 1; n < order.length; n++) {
      if (suppressed[n]) continue;
      final int j = order[n];
      final double xx1 = math.max(boxes[i][0], boxes[j][0]);
      final double yy1 = math.max(boxes[i][1], boxes[j][1]);
      final double xx2 = math.min(boxes[i][2], boxes[j][2]);
      final double yy2 = math.min(boxes[i][3], boxes[j][3]);
      final double inter = math.max(0.0, xx2 - xx1) * math.max(0.0, yy2 - yy1);
      final double u = areas[i] + areas[j] - inter + 1e-7;
      if (inter / u > iouThres) suppressed[n] = true;
    }
  }

  return keep;
}

/// Weighted Non-Maximum Suppression over XYXY-format bounding boxes.
///
/// Like [nms], but fuses overlapping boxes by computing a score-weighted
/// average of their coordinates. Produces tighter bounding boxes when
/// many overlapping detections fire on the same object, which is common
/// with SSD/anchor-based models like MediaPipe BlazeFace and BlazePalm.
///
/// Returns a list of records containing:
/// - `index`: Index of the highest-scoring detection in the cluster.
/// - `box`: Score-weighted average XYXY bounding box.
/// - `score`: Score of the highest-scoring detection.
///
/// Parameters:
/// - [boxes]: List of bounding boxes in `[x1, y1, x2, y2]` format.
/// - [scores]: Confidence score for each box.
/// - [iouThres]: IoU threshold above which boxes are merged (default 0.45).
/// - [maxDet]: Maximum number of detections to return (default 100).
List<({int index, List<double> box, double score})> weightedNms(
  List<List<double>> boxes,
  List<double> scores, {
  double iouThres = 0.45,
  int maxDet = 100,
}) {
  if (boxes.isEmpty) return const [];

  final List<int> order = argSortDesc(scores);

  double area(List<double> b) =>
      math.max(0.0, b[2] - b[0]) * math.max(0.0, b[3] - b[1]);

  final List<double> areas = boxes.map(area).toList();
  final List<bool> suppressed = List<bool>.filled(order.length, false);
  final List<({int index, List<double> box, double score})> kept = [];

  for (int m = 0; m < order.length; m++) {
    if (suppressed[m]) continue;
    final int i = order[m];
    final List<double> base = boxes[i];
    final double baseScore = scores[i];

    double sw = baseScore;
    double wx1 = base[0] * baseScore;
    double wy1 = base[1] * baseScore;
    double wx2 = base[2] * baseScore;
    double wy2 = base[3] * baseScore;

    for (int n = m + 1; n < order.length; n++) {
      if (suppressed[n]) continue;
      final int j = order[n];
      final double xx1 = math.max(base[0], boxes[j][0]);
      final double yy1 = math.max(base[1], boxes[j][1]);
      final double xx2 = math.min(base[2], boxes[j][2]);
      final double yy2 = math.min(base[3], boxes[j][3]);
      final double inter = math.max(0.0, xx2 - xx1) * math.max(0.0, yy2 - yy1);
      final double u = areas[i] + areas[j] - inter + 1e-7;
      if (inter / u > iouThres) {
        suppressed[n] = true;
        final double s = scores[j];
        sw += s;
        wx1 += boxes[j][0] * s;
        wy1 += boxes[j][1] * s;
        wx2 += boxes[j][2] * s;
        wy2 += boxes[j][3] * s;
      }
    }

    kept.add((
      index: i,
      box: [wx1 / sw, wy1 / sw, wx2 / sw, wy2 / sw],
      score: baseScore,
    ));
    if (kept.length >= maxDet) break;
  }

  return kept;
}
