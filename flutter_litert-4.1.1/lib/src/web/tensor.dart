import 'dart:typed_data';

import '../quantization_params.dart';
import '../tensor_type.dart';
import '../util/byte_conversion_utils_web.dart';
import '../util/list_utils.dart' as list_utils;
import '../util/tensor_shape_utils.dart' as shape_utils;

export '../tensor_type.dart';

/// Web implementation of Tensor.
///
/// On web, tensors are lightweight data containers rather than FFI pointer
/// wrappers. They hold tensor metadata (name, shape, type) and optionally
/// a data buffer.
class Tensor {
  final String _name;
  final TensorType _type;
  final List<int> _shape;
  Uint8List _data;

  /// Creates a tensor from metadata (name, type, and shape).
  Tensor.fromMetadata({
    required String name,
    required TensorType type,
    required List<int> shape,
  }) : _name = name,
       _type = type,
       _shape = shape,
       _data = Uint8List(_computeByteSize(type, shape));

  /// Creates a Tensor compatible with the native constructor signature.
  /// On web this is only used internally.
  Tensor(dynamic tensor)
    : _name = '',
      _type = TensorType.float32,
      _shape = [],
      _data = Uint8List(0);

  /// Name of the tensor element.
  String get name => _name;

  /// Data type of the tensor element.
  TensorType get type => _type;

  /// Dimensions of the tensor.
  List<int> get shape => _shape;

  /// Underlying data buffer as bytes.
  Uint8List get data => _data.asUnmodifiableView();

  /// Aliasing native tensor memory is not possible on web; tensors are
  /// Dart-side buffers that the engine copies from. Use [data] instead.
  Float32List asFloat32View() => throw UnsupportedError(
    'Tensor.asFloat32View is not supported on web; use Tensor.data.',
  );

  /// Quantization params (not available on web).
  QuantizationParams get params => QuantizationParams(1.0, 0);

  /// Updates the underlying data buffer.
  set data(Uint8List bytes) {
    _data = bytes;
  }

  /// Returns number of dimensions.
  int numDimensions() => _shape.length;

  /// Returns the size, in bytes, of the tensor data.
  int numBytes() => _data.length;

  /// Returns the number of elements in a flattened (1-D) view of the tensor.
  int numElements() => shape_utils.computeNumElements(_shape);

  /// Copies the given data into this tensor.
  void setTo(Object src) {
    _data = ByteConversionUtils.convertObjectToBytes(src, _type);
  }

  /// Copies this tensor's data into the destination.
  Object copyTo(Object dst) {
    Object obj;
    if (dst is Uint8List) {
      obj = _data;
    } else if (dst is ByteBuffer) {
      ByteData bdata = dst.asByteData();
      for (int i = 0; i < bdata.lengthInBytes; i++) {
        bdata.setUint8(i, _data[i]);
      }
      obj = bdata.buffer;
    } else {
      obj = ByteConversionUtils.convertBytesToObject(_data, _type, _shape);
    }
    if (obj is List && dst is List) {
      list_utils.duplicateList(obj, dst);
    } else {
      dst = obj;
    }
    return obj;
  }

  /// Returns the input shape if it differs from this tensor's shape.
  List<int>? getInputShapeIfDifferent(Object? input) =>
      list_utils.getInputShapeIfDifferent(input, _shape);

  @override
  String toString() =>
      'Tensor{name: $_name, type: $_type, shape: $_shape, data: ${_data.length}}';
}

/// Computes the byte size for a given tensor type and shape.
int _computeByteSize(TensorType type, List<int> shape) {
  int numElements = 1;
  for (final dim in shape) {
    numElements *= dim;
  }
  switch (type) {
    case TensorType.float32:
    case TensorType.int32:
      return numElements * 4;
    case TensorType.float64:
    case TensorType.int64:
      return numElements * 8;
    case TensorType.float16:
    case TensorType.int16:
    case TensorType.uint16:
      return numElements * 2;
    case TensorType.int8:
    case TensorType.uint8:
      return numElements;
    default:
      return numElements * 4;
  }
}
