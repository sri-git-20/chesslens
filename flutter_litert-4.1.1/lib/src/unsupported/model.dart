// Unsupported platform stub for Model.
//
// This file is used when compiling for platforms where neither dart:io
// nor dart:js_interop is available.

import 'dart:typed_data';

/// LiteRT model.
class Model {
  dynamic get base =>
      throw UnsupportedError('Model.base is not supported on this platform');

  /// Loads model from a file or throws if unsuccessful.
  factory Model.fromFile(String path) => throw UnsupportedError(
    'Model.fromFile is not supported on this platform',
  );

  /// Loads model from a buffer or throws if unsuccessful.
  factory Model.fromBuffer(Uint8List buffer) => throw UnsupportedError(
    'Model.fromBuffer is not supported on this platform',
  );

  /// Destroys the model instance.
  void delete() =>
      throw UnsupportedError('Model.delete is not supported on this platform');
}
