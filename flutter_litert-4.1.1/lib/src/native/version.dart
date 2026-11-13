import 'package:ffi/ffi.dart';
import 'package:flutter_litert/src/bindings/bindings.dart';

/// Returns the LiteRT native library version string.
String get version {
  final versionPointer = tfliteBinding.TfLiteVersion();
  return versionPointer.cast<Utf8>().toDartString();
}
