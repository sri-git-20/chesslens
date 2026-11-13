import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'geometry.dart';

/// A greyscale image with float values in [0, 1], row-major.
class GrayImage {
  GrayImage(this.width, this.height, [Float32List? data])
      : data = data ?? Float32List(width * height);

  /// An image filled with [value].
  GrayImage.filled(this.width, this.height, double value)
      : data = Float32List(width * height)..fillRange(0, width * height, value);

  final int width;
  final int height;
  final Float32List data;

  double at(int x, int y) => data[y * width + x];

  /// Greyscale as 8-bit values, for saving a crop.
  Uint8List toBytes() {
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = (data[i] * 255).round().clamp(0, 255);
    }
    return out;
  }
}

/// Greyscale `(0.299 R + 0.587 G + 0.114 B) / 255`; alpha is ignored.
GrayImage grayFromImage(img.Image image) {
  var source = image;
  if (source.format != img.Format.uint8 || source.hasPalette) {
    source = source.convert(
      format: img.Format.uint8,
      numChannels: source.numChannels,
    );
  }
  final channels = source.numChannels;
  final bytes = source.getBytes();
  final w = source.width;
  final h = source.height;
  final out = Float32List(w * h);
  if (channels >= 3) {
    for (var i = 0, j = 0; i < out.length; i++, j += channels) {
      out[i] = (0.299 * bytes[j] + 0.587 * bytes[j + 1] + 0.114 * bytes[j + 2]) / 255;
    }
  } else {
    for (var i = 0, j = 0; i < out.length; i++, j += channels) {
      out[i] = bytes[j] / 255;
    }
  }
  return GrayImage(w, h, out);
}

/// Greyscale from BGRA8888 pixels (as rendered by pdfrx).
GrayImage grayFromBgra(int width, int height, Uint8List bgra) {
  final out = Float32List(width * height);
  for (var i = 0, j = 0; i < out.length; i++, j += 4) {
    out[i] = (0.299 * bgra[j + 2] + 0.587 * bgra[j + 1] + 0.114 * bgra[j]) / 255;
  }
  return GrayImage(width, height, out);
}

/// Weights for one axis of a separable resize.
class _Taps {
  _Taps(this.start, this.count, this.weights);
  final Int32List start;
  final Int32List count;
  final List<Float32List> weights;
}

_Taps _areaTaps(int srcN, int dstN) {
  final scale = srcN / dstN;
  final start = Int32List(dstN);
  final count = Int32List(dstN);
  final weights = <Float32List>[];
  for (var d = 0; d < dstN; d++) {
    final a = d * scale;
    final b = math.min((d + 1) * scale, srcN.toDouble());
    final i0 = a.floor();
    final i1 = math.min(b.ceil(), srcN);
    final w = Float32List(i1 - i0);
    var sum = 0.0;
    for (var i = i0; i < i1; i++) {
      final overlap = math.min(i + 1.0, b) - math.max(i.toDouble(), a);
      w[i - i0] = overlap;
      sum += overlap;
    }
    for (var k = 0; k < w.length; k++) {
      w[k] = w[k] / sum;
    }
    start[d] = i0;
    count[d] = i1 - i0;
    weights.add(w);
  }
  return _Taps(start, count, weights);
}

_Taps _linearTaps(int srcN, int dstN) {
  final scale = srcN / dstN;
  final start = Int32List(dstN);
  final count = Int32List(dstN);
  final weights = <Float32List>[];
  for (var d = 0; d < dstN; d++) {
    final s = (d + 0.5) * scale - 0.5;
    var i0 = s.floor();
    var f = s - i0;
    var i1 = i0 + 1;
    if (i0 < 0) {
      i0 = 0;
      i1 = 0;
      f = 0;
    }
    if (i1 > srcN - 1) {
      i1 = srcN - 1;
      if (i0 > srcN - 1) i0 = srcN - 1;
    }
    if (i0 == i1) {
      start[d] = i0;
      count[d] = 1;
      weights.add(Float32List.fromList([1]));
    } else {
      start[d] = i0;
      count[d] = 2;
      weights.add(Float32List.fromList([1 - f, f]));
    }
  }
  return _Taps(start, count, weights);
}

/// Resizes like OpenCV `INTER_AREA`: box averaging when shrinking on both axes,
/// bilinear otherwise.
GrayImage resizeGray(GrayImage src, int newWidth, int newHeight) {
  if (newWidth == src.width && newHeight == src.height) {
    return GrayImage(src.width, src.height, Float32List.fromList(src.data));
  }
  final shrink = src.width >= newWidth && src.height >= newHeight;
  final tx = shrink ? _areaTaps(src.width, newWidth) : _linearTaps(src.width, newWidth);
  final ty = shrink ? _areaTaps(src.height, newHeight) : _linearTaps(src.height, newHeight);

  final tmp = Float32List(src.height * newWidth);
  for (var y = 0; y < src.height; y++) {
    final row = y * src.width;
    for (var x = 0; x < newWidth; x++) {
      final w = tx.weights[x];
      final s = tx.start[x];
      var acc = 0.0;
      for (var k = 0; k < w.length; k++) {
        acc += src.data[row + s + k] * w[k];
      }
      tmp[y * newWidth + x] = acc;
    }
  }
  final out = Float32List(newWidth * newHeight);
  for (var y = 0; y < newHeight; y++) {
    final w = ty.weights[y];
    final s = ty.start[y];
    for (var x = 0; x < newWidth; x++) {
      var acc = 0.0;
      for (var k = 0; k < w.length; k++) {
        acc += tmp[(s + k) * newWidth + x] * w[k];
      }
      out[y * newWidth + x] = acc;
    }
  }
  return GrayImage(newWidth, newHeight, out);
}

/// The square network input of the detector.
const int detectorSize = 384;

/// Scales so the longer side is 384, places the page at (0, 0) and fills the
/// rest with white. Returns the canvas and the scale factor.
(GrayImage, double) letterbox(GrayImage gray) {
  final s = detectorSize / math.max(gray.width, gray.height);
  final nw = math.max(1, (gray.width * s).round());
  final nh = math.max(1, (gray.height * s).round());
  final small = resizeGray(gray, nw, nh);
  final canvas = GrayImage.filled(detectorSize, detectorSize, 1.0);
  final cw = math.min(nw, detectorSize);
  final ch = math.min(nh, detectorSize);
  for (var y = 0; y < ch; y++) {
    canvas.data.setRange(
      y * detectorSize,
      y * detectorSize + cw,
      small.data,
      y * nw,
    );
  }
  return (canvas, s);
}

/// Result of [warpRegion]: the warped image and the homography that maps
/// original continuous coordinates to warped continuous coordinates.
class Warp {
  Warp(this.image, this.homography);
  final GrayImage image;
  final Mat3 homography;
}

/// Perspective-warps the region [src] (TL, TR, BR, BL) of [image] onto an
/// [out] x [out] square: TL to (0, 0), TR to (out, 0), BR to (out, out) and BL
/// to (0, out). Samples outside the image are white. Bilinear sampling,
/// preceded by an area-average shrink when the region is much larger than the
/// output. Follows `warp_region` of the reference pipeline.
Warp warpRegion(GrayImage image, Quad src, int out) {
  final dst = [
    const Pt(0, 0),
    Pt(out.toDouble(), 0),
    Pt(out.toDouble(), out.toDouble()),
    Pt(0, out.toDouble()),
  ];
  final plain = perspectiveTransform(src.points, dst) ?? Mat3.identity;
  final x0 = math.max(0, src.minX.floor() - 2);
  final x1 = math.min(image.width, src.maxX.ceil() + 2);
  final y0 = math.max(0, src.minY.floor() - 2);
  final y1 = math.min(image.height, src.maxY.ceil() + 2);
  if (x1 - x0 < 2 || y1 - y0 < 2) {
    return Warp(GrayImage.filled(out, out, 1.0), plain);
  }

  var roi = GrayImage(x1 - x0, y1 - y0);
  for (var y = y0; y < y1; y++) {
    roi.data.setRange(
      (y - y0) * roi.width,
      (y - y0 + 1) * roi.width,
      image.data,
      y * image.width + x0,
    );
  }
  var fx = 1.0;
  var fy = 1.0;
  final side = src.meanSide;
  if (side / out > 1.5) {
    final f = out / side;
    final nw = math.max(1, (roi.width * f).round());
    final nh = math.max(1, (roi.height * f).round());
    final shrunk = resizeGray(roi, nw, nh);
    fx = nw / (x1 - x0);
    fy = nh / (y1 - y0);
    roi = shrunk;
  }
  final scaleToRoi = Mat3([fx, 0, -x0 * fx, 0, fy, -y0 * fy, 0, 0, 1]);
  final srcScaled = [
    for (final p in src.points) Pt((p.x - x0) * fx, (p.y - y0) * fy),
  ];
  final hs = perspectiveTransform(srcScaled, dst);
  if (hs == null) {
    return Warp(GrayImage.filled(out, out, 1.0), plain);
  }
  final inverse = hs.inverse();
  if (inverse == null) {
    return Warp(GrayImage.filled(out, out, 1.0), plain);
  }

  final result = Float32List(out * out);
  final rw = roi.width;
  final rh = roi.height;
  final rd = roi.data;
  const fill = 1.0;
  double px(int x, int y) =>
      (x < 0 || y < 0 || x >= rw || y >= rh) ? fill : rd[y * rw + x];
  for (var j = 0; j < out; j++) {
    for (var i = 0; i < out; i++) {
      final p = inverse.apply(Pt(i + 0.5, j + 0.5));
      final sx = p.x - 0.5;
      final sy = p.y - 0.5;
      final xi = sx.floor();
      final yi = sy.floor();
      final ax = sx - xi;
      final ay = sy - yi;
      final top = px(xi, yi) * (1 - ax) + px(xi + 1, yi) * ax;
      final bottom = px(xi, yi + 1) * (1 - ax) + px(xi + 1, yi + 1) * ax;
      result[j * out + i] = top * (1 - ay) + bottom * ay;
    }
  }
  return Warp(GrayImage(out, out, result), hs * scaleToRoi);
}

/// The square around a coarse quad: centre = bounding-box centre, side
/// `1.25 * max(bbox width, bbox height)`.
Quad coarseSquare(Quad quad) {
  final c = quad.center;
  final side = math.max(1.25 * math.max(quad.width, quad.height), 8.0);
  final h = side / 2;
  return Quad.fromRect(c.x - h, c.y - h, c.x + h, c.y + h);
}
