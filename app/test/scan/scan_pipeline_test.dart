import 'dart:typed_data';

import 'package:chesslens/src/scan/geometry.dart';
import 'package:chesslens/src/scan/gray_image.dart';
import 'package:chesslens/src/scan/model_decode.dart';
import 'package:chesslens/src/scan/pipeline.dart';
import 'package:chesslens/src/scan/scan_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A white page with one 8x8 checkerboard whose corners are [quad]
/// (axis-aligned). Cell (row, col) is dark when (row + col) is odd.
img.Image boardPage(int width, int height, Quad quad) {
  final image = img.Image(width: width, height: height, numChannels: 3);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  final cw = quad.width / 8;
  final ch = quad.height / 8;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final fx = (x + 0.5 - quad.minX) / cw;
      final fy = (y + 0.5 - quad.minY) / ch;
      if (fx < 0 || fy < 0 || fx >= 8 || fy >= 8) continue;
      if ((fx.floor() + fy.floor()).isOdd) {
        image.setPixelRgb(x, y, 0, 0, 0);
      }
    }
  }
  return image;
}

/// Fake models that "see" the synthetic board.
///
/// The detector reports [coarse] (a slightly wrong quad). The corners model
/// reports the true corners, converted to the crop of the coarse quad. The
/// squares model calls a dark cell a white pawn and a light cell empty.
RecognitionPipeline fakePipeline({
  required Quad truth,
  required Quad coarse,
  required Size2 pageSize,
}) {
  final scale = detectorSize / (pageSize.w > pageSize.h ? pageSize.w : pageSize.h);
  return RecognitionPipeline(
    detector: (input) {
      expect(input.length, detectorSize * detectorSize);
      final out = Float32List(96 * 96 * 9);
      final c = coarse.center;
      final cx = (c.x * scale / 4).floor();
      final cy = (c.y * scale / 4).floor();
      final base = (cy * 96 + cx) * 9;
      out[base] = 0.9;
      final centerX = (cx + 0.5) * 4;
      final centerY = (cy + 0.5) * 4;
      for (var k = 0; k < 4; k++) {
        final p = coarse.points[k];
        out[base + 1 + 2 * k] = (p.x * scale - centerX) / 384;
        out[base + 2 + 2 * k] = (p.y * scale - centerY) / 384;
      }
      return out;
    },
    corners: (input) {
      expect(input.length, cornersSize * cornersSize);
      final warp = warpRegion(
        GrayImage(pageSize.w, pageSize.h),
        coarseSquare(coarse),
        cornersSize,
      );
      final out = Float32List(64 * 64 * 4);
      for (var k = 0; k < 4; k++) {
        final p = warp.homography.apply(truth.points[k]);
        final gx = (p.x / 4 - 0.5).round();
        final gy = (p.y / 4 - 0.5).round();
        out[(gy * 64 + gx) * 4 + k] = 1.0;
      }
      return out;
    },
    squares: (input) {
      expect(input.length, squaresSize * squaresSize);
      final out = Float32List(64 * classCount);
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 8; c++) {
          final v = input[(r * 32 + 16) * 256 + c * 32 + 16];
          final pawn = v < 0.5;
          out[(r * 8 + c) * classCount + (pawn ? 1 : 0)] = 1.0;
        }
      }
      return out;
    },
  );
}

class Size2 {
  const Size2(this.w, this.h);
  final int w;
  final int h;
}

void main() {
  final truth = Quad.fromRect(120, 60, 320, 260);
  final coarse = Quad.fromRect(110, 52, 332, 270);
  const page = Size2(500, 380);

  group('RecognitionPipeline', () {
    test('finds, refines and reads a synthetic board', () {
      final gray = grayFromImage(boardPage(page.w, page.h, truth));
      final pipeline = fakePipeline(truth: truth, coarse: coarse, pageSize: page);

      final dets = pipeline.detect(gray);
      expect(dets, hasLength(1));
      for (var k = 0; k < 4; k++) {
        expect(dets.single.quad.points[k].x, closeTo(coarse.points[k].x, 4));
        expect(dets.single.quad.points[k].y, closeTo(coarse.points[k].y, 4));
      }

      final read = pipeline.readDetection(gray, dets.single);
      for (var k = 0; k < 4; k++) {
        // The corners grid has 4-pixel cells in a crop that is ~1.1 times
        // smaller than the page, so a few pixels of slack.
        expect(read.quad.points[k].x, closeTo(truth.points[k].x, 5));
        expect(read.quad.points[k].y, closeTo(truth.points[k].y, 5));
      }
      final classes = squareClasses(read.probs);
      for (var r = 0; r < 8; r++) {
        for (var c = 0; c < 8; c++) {
          expect(classes[r * 8 + c], (r + c).isOdd ? 1 : 0, reason: 'row $r col $c');
        }
      }
      expect(
        placementFromClasses(classes),
        '1P1P1P1P/P1P1P1P1/1P1P1P1P/P1P1P1P1/1P1P1P1P/P1P1P1P1/1P1P1P1P/P1P1P1P1',
      );
    });

    test('a page with no peak has no boards', () {
      final pipeline = RecognitionPipeline(
        detector: (_) => Float32List(96 * 96 * 9),
        corners: (_) => throw StateError('not called'),
        squares: (_) => throw StateError('not called'),
      );
      expect(pipeline.readPage(GrayImage.filled(100, 80, 1.0)), isEmpty);
    });
  });

  group('ScanEngine', () {
    test('decodes a PNG, reads the board and returns a page JPEG and a crop', () {
      final pipeline = fakePipeline(truth: truth, coarse: coarse, pageSize: page);
      final engine = ScanEngine(pipeline);
      final png = img.encodePng(boardPage(page.w, page.h, truth));
      final analysis = engine.analyze(1, EncodedInput(png));
      expect(analysis.width, page.w);
      expect(analysis.height, page.h);
      expect(analysis.boards, hasLength(1));

      final jpeg = img.decodeJpg(analysis.jpeg)!;
      expect(jpeg.width, page.w);

      final board = analysis.boards.single;
      expect(board.probs, hasLength(64 * classCount));
      expect(board.corners, hasLength(8));
      final crop = img.decodePng(board.cropPng)!;
      expect(crop.width, cropSize);
      expect(crop.height, cropSize);

      // Reading the same quad again from the cache gives the same squares.
      final again = engine.readQuad(1, analysis.jpeg, board.quad);
      expect(squareClasses(again.probs), squareClasses(board.probs));
    });

    test('raw BGRA pixels work like an encoded image', () {
      final pipeline = fakePipeline(truth: truth, coarse: coarse, pageSize: page);
      final engine = ScanEngine(pipeline);
      final rgb = boardPage(page.w, page.h, truth);
      final bgra = Uint8List(page.w * page.h * 4);
      for (var i = 0, p = 0; i < page.w * page.h; i++, p += 4) {
        final pixel = rgb.getPixel(i % page.w, i ~/ page.w);
        bgra[p] = pixel.b.toInt();
        bgra[p + 1] = pixel.g.toInt();
        bgra[p + 2] = pixel.r.toInt();
        bgra[p + 3] = 255;
      }
      final analysis = engine.analyze(2, BgraInput(page.w, page.h, bgra));
      expect(analysis.boards, hasLength(1));
    });

    test('garbage bytes give a readable error', () {
      final engine = ScanEngine(fakePipeline(truth: truth, coarse: coarse, pageSize: page));
      expect(
        () => engine.analyze(3, EncodedInput(Uint8List.fromList([1, 2, 3, 4]))),
        throwsA(isA<ScanException>()),
      );
    });
  });

  group('grayscale', () {
    test('uses the BT.601 luma weights', () {
      final image = img.Image(width: 3, height: 1, numChannels: 3);
      image.setPixelRgb(0, 0, 255, 0, 0);
      image.setPixelRgb(1, 0, 0, 255, 0);
      image.setPixelRgb(2, 0, 0, 0, 255);
      final gray = grayFromImage(image);
      expect(gray.at(0, 0), closeTo(0.299, 1e-6));
      expect(gray.at(1, 0), closeTo(0.587, 1e-6));
      expect(gray.at(2, 0), closeTo(0.114, 1e-6));
    });

    test('BGRA input gives the same values', () {
      final gray = grayFromBgra(1, 1, Uint8List.fromList([0, 0, 255, 255]));
      expect(gray.at(0, 0), closeTo(0.299, 1e-6));
    });
  });
}
