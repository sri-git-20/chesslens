import 'js_interop/script_loader.dart';
import 'js_interop/tflite_js.dart';

const _cdnBaseUrl =
    'https://cdn.jsdelivr.net/gh/hoomanmmd/tflite-js@v0.0.1-alpha.10';

/// Initializes the TFLite.js WASM runtime for web.
///
/// Must be called before creating any interpreter on web.
/// On native platforms, this is a no-op.
///
/// By default loads scripts from CDN. Pass custom URLs to load from
/// your own server (e.g., for offline support).
Future<void> initializeWeb({
  String? tfJsScriptUrl,
  List<String>? tfBackendScriptUrls,
  String? tfliteScriptUrl,
}) async {
  if (isTFLiteInitialized()) return;

  final coreUrl = tfJsScriptUrl ?? '$_cdnBaseUrl/tf-core.js';
  final backendUrls = tfBackendScriptUrls ?? ['$_cdnBaseUrl/tf-backend-cpu.js'];
  final tfliteUrl = tfliteScriptUrl ?? '$_cdnBaseUrl/tf-tflite.min.js';

  await loadScript([coreUrl, ...backendUrls, tfliteUrl]);
}
