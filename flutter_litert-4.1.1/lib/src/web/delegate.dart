/// Web implementation of Delegate.
///
/// On web, native-style delegates are no-ops for the tflite-js `Interpreter`.
/// Use `LiteRtInterpreter` when you need the LiteRT.js WebGPU path.
abstract class Delegate {
  /// On web, returns null (no FFI pointer).
  dynamic get base => null;

  /// No-op on web.
  void delete() {}
}
