import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'geometry.dart';
import 'gray_image.dart';
import 'pipeline.dart';

/// Longest side kept when a page is decoded, to bound memory.
const int maxPageSide = 3200;

/// Size of the diagram crop saved with each puzzle.
const int cropSize = 512;

/// Something to scan: an encoded image (JPEG, PNG, ...) or raw BGRA pixels.
sealed class ScanInput {
  const ScanInput();
}

class EncodedInput extends ScanInput {
  const EncodedInput(this.bytes);
  final Uint8List bytes;
}

class BgraInput extends ScanInput {
  const BgraInput(this.width, this.height, this.pixels);
  final int width;
  final int height;
  final Uint8List pixels;
}

/// One board as read by the models. Plain data, so it can cross isolates.
class RawBoard {
  RawBoard({
    required this.corners,
    required this.probs,
    required this.cropPng,
    this.score,
  });

  /// TL.x, TL.y, TR.x, TR.y, BR.x, BR.y, BL.x, BL.y in page pixels.
  final Float64List corners;

  /// 64 squares x 13 classes, as drawn.
  final Float32List probs;

  /// PNG of the board, [cropSize] pixels square.
  final Uint8List cropPng;

  final double? score;

  Quad get quad => Quad.fromList(corners);
}

/// A scanned page: its normalised image and the boards on it.
class PageAnalysis {
  PageAnalysis({
    required this.width,
    required this.height,
    required this.jpeg,
    required this.boards,
  });

  final int width;
  final int height;

  /// The page with orientation applied, as JPEG. All later requests refer to
  /// this image, so its pixel coordinates match the boards.
  final Uint8List jpeg;

  final List<RawBoard> boards;
}

/// Thrown with a message that is fit to show to the user.
class ScanException implements Exception {
  const ScanException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Decodes pages and runs the recognition pipeline on them. Runs on whichever
/// isolate it is created on; the app creates it on a worker isolate.
class ScanEngine {
  ScanEngine(this.pipeline);

  final RecognitionPipeline pipeline;

  int? _cachedKey;
  GrayImage? _cachedGray;

  /// Decodes [input], finds every board and reads it. [key] identifies the
  /// page for later [readQuad] and [readRegion] calls.
  PageAnalysis analyze(int key, ScanInput input, {double threshold = 0.35}) {
    final image = _decode(input);
    final gray = grayFromImage(image);
    _cachedKey = key;
    _cachedGray = gray;
    final jpeg = _encodePage(image);
    final boards = [
      for (final d in pipeline.detect(gray, threshold: threshold))
        _raw(gray, pipeline.readDetection(gray, d)),
    ];
    return PageAnalysis(
      width: gray.width,
      height: gray.height,
      jpeg: jpeg,
      boards: boards,
    );
  }

  /// Reads the board inside [quad], whose corners the user has set.
  RawBoard readQuad(int key, Uint8List jpeg, Quad quad) {
    final gray = _grayFor(key, jpeg);
    return _raw(gray, pipeline.readQuad(gray, quad));
  }

  /// Finds and reads the board inside the rectangle [region].
  RawBoard readRegion(int key, Uint8List jpeg, Quad region) {
    final gray = _grayFor(key, jpeg);
    return _raw(gray, pipeline.readRegion(gray, region));
  }

  GrayImage _grayFor(int key, Uint8List jpeg) {
    if (_cachedKey == key && _cachedGray != null) return _cachedGray!;
    final image = img.decodeJpg(jpeg);
    if (image == null) {
      throw const ScanException('The page image could not be read.');
    }
    final gray = grayFromImage(image);
    _cachedKey = key;
    _cachedGray = gray;
    return gray;
  }

  RawBoard _raw(GrayImage gray, BoardProbs read) => RawBoard(
        corners: Float64List.fromList(read.quad.toList()),
        probs: read.probs,
        cropPng: encodeCrop(gray, read.quad),
        score: read.score,
      );

  img.Image _decode(ScanInput input) {
    switch (input) {
      case EncodedInput(:final bytes):
        final decoded = img.decodeImage(bytes);
        if (decoded == null) {
          throw const ScanException(
            'This image could not be read. Try a JPEG or PNG.',
          );
        }
        return _limit(img.bakeOrientation(decoded));
      case BgraInput(:final width, :final height, :final pixels):
        final rgb = Uint8List(width * height * 3);
        for (var i = 0, j = 0, k = 0; i < width * height; i++, j += 4, k += 3) {
          rgb[k] = pixels[j + 2];
          rgb[k + 1] = pixels[j + 1];
          rgb[k + 2] = pixels[j];
        }
        return _limit(
          img.Image.fromBytes(
            width: width,
            height: height,
            bytes: rgb.buffer,
            numChannels: 3,
          ),
        );
    }
  }

  img.Image _limit(img.Image image) {
    final longest = math.max(image.width, image.height);
    if (longest <= maxPageSide) return image;
    final f = maxPageSide / longest;
    return img.copyResize(
      image,
      width: (image.width * f).round(),
      height: (image.height * f).round(),
      interpolation: img.Interpolation.average,
    );
  }

  Uint8List _encodePage(img.Image image) {
    final clean = img.Image.from(image)..exif = img.ExifData();
    return img.encodeJpg(clean, quality: 90);
  }
}

/// A square PNG of the board inside [quad], greyscale.
Uint8List encodeCrop(GrayImage gray, Quad quad, {int size = cropSize}) {
  final warp = warpRegion(gray, quad, size);
  final bytes = warp.image.toBytes();
  final image = img.Image.fromBytes(
    width: size,
    height: size,
    bytes: bytes.buffer,
    numChannels: 1,
  );
  return img.encodePng(image);
}
