import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'model_tensor_info.dart';

/// Creates a tf.tensor from data, optional shape, and optional type.
@staticInterop
@JS('tf.tensor')
external JSTensor _createTensor(JSAny data, JSAny? shape, JSAny? type);

/// Converts Dart typed data to the appropriate JS type for tensor creation.
JSAny convertDartDataToJs(Object data) {
  if (data is Float32List) return data.toJS;
  if (data is Float64List) return data.toJS;
  if (data is Int32List) return data.toJS;
  if (data is String) return data.toJS;
  return data.jsify()!;
}

/// JS interop binding for a TensorFlow.js Tensor object.
@staticInterop
@JS('tf.Tensor')
class JSTensor {
  factory JSTensor(Object data, {List<int>? shape, TFLiteDataType? type}) {
    return _createTensor(
      convertDartDataToJs(data),
      shape?.jsify(),
      type?.name.toJS,
    );
  }
}

extension JSTensorExtensions on JSTensor {
  /// Synchronously reads tensor data back to Dart.
  T dataSync<T>() => _dataSync().dartify() as T;

  /// Synchronously reads tensor data as a [Float32List] without going through
  /// the slow `dartify()` path. Zero-copy on dart2js for typed-array tensors.
  Float32List dataSyncFloat32() {
    final JSAny raw = _dataSync();
    if (raw.isA<JSFloat32Array>()) {
      return (raw as JSFloat32Array).toDart;
    }
    // Fallback: legacy path via dartify.
    return Float32List.fromList((raw.dartify() as List).cast<double>());
  }

  String get dtype => _dtype.toDart;

  int get id => _id.toDartInt;

  bool get isDisposed => _isDisposed.toDart;

  List<int> get strides {
    final jsStrides = _strides;
    return List<int>.generate(
      jsStrides.length,
      (i) => jsStrides[i].toDartInt,
      growable: false,
    );
  }

  int get size => _size.toDartInt;

  @JS('dtype')
  external JSString get _dtype;

  @JS('id')
  external JSNumber get _id;

  @JS('isDisposed')
  external JSBoolean get _isDisposed;

  @JS('strides')
  external JSArray<JSNumber> get _strides;

  @JS('size')
  external JSNumber get _size;

  @JS('dataSync')
  external JSAny _dataSync();

  @JS('data')
  external JSPromise _data();

  external void dispose();

  /// Asynchronously reads tensor data.
  Future<T> dataAsync<T>() async {
    final output = await _data().toDart;
    return output.dartify() as T;
  }
}

/// JS interop binding for a NamedTensorMap (used for multi-output models).
@staticInterop
@JS('Map')
class NamedTensorMap {
  external factory NamedTensorMap();
}

extension NamedTensorMapExtensions on NamedTensorMap {
  dynamic operator [](String name) => (this as JSObject).getProperty(name.toJS);

  void operator []=(String name, Object value) {
    // ignore: invalid_runtime_check_with_js_interop_types
    if (value is JSTensor) {
      (this as JSObject).setProperty(name.toJS, value as JSAny);
      return;
    }
    (this as JSObject).setProperty(name.toJS, value.jsify());
  }

  T get<T>(String name) {
    // ignore: invalid_runtime_check_with_js_interop_types
    return (this as JSObject).getProperty(name.toJS) as T;
  }
}
