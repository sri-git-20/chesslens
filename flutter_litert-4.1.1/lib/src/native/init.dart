/// No-op on native platforms. TFLite uses FFI directly.
Future<void> initializeWeb({
  String? tfJsScriptUrl,
  List<String>? tfBackendScriptUrls,
  String? tfliteScriptUrl,
}) async {
  // No-op: native platforms use dart:ffi, no JS runtime needed.
}
