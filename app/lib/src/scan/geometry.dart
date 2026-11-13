import 'dart:math' as math;

/// A point in continuous image coordinates: (0, 0) is the top-left corner of
/// the top-left pixel and the centre of pixel (i, j) is (i + 0.5, j + 0.5).
class Pt {
  const Pt(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) => other is Pt && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Pt(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// Four corners in the order top-left, top-right, bottom-right, bottom-left
/// (by position in the image).
class Quad {
  Quad(List<Pt> points)
      : assert(points.length == 4),
        points = List.unmodifiable(points);

  /// Builds a quad from 8 numbers: TL.x, TL.y, TR.x, TR.y, BR.x, BR.y, BL.x, BL.y.
  factory Quad.fromList(List<double> v) => Quad([
        Pt(v[0], v[1]),
        Pt(v[2], v[3]),
        Pt(v[4], v[5]),
        Pt(v[6], v[7]),
      ]);

  /// An axis-aligned rectangle as a quad.
  factory Quad.fromRect(double left, double top, double right, double bottom) =>
      Quad([Pt(left, top), Pt(right, top), Pt(right, bottom), Pt(left, bottom)]);

  final List<Pt> points;

  Pt get tl => points[0];
  Pt get tr => points[1];
  Pt get br => points[2];
  Pt get bl => points[3];

  List<double> toList() => [for (final p in points) ...[p.x, p.y]];

  double get minX => points.map((p) => p.x).reduce(math.min);
  double get maxX => points.map((p) => p.x).reduce(math.max);
  double get minY => points.map((p) => p.y).reduce(math.min);
  double get maxY => points.map((p) => p.y).reduce(math.max);
  double get width => maxX - minX;
  double get height => maxY - minY;
  Pt get center => Pt((minX + maxX) / 2, (minY + maxY) / 2);

  /// Mean length of the four edges.
  double get meanSide {
    var total = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = points[i];
      final b = points[(i + 1) % 4];
      total += math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
    }
    return total / 4;
  }

  Quad withPoint(int index, Pt p) {
    final next = List<Pt>.of(points);
    next[index] = p;
    return Quad(next);
  }

  Quad map(Pt Function(Pt) f) => Quad(points.map(f).toList());
}

/// A 3x3 matrix in row-major order, used as a homography.
class Mat3 {
  Mat3(List<double> v)
      : assert(v.length == 9),
        v = List.unmodifiable(v);

  static final identity = Mat3([1, 0, 0, 0, 1, 0, 0, 0, 1]);

  final List<double> v;

  Mat3 operator *(Mat3 o) {
    final r = List<double>.filled(9, 0);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        var s = 0.0;
        for (var k = 0; k < 3; k++) {
          s += v[i * 3 + k] * o.v[k * 3 + j];
        }
        r[i * 3 + j] = s;
      }
    }
    return Mat3(r);
  }

  /// The inverse, or `null` when the matrix is singular.
  Mat3? inverse() {
    final a = v[0], b = v[1], c = v[2];
    final d = v[3], e = v[4], f = v[5];
    final g = v[6], h = v[7], i = v[8];
    final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    if (det.abs() < 1e-18) return null;
    final inv = 1 / det;
    return Mat3([
      (e * i - f * h) * inv,
      (c * h - b * i) * inv,
      (b * f - c * e) * inv,
      (f * g - d * i) * inv,
      (a * i - c * g) * inv,
      (c * d - a * f) * inv,
      (d * h - e * g) * inv,
      (b * g - a * h) * inv,
      (a * e - b * d) * inv,
    ]);
  }

  Pt apply(Pt p) {
    final w = v[6] * p.x + v[7] * p.y + v[8];
    return Pt(
      (v[0] * p.x + v[1] * p.y + v[2]) / w,
      (v[3] * p.x + v[4] * p.y + v[5]) / w,
    );
  }
}

/// The homography that maps the four [src] points onto the four [dst] points
/// (like `cv2.getPerspectiveTransform`). Returns `null` for degenerate input.
Mat3? perspectiveTransform(List<Pt> src, List<Pt> dst) {
  // Unknowns h0..h7 with h8 = 1; two equations per point pair.
  final a = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var i = 0; i < 4; i++) {
    final x = src[i].x, y = src[i].y, u = dst[i].x, w = dst[i].y;
    a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u];
    a[2 * i + 1] = [0, 0, 0, x, y, 1, -w * x, -w * y, w];
  }
  // Gaussian elimination with partial pivoting.
  for (var col = 0; col < 8; col++) {
    var pivot = col;
    for (var r = col + 1; r < 8; r++) {
      if (a[r][col].abs() > a[pivot][col].abs()) pivot = r;
    }
    if (a[pivot][col].abs() < 1e-12) return null;
    final tmp = a[col];
    a[col] = a[pivot];
    a[pivot] = tmp;
    for (var r = 0; r < 8; r++) {
      if (r == col) continue;
      final factor = a[r][col] / a[col][col];
      if (factor == 0) continue;
      for (var c = col; c < 9; c++) {
        a[r][c] -= factor * a[col][c];
      }
    }
  }
  final h = [for (var i = 0; i < 8; i++) a[i][8] / a[i][i]];
  return Mat3([...h, 1.0]);
}
