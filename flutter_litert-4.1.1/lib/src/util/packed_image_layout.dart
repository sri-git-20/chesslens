import 'dart:typed_data';

/// Backend-neutral packed image formats used by camera frame decode plans.
///
/// These describe how bytes are laid out in memory. Image backends such as
/// OpenCV still decide which concrete Mat / bitmap / native buffer type to
/// construct from the layout.
enum PackedImageFormat {
  /// 8-bit BGRA, four bytes per pixel.
  bgra8888,

  /// 8-bit RGBA, four bytes per pixel.
  rgba8888,

  /// YUV420 NV12: Y plane followed by interleaved UV bytes.
  yuv420Nv12,

  /// YUV420 NV21: Y plane followed by interleaved VU bytes.
  yuv420Nv21,

  /// YUV420 I420: Y plane, then U plane, then V plane.
  yuv420I420,
}

/// A tightly packed source-buffer layout for image backend reconstruction.
///
/// For OpenCV, callers should allocate a Mat with [rows], [cols], and a type
/// matching [channels], then call [copyTo] into the Mat's byte buffer. This
/// avoids slower list-element reconstruction paths.
class PackedImageLayout {
  /// Source rows in the packed buffer.
  final int rows;

  /// Source columns in the packed buffer.
  final int cols;

  /// Bytes per pixel/sample column.
  final int channels;

  /// Semantic format of the packed bytes.
  final PackedImageFormat format;

  /// Creates a packed image layout.
  const PackedImageLayout({
    required this.rows,
    required this.cols,
    required this.channels,
    required this.format,
  });

  /// Expected byte length for a tightly packed source buffer.
  int get byteLength => rows * cols * channels;

  /// Copies [src] into [dst] after validating both match [byteLength].
  ///
  /// The destination is typically a backend-owned byte buffer such as
  /// `cv.Mat.data`.
  void copyTo(Uint8List dst, Uint8List src) {
    validate(src, name: 'src');
    if (dst.length != byteLength) {
      throw ArgumentError(
        'dst.length ${dst.length} does not match packed layout byteLength '
        '$byteLength ($rows x $cols x $channels, $format)',
      );
    }
    dst.setAll(0, src);
  }

  /// Validates that [bytes] matches [byteLength].
  void validate(Uint8List bytes, {String name = 'bytes'}) {
    if (bytes.length != byteLength) {
      throw ArgumentError(
        '$name.length ${bytes.length} does not match packed layout byteLength '
        '$byteLength ($rows x $cols x $channels, $format)',
      );
    }
  }
}
