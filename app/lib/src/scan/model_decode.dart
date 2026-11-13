import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'gray_image.dart';

const int detectorGrid = 96;
const int detectorChannels = 9;
const int detectorStride = 4;
const double detectorThreshold = 0.35;

const int cornersSize = 256;
const int cornersGrid = 64;
const int cornersStride = 4;

const int squaresSize = 256;
const int classCount = 13;

/// FEN letters for the 13 classes: empty, then P N B R Q K, then p n b r q k.
const List<String> classFenChars = [
  '', 'P', 'N', 'B', 'R', 'Q', 'K', 'p', 'n', 'b', 'r', 'q', 'k', //
];

/// A board found by the detector, with its coarse corners in original pixels.
class Detection {
  const Detection({required this.score, required this.quad, required this.cellX, required this.cellY});

  final double score;
  final Quad quad;
  final int cellX;
  final int cellY;
}

/// Decodes the detector output `[96, 96, 9]` (flat). A board is a cell whose
/// heat is at least [threshold] and is the maximum of its 3x3 neighbourhood;
/// exact ties between neighbours keep only the first cell in raster order.
/// [scale] is the letterbox scale: corners are divided by it to get original
/// pixels.
List<Detection> decodeDetector(
  Float32List out,
  double scale, {
  double threshold = detectorThreshold,
}) {
  const n = detectorGrid;
  const ch = detectorChannels;
  double heat(int x, int y) => out[(y * n + x) * ch];

  final accepted = <(int, int)>[];
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final v = heat(x, y);
      if (v < threshold) continue;
      var isMax = true;
      for (var dy = -1; dy <= 1 && isMax; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          if (dx == 0 && dy == 0) continue;
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= n || ny >= n) continue;
          if (heat(nx, ny) > v) {
            isMax = false;
            break;
          }
        }
      }
      if (!isMax) continue;
      final tied = accepted.any(
        (a) => (x - a.$1).abs() <= 1 && (y - a.$2).abs() <= 1 && heat(a.$1, a.$2) == v,
      );
      if (tied) continue;
      accepted.add((x, y));
    }
  }

  return [
    for (final (x, y) in accepted)
      () {
        final cx = (x + 0.5) * detectorStride;
        final cy = (y + 0.5) * detectorStride;
        final base = (y * n + x) * ch;
        Pt corner(int k) => Pt(
              (cx + out[base + 1 + 2 * k] * detectorSize) / scale,
              (cy + out[base + 2 + 2 * k] * detectorSize) / scale,
            );
        return Detection(
          score: heat(x, y),
          quad: Quad([corner(0), corner(1), corner(2), corner(3)]),
          cellX: x,
          cellY: y,
        );
      }(),
  ];
}

/// Decodes the corners output `[64, 64, 4]` (flat) to four points in crop
/// pixels: per channel the arg-max cell, refined with the value-weighted mean
/// of its 3x3 neighbourhood; pixel = `(x + 0.5) * 4`.
List<Pt> decodeCorners(Float32List out) {
  const n = cornersGrid;
  const ch = 4;
  final points = <Pt>[];
  for (var k = 0; k < ch; k++) {
    var best = -double.infinity;
    var bx = 0;
    var by = 0;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final v = out[(y * n + x) * ch + k];
        if (v > best) {
          best = v;
          bx = x;
          by = y;
        }
      }
    }
    final ya = math.max(0, by - 1);
    final yb = math.min(n, by + 2);
    final xa = math.max(0, bx - 1);
    final xb = math.min(n, bx + 2);
    var total = 0.0;
    var sx = 0.0;
    var sy = 0.0;
    for (var y = ya; y < yb; y++) {
      for (var x = xa; x < xb; x++) {
        final v = out[(y * n + x) * ch + k];
        total += v;
        sx += v * x;
        sy += v * y;
      }
    }
    final mx = total <= 0 ? bx.toDouble() : sx / total;
    final my = total <= 0 ? by.toDouble() : sy / total;
    points.add(Pt((mx + 0.5) * cornersStride, (my + 0.5) * cornersStride));
  }
  return points;
}

/// Arg-max class per square of the squares output `[8, 8, 13]` (flat).
Uint8List squareClasses(Float32List probs) {
  final classes = Uint8List(64);
  for (var i = 0; i < 64; i++) {
    var best = 0;
    for (var c = 1; c < classCount; c++) {
      if (probs[i * classCount + c] > probs[i * classCount + best]) best = c;
    }
    classes[i] = best;
  }
  return classes;
}

/// The probability of the winning class per square.
Float32List squareConfidence(Float32List probs) {
  final conf = Float32List(64);
  for (var i = 0; i < 64; i++) {
    var best = 0.0;
    for (var c = 0; c < classCount; c++) {
      best = math.max(best, probs[i * classCount + c]);
    }
    conf[i] = best;
  }
  return conf;
}

/// FEN piece placement from 64 class ids, row 0 first (as drawn).
String placementFromClasses(Uint8List classes) {
  final ranks = <String>[];
  for (var r = 0; r < 8; r++) {
    final sb = StringBuffer();
    var empty = 0;
    for (var c = 0; c < 8; c++) {
      final k = classes[r * 8 + c];
      if (k == 0) {
        empty++;
      } else {
        if (empty > 0) sb.write(empty);
        empty = 0;
        sb.write(classFenChars[k]);
      }
    }
    if (empty > 0) sb.write(empty);
    ranks.add(sb.toString());
  }
  return ranks.join('/');
}
