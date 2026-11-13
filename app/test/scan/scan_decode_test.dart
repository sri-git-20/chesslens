import 'dart:typed_data';

import 'package:chesslens/src/scan/model_decode.dart';
import 'package:flutter_test/flutter_test.dart';

Float32List detectorOutput() => Float32List(96 * 96 * 9);

void setCell(Float32List out, int x, int y, double heat, [List<double>? offsets]) {
  final base = (y * 96 + x) * 9;
  out[base] = heat;
  if (offsets != null) {
    for (var i = 0; i < 8; i++) {
      out[base + 1 + i] = offsets[i];
    }
  }
}

void main() {
  group('decodeDetector', () {
    test('turns a peak into a quad in original pixels', () {
      final out = detectorOutput();
      // Cell (20, 30) has its centre at (82, 122) in letterbox pixels.
      setCell(out, 20, 30, 0.9, [
        -40 / 384, -50 / 384, //
        60 / 384, -48 / 384,
        62 / 384, 52 / 384,
        -38 / 384, 50 / 384,
      ]);
      final dets = decodeDetector(out, 0.5);
      expect(dets, hasLength(1));
      final q = dets.single.quad;
      expect(q.tl.x, closeTo((82 - 40) / 0.5, 1e-3));
      expect(q.tl.y, closeTo((122 - 50) / 0.5, 1e-3));
      expect(q.br.x, closeTo((82 + 62) / 0.5, 1e-3));
      expect(q.br.y, closeTo((122 + 52) / 0.5, 1e-3));
      expect(dets.single.score, closeTo(0.9, 1e-6));
    });

    test('keeps only the maximum of a 3x3 neighbourhood', () {
      final out = detectorOutput();
      setCell(out, 10, 10, 0.9);
      setCell(out, 11, 10, 0.8);
      setCell(out, 10, 11, 0.6);
      setCell(out, 50, 50, 0.7);
      final dets = decodeDetector(out, 1.0);
      expect(dets.map((d) => (d.cellX, d.cellY)).toSet(), {(10, 10), (50, 50)});
    });

    test('ignores values below the threshold', () {
      final out = detectorOutput();
      setCell(out, 5, 5, 0.34);
      setCell(out, 6, 40, 0.36);
      final dets = decodeDetector(out, 1.0);
      expect(dets.map((d) => (d.cellX, d.cellY)), [(6, 40)]);
    });

    test('an exact tie between neighbours keeps the first in raster order', () {
      final out = detectorOutput();
      setCell(out, 30, 30, 0.8);
      setCell(out, 31, 30, 0.8);
      final dets = decodeDetector(out, 1.0);
      expect(dets, hasLength(1));
      expect(dets.single.cellX, 30);
    });

    test('peaks on the border are found', () {
      final out = detectorOutput();
      setCell(out, 0, 0, 0.9);
      setCell(out, 95, 95, 0.9);
      expect(decodeDetector(out, 1.0), hasLength(2));
    });
  });

  group('decodeCorners', () {
    Float32List cornersOutput(List<(int, int)> peaks, {List<double>? neighbours}) {
      final out = Float32List(64 * 64 * 4);
      for (var k = 0; k < 4; k++) {
        out[(peaks[k].$2 * 64 + peaks[k].$1) * 4 + k] = 1.0;
      }
      return out;
    }

    test('a single-cell peak decodes to the cell centre', () {
      final out = cornersOutput([(10, 12), (50, 11), (51, 52), (9, 53)]);
      final pts = decodeCorners(out);
      expect(pts[0].x, closeTo(10.5 * 4, 1e-9));
      expect(pts[0].y, closeTo(12.5 * 4, 1e-9));
      expect(pts[2].x, closeTo(51.5 * 4, 1e-9));
      expect(pts[3].y, closeTo(53.5 * 4, 1e-9));
    });

    test('neighbours pull the point by their weight', () {
      final out = cornersOutput([(10, 10), (50, 10), (50, 50), (10, 50)]);
      // Channel 0: a weaker right neighbour shifts x by 0.5 / 1.5.
      out[(10 * 64 + 11) * 4 + 0] = 0.5;
      final p = decodeCorners(out)[0];
      expect(p.x, closeTo((10 + 0.5 / 1.5 + 0.5) * 4, 1e-6));
      expect(p.y, closeTo(10.5 * 4, 1e-6));
    });

    test('a peak at the border does not read outside the grid', () {
      final out = cornersOutput([(0, 0), (63, 0), (63, 63), (0, 63)]);
      final pts = decodeCorners(out);
      expect(pts[0].x, closeTo(2, 1e-9));
      expect(pts[2].x, closeTo(63.5 * 4, 1e-9));
    });
  });

  group('squares', () {
    Float32List probsFor(List<int> classes) {
      final probs = Float32List(64 * classCount);
      for (var i = 0; i < 64; i++) {
        probs[i * classCount + classes[i]] = 0.9;
        probs[i * classCount + (classes[i] + 1) % classCount] = 0.1;
      }
      return probs;
    }

    test('the start position as drawn gives the start FEN', () {
      final classes = List<int>.filled(64, 0);
      const back = [4, 2, 3, 5, 6, 3, 2, 4];
      for (var c = 0; c < 8; c++) {
        classes[c] = back[c] + 6;
        classes[8 + c] = 7;
        classes[48 + c] = 1;
        classes[56 + c] = back[c];
      }
      final probs = probsFor(classes);
      final decoded = squareClasses(probs);
      expect(placementFromClasses(decoded), 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR');
      final conf = squareConfidence(probs);
      expect(conf.every((v) => (v - 0.9).abs() < 1e-6), isTrue);
    });

    test('empty squares are run-length encoded', () {
      final classes = List<int>.filled(64, 0);
      classes[4] = 12; // e8
      classes[60] = 6; // e1
      classes[27] = 1; // d5
      expect(
        placementFromClasses(Uint8List.fromList(classes)),
        '4k3/8/8/3P4/8/8/8/4K3',
      );
    });
  });
}
