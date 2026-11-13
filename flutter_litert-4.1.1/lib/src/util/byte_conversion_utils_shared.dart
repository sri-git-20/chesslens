import 'dart:convert';
import 'dart:typed_data';

import '../tensor_type.dart';
import 'list_shape_extension.dart';

/// Size of int32 in bytes (avoids dart:ffi dependency for web compatibility).
const int kInt32ByteSize = 4;

/// Error thrown when an input value cannot be converted to the expected tensor type.
class ByteConversionError extends ArgumentError {
  ByteConversionError({required this.input, required this.tensorType})
    : super(
        'The input element is ${input.runtimeType} while tensor data type is $tensorType',
      );

  final Object input;
  final Object tensorType;
}

/// Utilities for converting between Dart objects and raw tensor byte buffers.
class ByteConversionUtils {
  /// Converts a Dart object to its byte representation for the given [tensorType].
  static Uint8List convertObjectToBytes(Object o, TensorType tensorType) {
    if (o is Uint8List) {
      return o;
    }
    if (o is ByteBuffer) {
      return o.asUint8List();
    }
    // String tensors must be encoded as a single block (not element-by-element).
    if (tensorType == TensorType.string) {
      if (o is String) {
        return encodeTFStrings([o]);
      }
      if (o is List) {
        final strings = o.whereType<String>().toList();
        if (strings.length == o.length && o.isNotEmpty) {
          return encodeTFStrings(strings);
        }
        List<int> bytes = <int>[];
        for (var e in o) {
          bytes.addAll(convertObjectToBytes(e, tensorType));
        }
        return Uint8List.fromList(bytes);
      }
    }
    final typedBytes = _typedDataBytes(o, tensorType);
    if (typedBytes != null) {
      return typedBytes;
    }
    if (o is List) {
      return _convertListToBytes(o, tensorType);
    }
    return _convertElementToBytes(o, tensorType);
  }

  /// Zero-copy view of [o]'s backing bytes when its runtime type already
  /// matches the tensor's element type.
  static Uint8List? _typedDataBytes(Object o, TensorType tensorType) {
    if (tensorType == TensorType.float32) {
      if (o is Float32List) return _viewBytes(o);
      // Single-pass narrowing conversion instead of the element-wise path.
      if (o is Float64List) return _viewBytes(Float32List.fromList(o));
    }
    if (tensorType == TensorType.int32 && o is Int32List) return _viewBytes(o);
    if (tensorType == TensorType.int64 && o is Int64List) return _viewBytes(o);
    if (tensorType == TensorType.int16 && o is Int16List) return _viewBytes(o);
    if (tensorType == TensorType.int8 && o is Int8List) return _viewBytes(o);
    return null;
  }

  static Uint8List _viewBytes(TypedData data) =>
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  /// Converts a (possibly nested) list by counting leaf elements once and
  /// filling a single pre-sized buffer, instead of allocating a small byte
  /// buffer per element.
  static Uint8List _convertListToBytes(List o, TensorType tensorType) {
    final count = _countLeafElements(o);
    if (count == 0) return Uint8List(0);
    final elementSize = _elementByteSize(tensorType);
    if (elementSize == null) {
      throw ArgumentError(
        'The input data tfliteType ${_firstLeaf(o).runtimeType} is unsupported',
      );
    }
    final data = ByteData(count * elementSize);
    _fillLeafBytes(o, data, 0, tensorType);
    return data.buffer.asUint8List();
  }

  static int _countLeafElements(List list) {
    var count = 0;
    for (final e in list) {
      if (e is List) {
        count += _countLeafElements(e);
      } else {
        count++;
      }
    }
    return count;
  }

  static Object? _firstLeaf(List list) {
    Object? node = list;
    while (node is List && node.isNotEmpty) {
      node = node.first;
    }
    return node;
  }

  static int? _elementByteSize(TensorType tensorType) {
    if (tensorType == TensorType.float32) return 4;
    if (tensorType == TensorType.int32) return 4;
    if (tensorType == TensorType.int64) return 8;
    if (tensorType == TensorType.int16) return 2;
    if (tensorType == TensorType.float16) return 2;
    if (tensorType == TensorType.int8) return 1;
    if (tensorType == TensorType.uint8) return 1;
    return null;
  }

  static int _fillLeafBytes(
    List list,
    ByteData data,
    int offset,
    TensorType tensorType,
  ) {
    for (final e in list) {
      if (e is List) {
        offset = _fillLeafBytes(e, data, offset, tensorType);
      } else {
        offset = _writeElement(data, offset, e, tensorType);
      }
    }
    return offset;
  }

  static int _writeElement(
    ByteData data,
    int offset,
    Object? e,
    TensorType tensorType,
  ) {
    if (tensorType == TensorType.float32) {
      if (e is num) {
        data.setFloat32(offset, e.toDouble(), Endian.little);
        return offset + 4;
      }
      throw ByteConversionError(input: e as Object, tensorType: tensorType);
    }
    if (tensorType == TensorType.int32) {
      if (e is int) {
        data.setInt32(offset, e, Endian.little);
        return offset + 4;
      }
      throw ByteConversionError(input: e as Object, tensorType: tensorType);
    }
    if (tensorType == TensorType.int64) {
      if (e is int) {
        data.setInt64(offset, e, Endian.little);
        return offset + 8;
      }
      throw ByteConversionError(input: e as Object, tensorType: tensorType);
    }
    if (tensorType == TensorType.int16) {
      if (e is int) {
        data.setInt16(offset, e, Endian.little);
        return offset + 2;
      }
      throw ByteConversionError(input: e as Object, tensorType: tensorType);
    }
    if (tensorType == TensorType.float16) {
      if (e is num) {
        data.setUint16(offset, float32ToFloat16(e.toDouble()), Endian.little);
        return offset + 2;
      }
      throw ByteConversionError(input: e as Object, tensorType: tensorType);
    }
    if (tensorType == TensorType.int8) {
      if (e is int) {
        data.setInt8(offset, e);
        return offset + 1;
      }
      throw ByteConversionError(input: e as Object, tensorType: tensorType);
    }
    if (tensorType == TensorType.uint8) {
      if (e is int) {
        data.setUint8(offset, e);
        return offset + 1;
      }
      throw ByteConversionError(input: e as Object, tensorType: tensorType);
    }
    throw ArgumentError(
      'The input data tfliteType ${e.runtimeType} is unsupported',
    );
  }

  static Uint8List _convertElementToBytes(Object o, TensorType tensorType) {
    if (tensorType == TensorType.float32) {
      if (o is num) {
        var buffer = Uint8List(4).buffer;
        var bdata = ByteData.view(buffer);
        bdata.setFloat32(0, o.toDouble(), Endian.little);
        return buffer.asUint8List();
      }
      throw ByteConversionError(input: o, tensorType: tensorType);
    }

    if (tensorType == TensorType.uint8) {
      if (o is int) {
        var buffer = Uint8List(1).buffer;
        var bdata = ByteData.view(buffer);
        bdata.setUint8(0, o);
        return buffer.asUint8List();
      }
      throw ByteConversionError(input: o, tensorType: tensorType);
    }

    if (tensorType == TensorType.int32) {
      if (o is int) {
        var buffer = Uint8List(4).buffer;
        var bdata = ByteData.view(buffer);
        bdata.setInt32(0, o, Endian.little);
        return buffer.asUint8List();
      }
      throw ByteConversionError(input: o, tensorType: tensorType);
    }

    if (tensorType == TensorType.int64) {
      if (o is int) {
        var buffer = Uint8List(8).buffer;
        var bdata = ByteData.view(buffer);
        bdata.setInt64(0, o, Endian.little);
        return buffer.asUint8List();
      }
      throw ByteConversionError(input: o, tensorType: tensorType);
    }

    if (tensorType == TensorType.int16) {
      if (o is int) {
        var buffer = Uint8List(2).buffer;
        var bdata = ByteData.view(buffer);
        bdata.setInt16(0, o, Endian.little);
        return buffer.asUint8List();
      }
      throw ByteConversionError(input: o, tensorType: tensorType);
    }

    if (tensorType == TensorType.float16) {
      if (o is num) {
        return floatToFloat16Bytes(o.toDouble());
      }
      throw ByteConversionError(input: o, tensorType: tensorType);
    }

    if (tensorType == TensorType.int8) {
      if (o is int) {
        var buffer = Uint8List(1).buffer;
        var bdata = ByteData.view(buffer);
        bdata.setInt8(0, o);
        return buffer.asUint8List();
      }
      throw ByteConversionError(input: o, tensorType: tensorType);
    }

    if (tensorType == TensorType.string) {
      if (o is String) {
        return encodeTFStrings([o]);
      }
      throw ByteConversionError(input: o, tensorType: tensorType);
    }

    throw ArgumentError(
      'The input data tfliteType ${o.runtimeType} is unsupported',
    );
  }

  /// Decodes a TensorFlow string tensor to a `List<String>`.
  static List<String> decodeTFStrings(Uint8List bytes) =>
      _decodeTFStrings(bytes);

  /// Encodes a list of Dart strings into the TFLite string tensor binary format.
  ///
  /// Binary layout (all integers are little-endian int32):
  /// ```
  /// [numStrings]
  /// [offset_0]       // byte offset where string 0 data begins
  /// [offset_1]       // byte offset where string 1 data begins
  /// ...
  /// [offset_N]       // total buffer length (sentinel for last string end)
  /// [UTF-8 bytes for all strings, concatenated]
  /// ```
  ///
  /// This is the inverse of [decodeTFStrings].
  static Uint8List encodeTFStrings(List<String> strings) =>
      _encodeTFStrings(strings);

  /// Converts raw tensor bytes back to a Dart object with the given [shape] and [tensorType].
  ///
  /// The returned object never aliases [bytes]: reshape boxes every element
  /// into new lists, so callers may pass views over volatile native memory.
  static Object convertBytesToObject(
    Uint8List bytes,
    TensorType tensorType,
    List<int> shape,
  ) {
    if (tensorType == TensorType.int32) {
      final b = _aligned(bytes, 4);
      return b.buffer
          .asInt32List(b.offsetInBytes, b.lengthInBytes ~/ 4)
          .reshape<int>(shape);
    } else if (tensorType == TensorType.float32) {
      final b = _aligned(bytes, 4);
      return b.buffer
          .asFloat32List(b.offsetInBytes, b.lengthInBytes ~/ 4)
          .reshape<double>(shape);
    } else if (tensorType == TensorType.int16) {
      final b = _aligned(bytes, 2);
      return b.buffer
          .asInt16List(b.offsetInBytes, b.lengthInBytes ~/ 2)
          .reshape<int>(shape);
    } else if (tensorType == TensorType.float16) {
      final data = ByteData.sublistView(bytes);
      final list = List<double>.filled(bytes.length ~/ 2, 0);
      for (var i = 0; i < list.length; i++) {
        list[i] = float16ToFloat32(data.getUint16(i * 2, Endian.little));
      }
      return list.reshape<double>(shape);
    } else if (tensorType == TensorType.int8) {
      return bytes.buffer
          .asInt8List(bytes.offsetInBytes, bytes.lengthInBytes)
          .reshape<int>(shape);
    } else if (tensorType == TensorType.uint8) {
      return bytes.reshape<int>(shape);
    } else if (tensorType == TensorType.int64) {
      final b = _aligned(bytes, 8);
      return b.buffer
          .asInt64List(b.offsetInBytes, b.lengthInBytes ~/ 8)
          .reshape<int>(shape);
    } else if (tensorType == TensorType.string) {
      return <dynamic>[decodeTFStrings(bytes)];
    }
    throw UnsupportedError("$tensorType is not Supported.");
  }

  /// Returns [bytes] if its view offset satisfies [alignment], else a copy.
  static Uint8List _aligned(Uint8List bytes, int alignment) =>
      bytes.offsetInBytes % alignment == 0 ? bytes : Uint8List.fromList(bytes);

  /// Converts a float64 [value] to its float16 byte representation.
  static Uint8List floatToFloat16Bytes(double value) =>
      _floatToFloat16Bytes(value);

  /// Converts float16 [bytes] to a float64 value via float32.
  static double bytesToFloat32(Uint8List bytes) => _bytesToFloat32(bytes);
}

/// Converts a float32 to float16 representation (as int).
int float32ToFloat16(double value) {
  final Float32List float32Buffer = Float32List(1);
  final Uint32List int32Buffer = float32Buffer.buffer.asUint32List();

  float32Buffer[0] = value;
  int f = int32Buffer[0];
  int sign = (f >> 16) & 0x8000;
  int exponent = (f >> 23) & 0xFF;
  int mantissa = f & 0x007FFFFF;

  if (exponent == 0) return sign;
  if (exponent == 255) return sign | 0x7C00;

  exponent = exponent - 127 + 15;
  if (exponent >= 31) return sign | 0x7C00;
  if (exponent <= 0) return sign;

  int roundMantissa = (mantissa >> 13) + ((mantissa >> 12) & 1);

  return sign | (exponent << 10) | roundMantissa;
}

/// Converts a float16 (as int) to float32.
double float16ToFloat32(int value) {
  final Float32List float32Buffer = Float32List(1);
  final Uint32List int32Buffer = float32Buffer.buffer.asUint32List();

  int sign = (value & 0x8000) << 16;
  int exponent = (value & 0x7C00) >> 10;
  int mantissa = (value & 0x03FF) << 13;

  if (exponent == 0) {
    if (mantissa == 0) return sign == 0 ? 0.0 : -0.0;
    while ((mantissa & 0x00800000) == 0) {
      mantissa <<= 1;
      exponent -= 1;
    }
    exponent += 1;
  } else if (exponent == 31) {
    if (mantissa == 0) {
      return sign == 0 ? double.infinity : double.negativeInfinity;
    }
    return double.nan;
  }

  exponent = exponent - 15 + 127;
  int32Buffer[0] = sign | (exponent << 23) | mantissa;

  return float32Buffer[0];
}

// ---------------------------------------------------------------------------
// Private implementations
// ---------------------------------------------------------------------------

Uint8List _floatToFloat16Bytes(double value) {
  int float16 = float32ToFloat16(value);
  final ByteData byteDataBuffer = ByteData(2)
    ..setUint16(0, float16, Endian.little);
  return Uint8List.fromList(byteDataBuffer.buffer.asUint8List());
}

double _bytesToFloat32(Uint8List bytes) {
  final ByteData byteDataBuffer = ByteData.view(
    bytes.buffer,
    bytes.offsetInBytes,
    2,
  );
  int float16 = byteDataBuffer.getUint16(0, Endian.little);
  return float16ToFloat32(float16);
}

List<String> _decodeTFStrings(Uint8List bytes) {
  List<String> decodedStrings = [];

  int numStrings = ByteData.view(
    bytes.sublist(0, kInt32ByteSize).buffer,
  ).getInt32(0, Endian.little);

  for (int s = 0; s < numStrings; s++) {
    int startIdx = ByteData.view(
      bytes.sublist((1 + s) * kInt32ByteSize, (2 + s) * kInt32ByteSize).buffer,
    ).getInt32(0, Endian.little);
    int endIdx = ByteData.view(
      bytes.sublist((2 + s) * kInt32ByteSize, (3 + s) * kInt32ByteSize).buffer,
    ).getInt32(0, Endian.little);

    decodedStrings.add(utf8.decode(bytes.sublist(startIdx, endIdx)));
  }

  return decodedStrings;
}

Uint8List _encodeTFStrings(List<String> strings) {
  final encodedStrings = strings.map((s) => utf8.encode(s)).toList();
  final int numStrings = strings.length;

  final int headerSize = (numStrings + 2) * kInt32ByteSize;
  final int dataSize = encodedStrings.fold<int>(0, (sum, e) => sum + e.length);
  final int totalSize = headerSize + dataSize;

  final buffer = Uint8List(totalSize);
  final byteData = ByteData.view(buffer.buffer);

  byteData.setInt32(0, numStrings, Endian.little);

  int dataOffset = headerSize;
  for (int i = 0; i < numStrings; i++) {
    byteData.setInt32((1 + i) * kInt32ByteSize, dataOffset, Endian.little);
    buffer.setRange(
      dataOffset,
      dataOffset + encodedStrings[i].length,
      encodedStrings[i],
    );
    dataOffset += encodedStrings[i].length;
  }

  byteData.setInt32(
    (1 + numStrings) * kInt32ByteSize,
    dataOffset,
    Endian.little,
  );

  return buffer;
}
