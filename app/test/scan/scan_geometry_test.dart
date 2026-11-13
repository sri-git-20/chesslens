import 'dart:math' as math;

import 'package:chesslens/src/scan/geometry.dart';
import 'package:chesslens/src/scan/gray_image.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page with an 8x8 checkerboard whose cell (row, col) is dark when
/// (row + col) is odd, drawn through the homography [forward] that maps the
/// unit board [0, 8] x [0, 8] to page pixels.
GrayImage checkerboardPage(int width, int height, Mat3 forward) {
  final inverse = forward.inverse()!;
  final page = GrayImage.filled(width, height, 1.0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = inverse.apply(Pt(x + 0.5, y + 0.5));
      if (p.x < 0 || p.y < 0 || p.x >= 8 || p.y >= 8) continue;
      final dark = (p.x.floor() + p.y.floor()).isOdd;
      page.data[y * width + x] = dark ? 0.0 : 1.0;
    }
  }
  return page;
}

void main() {
  group('homography', () {
    test('maps the four source points onto the four targets', () {
      final src = [const Pt(10, 20), const Pt(210, 30), const Pt(200, 240), const Pt(5, 230)];
      final dst = [const Pt(0, 0), const Pt(256, 0), const Pt(256, 256), const Pt(0, 256)];
      final h = perspectiveTransform(src, dst)!;
      for (var i = 0; i < 4; i++) {
        final mapped = h.apply(src[i]);
        expect(mapped.x, closeTo(dst[i].x, 1e-6));
        expect(mapped.y, closeTo(dst[i].y, 1e-6));
      }
    });

    test('inverse undoes the transform', () {
      final h = perspectiveTransform(
        [const Pt(0, 0), const Pt(100, 5), const Pt(90, 110), const Pt(-4, 95)],
        [const Pt(0, 0), const Pt(64, 0), const Pt(64, 64), const Pt(0, 64)],
      )!;
      final back = h.inverse()!;
      const p = Pt(33.5, 21.25);
      final round = back.apply(h.apply(p));
      expect(round.x, closeTo(p.x, 1e-9));
      expect(round.y, closeTo(p.y, 1e-9));
    });

    test('degenerate input gives null', () {
      final line = [const Pt(0, 0), const Pt(1, 1), const Pt(2, 2), const Pt(3, 3)];
      final dst = [const Pt(0, 0), const Pt(1, 0), const Pt(1, 1), const Pt(0, 1)];
      expect(perspectiveTransform(line, dst), isNull);
    });
  });

  group('letterbox', () {
    test('scales the long side to 384, keeps the page top-left, pads white', () {
      final page = GrayImage.filled(200, 100, 0.25);
      final (canvas, scale) = letterbox(page);
      expect(scale, closeTo(384 / 200, 1e-12));
      expect(canvas.width, 384);
      expect(canvas.height, 384);
      expect(canvas.at(0, 0), closeTo(0.25, 1e-6));
      expect(canvas.at(383, 191), closeTo(0.25, 1e-6));
      expect(canvas.at(0, 192), 1.0);
      expect(canvas.at(100, 300), 1.0);
    });

    test('a tall page is scaled by its height', () {
      final page = GrayImage.filled(100, 400, 0.5);
      final (canvas, scale) = letterbox(page);
      expect(scale, closeTo(0.96, 1e-12));
      expect(canvas.at(95, 383), closeTo(0.5, 1e-6));
      expect(canvas.at(96, 10), 1.0);
    });

    test('a small page is scaled up', () {
      final page = GrayImage.filled(96, 96, 0.5);
      final (canvas, scale) = letterbox(page);
      expect(scale, 4.0);
      expect(canvas.at(383, 383), closeTo(0.5, 1e-6));
    });
  });

  group('resize', () {
    test('area average of a checker pattern is grey', () {
      final src = GrayImage(8, 8);
      for (var y = 0; y < 8; y++) {
        for (var x = 0; x < 8; x++) {
          src.data[y * 8 + x] = (x + y).isEven ? 1.0 : 0.0;
        }
      }
      final out = resizeGray(src, 4, 4);
      for (final v in out.data) {
        expect(v, closeTo(0.5, 1e-6));
      }
    });

    test('fractional area resize keeps the mean', () {
      final src = GrayImage(10, 10);
      for (var i = 0; i < 100; i++) {
        src.data[i] = (i % 7) / 7;
      }
      final out = resizeGray(src, 4, 4);
      final mean = out.data.reduce((a, b) => a + b) / 16;
      final srcMean = src.data.reduce((a, b) => a + b) / 100;
      expect(mean, closeTo(srcMean, 0.03));
    });
  });

  group('warpRegion', () {
    void expectCheckerboard(GrayImage warped, {int minCorrect = 64}) {
      var correct = 0;
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 8; c++) {
          final v = warped.at(c * 32 + 16, r * 32 + 16);
          final dark = (r + c).isOdd;
          if ((dark && v < 0.2) || (!dark && v > 0.8)) correct++;
        }
      }
      expect(correct, greaterThanOrEqualTo(minCorrect));
    }

    test('an axis-aligned board becomes the 256x256 checkerboard', () {
      final forward = Mat3([25, 0, 100, 0, 25, 50, 0, 0, 1]);
      final page = checkerboardPage(400, 320, forward);
      final quad = Quad.fromRect(100, 50, 300, 250);
      final warp = warpRegion(page, quad, 256);
      expect(warp.image.width, 256);
      expectCheckerboard(warp.image);
      // The homography maps page points to warped points.
      final p = warp.homography.apply(const Pt(100, 50));
      expect(p.x, closeTo(0, 1e-6));
      expect(p.y, closeTo(0, 1e-6));
      final q = warp.homography.apply(const Pt(300, 250));
      expect(q.x, closeTo(256, 1e-6));
      expect(q.y, closeTo(256, 1e-6));
    });

    test('a rotated, tilted board is straightened', () {
      // Unit-square corners go to a skewed quad.
      final target = [const Pt(60, 40), const Pt(330, 70), const Pt(310, 300), const Pt(40, 270)];
      final unit = [const Pt(0, 0), const Pt(8, 0), const Pt(8, 8), const Pt(0, 8)];
      final forward = perspectiveTransform(unit, target)!;
      final page = checkerboardPage(400, 340, forward);
      final warp = warpRegion(page, Quad(target), 256);
      expectCheckerboard(warp.image, minCorrect: 62);
    });

    test('a board larger than the output is shrunk first and still reads', () {
      final forward = Mat3([60, 0, 200, 0, 60, 100, 0, 0, 1]); // 480 px board
      final page = checkerboardPage(900, 700, forward);
      final quad = Quad.fromRect(200, 100, 680, 580);
      expectCheckerboard(warpRegion(page, quad, 256).image);
    });

    test('pixels outside the page are white', () {
      final page = GrayImage.filled(100, 100, 0.0);
      final quad = Quad.fromRect(-100, -100, 0, 0);
      final warp = warpRegion(page, quad, 64);
      expect(warp.image.data.every((v) => v == 1.0), isTrue);
    });

    test('a quad half outside the page is white on the outside half', () {
      final page = GrayImage.filled(100, 100, 0.0);
      final quad = Quad.fromRect(50, 0, 150, 100);
      final warp = warpRegion(page, quad, 64);
      expect(warp.image.at(8, 32), closeTo(0.0, 0.05));
      expect(warp.image.at(56, 32), closeTo(1.0, 0.05));
    });
  });

  group('coarseSquare', () {
    test('is centred on the bounding box and 1.25 times its longest side', () {
      final q = Quad([const Pt(100, 100), const Pt(300, 110), const Pt(290, 260), const Pt(95, 250)]);
      final square = coarseSquare(q);
      final side = 1.25 * math.max(q.width, q.height);
      expect(square.width, closeTo(side, 1e-9));
      expect(square.height, closeTo(side, 1e-9));
      expect(square.center.x, closeTo(q.center.x, 1e-9));
      expect(square.center.y, closeTo(q.center.y, 1e-9));
    });
  });
}
