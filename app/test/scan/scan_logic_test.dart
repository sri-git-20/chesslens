import 'dart:typed_data';

import 'package:chesslens/src/chess/board_utils.dart';
import 'package:chesslens/src/scan/board_reading.dart';
import 'package:chesslens/src/scan/geometry.dart';
import 'package:chesslens/src/scan/model_decode.dart';
import 'package:chesslens/src/scan/page_range.dart';
import 'package:chesslens/src/scan/reading_order.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';

/// Class ids (as drawn, row 0 first) of a placement string.
Uint8List classesOf(String placement) {
  const letters = 'PNBRQKpnbrqk';
  final out = Uint8List(64);
  var i = 0;
  for (final rank in placement.split('/')) {
    for (final ch in rank.split('')) {
      final n = int.tryParse(ch);
      if (n != null) {
        i += n;
      } else {
        out[i++] = letters.indexOf(ch) + 1;
      }
    }
  }
  return out;
}

/// One-hot-ish probabilities: [top] for the class, the rest on [second].
Float32List probsOf(Uint8List classes, {double top = 0.95}) {
  final probs = Float32List(64 * classCount);
  for (var i = 0; i < 64; i++) {
    final second = classes[i] == 0 ? 1 : 0;
    probs[i * classCount + classes[i]] = top;
    probs[i * classCount + second] = 1 - top;
  }
  return probs;
}

Uint8List rotated(Uint8List classes) =>
    Uint8List.fromList([for (var i = 63; i >= 0; i--) classes[i]]);

Quad box(double l, double t, double r, double b) => Quad.fromRect(l, t, r, b);

void main() {
  group('reading order', () {
    test('a single column goes top to bottom', () {
      final quads = [box(10, 300, 110, 400), box(12, 10, 108, 110), box(8, 150, 112, 250)];
      expect(readingOrder(quads), [1, 2, 0]);
    });

    test('columns go left to right, each top to bottom', () {
      final quads = [
        box(210, 10, 310, 110), // 0: right column, top
        box(10, 200, 110, 300), // 1: left column, bottom
        box(10, 10, 110, 110), //  2: left column, top
        box(212, 200, 312, 300), // 3: right column, bottom
      ];
      expect(readingOrder(quads), [2, 1, 0, 3]);
    });

    test('slightly misaligned boards of one column stay together', () {
      final quads = [box(100, 400, 300, 600), box(130, 100, 330, 300), box(60, 700, 250, 900)];
      expect(readingOrder(quads), [1, 0, 2]);
    });

    test('an empty page gives an empty order', () {
      expect(readingOrder([]), isEmpty);
    });
  });

  group('range', () {
    test('parses numbers and ranges', () {
      final r = parseRange('3-7, 9', 12);
      expect(r.isValid, isTrue);
      expect(r.numbers, {3, 4, 5, 6, 7, 9});
    });

    test('accepts spaces around the dash and semicolons', () {
      expect(parseRange('1 - 3; 5', 5).numbers, {1, 2, 3, 5});
    });

    test('a single number works', () {
      expect(parseRange('4', 4).numbers, {4});
    });

    test('rejects numbers out of range, empty text and nonsense', () {
      expect(parseRange('0-2', 5).isValid, isFalse);
      expect(parseRange('3-9', 5).error, 'Numbers go from 1 to 5.');
      expect(parseRange('', 5).isValid, isFalse);
      expect(parseRange('a-b', 5).isValid, isFalse);
      expect(parseRange('7-3', 9).error, contains('backwards'));
    });
  });

  group('orientation', () {
    test('the start position with White at the bottom stays', () {
      expect(blackAtBottom(classesOf(startPlacement)), isFalse);
    });

    test('the start position turned around is detected', () {
      expect(blackAtBottom(rotated(classesOf(startPlacement))), isTrue);
    });

    test('kings alone decide when they stand on their home side', () {
      // White king at the top, black king at the bottom.
      expect(blackAtBottom(classesOf('4K3/8/8/8/8/8/8/4k3')), isTrue);
      expect(blackAtBottom(classesOf('4k3/8/8/8/8/8/8/4K3')), isFalse);
    });

    test('a few advanced pawns do not flip the board', () {
      expect(blackAtBottom(classesOf('8/4k3/8/3P4/8/8/8/4K3')), isFalse);
      expect(blackAtBottom(classesOf('4k3/3P4/8/8/8/8/8/4K3')), isFalse);
    });

    test('an empty board is not flipped', () {
      expect(blackAtBottom(classesOf(emptyPlacement)), isFalse);
    });
  });

  group('interpretBoard', () {
    test('keeps a White-at-bottom board and its confidence order', () {
      final reading = interpretBoard(probsOf(classesOf(startPlacement)));
      expect(reading.placement, startPlacement);
      expect(reading.orientation, Side.white);
      expect(reading.isLegal, isTrue);
      expect(reading.repaired, isEmpty);
      expect(reading.confidence, hasLength(64));
      expect(reading.confidence.every((c) => (c - 0.95).abs() < 1e-6), isTrue);
    });

    test('rotates a Black-at-bottom board so the FEN is correct', () {
      final classes = rotated(classesOf(startPlacement));
      final probs = probsOf(classes);
      // Make the drawn top-left square (a1 for White) the least sure one.
      probs[0 * classCount + classes[0]] = 0.6;
      final reading = interpretBoard(probs);
      expect(reading.placement, startPlacement);
      expect(reading.orientation, Side.black);
      // Drawn square 0 is FEN square 63 (h1).
      expect(reading.confidence[63], closeTo(0.6, 1e-6));
      expect(reading.confidence[0], closeTo(0.95, 1e-6));
    });
  });

  group('legality repair', () {
    test('a legal position is returned as is', () {
      final probs = probsOf(classesOf('4k3/8/8/8/8/8/8/4K3'));
      final result = repairPosition(probs);
      expect(result.changed, isEmpty);
      expect(placementFromClasses(result.classes), '4k3/8/8/8/8/8/8/4K3');
    });

    test('a doubtful extra king becomes its second guess', () {
      final classes = classesOf('4k3/8/8/8/8/8/8/4K3');
      classes[27] = 12; // a second black king on d5
      final probs = probsOf(classes);
      // Square 27: black king 0.5, empty 0.45.
      for (var c = 0; c < classCount; c++) {
        probs[27 * classCount + c] = 0;
      }
      probs[27 * classCount + 12] = 0.5;
      probs[27 * classCount + 0] = 0.45;
      final result = repairPosition(probs);
      expect(result.changed, [27]);
      expect(placementFromClasses(result.classes), '4k3/8/8/8/8/8/8/4K3');
    });

    test('interpretBoard lowers the confidence of a repaired square', () {
      final classes = classesOf('4k3/8/8/8/8/8/8/4K3');
      classes[27] = 12;
      final probs = probsOf(classes);
      for (var c = 0; c < classCount; c++) {
        probs[27 * classCount + c] = 0;
      }
      probs[27 * classCount + 12] = 0.5;
      probs[27 * classCount + 0] = 0.45;
      final reading = interpretBoard(probs);
      expect(reading.isLegal, isTrue);
      expect(reading.repaired, [27]);
      expect(reading.confidence[27], closeTo(0.45, 1e-6));
    });

    test('an unfixable position is returned unchanged', () {
      // No kings at all, and nothing likely to fix it.
      final probs = probsOf(classesOf('8/8/8/3P4/8/8/8/8'), top: 0.99);
      final result = repairPosition(probs);
      expect(result.changed, isEmpty);
      expect(placementFromClasses(result.classes), '8/8/8/3P4/8/8/8/8');
      expect(interpretBoard(probs).isLegal, isFalse);
    });

    test('the search finds the cheapest of several fixes', () {
      // Two black kings: d5 (0.55 vs empty 0.40) and a2 (0.80 vs empty 0.15).
      final classes = classesOf('4k3/8/8/8/8/8/8/4K3');
      classes[27] = 12;
      classes[48] = 12;
      final probs = probsOf(classes);
      for (final s in [27, 48]) {
        for (var c = 0; c < classCount; c++) {
          probs[s * classCount + c] = 0;
        }
        probs[s * classCount + 12] = s == 27 ? 0.55 : 0.80;
        probs[s * classCount + 0] = s == 27 ? 0.40 : 0.15;
      }
      // Three black kings: the two doubtful ones must go.
      final result = repairPosition(probs);
      final placement = placementFromClasses(result.classes);
      expect(placement.split('k').length - 1, 1);
      expect(result.changed, isNotEmpty);
    });
  });
}
