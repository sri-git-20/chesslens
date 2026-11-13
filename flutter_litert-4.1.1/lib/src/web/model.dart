import 'dart:typed_data';

import 'js_interop/tflite_js.dart';

/// Web implementation of Model.
///
/// Wraps a TFLiteModel loaded via TFLite.js WASM runtime.
class Model {
  final TFLiteModel _model;

  Model._(this._model);

  /// Returns the underlying TFLiteModel.
  TFLiteModel get base => _model;

  /// Not supported on web, use `Interpreter.fromBytes` or
  /// `Interpreter.fromAsset`.
  factory Model.fromFile(String path) => throw UnsupportedError(
    'Model.fromFile is not supported on web. Use Interpreter.fromAsset instead.',
  );

  /// Loads model from a buffer.
  static Future<Model> fromBuffer(Uint8List buffer) async {
    final model = await TFLiteModel.fromMemory(buffer);
    return Model._(model);
  }

  /// No-op on web (JS GC handles cleanup).
  void delete() {}
}
