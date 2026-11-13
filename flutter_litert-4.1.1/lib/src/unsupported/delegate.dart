// Unsupported platform stub for Delegate.
//
// This file is used when compiling for platforms where neither dart:io
// nor dart:js_interop is available.

abstract class Delegate {
  /// Get pointer to TfLiteDelegate
  dynamic get base =>
      throw UnsupportedError('Delegate.base is not supported on this platform');

  /// Destroys delegate instance
  void delete() => throw UnsupportedError(
    'Delegate.delete is not supported on this platform',
  );
}
