import 'dart:js_interop';

/// Data types supported by TFLite.js tensors.
enum TFLiteDataType {
  float32,
  int32,
  bool,
  complex64,
  string;

  const TFLiteDataType();

  factory TFLiteDataType.fromName(String name) {
    for (final value in TFLiteDataType.values) {
      if (value.name == name) {
        return value;
      }
    }
    throw ArgumentError('Unknown TFLite data type: $name');
  }
}

/// JS interop binding for TFLite model tensor metadata.
@staticInterop
@JS('ModelTensorInfo')
class ModelTensorInfo {}

extension ModelTensorInfoExtensions on ModelTensorInfo {
  String get name => _name.toDart;

  List<int>? get shape {
    final jsInputs = _shape;
    if (jsInputs == null) {
      return null;
    }
    return List<int>.generate(
      jsInputs.length,
      (i) => jsInputs[i].toDartInt,
      growable: false,
    );
  }

  TFLiteDataType get dataType => TFLiteDataType.fromName(_dtype.toDart);

  String get dtype => _dtype.toDart;

  @JS('name')
  external JSString get _name;

  @JS('shape')
  external JSArray<JSNumber>? get _shape;

  @JS('dtype')
  external JSString get _dtype;
}
