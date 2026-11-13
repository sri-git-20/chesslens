import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'model_tensor_info.dart';
import 'tfjs_tensor.dart';

/// Checks whether the TFLite.js runtime has been loaded.
bool isTFLiteInitialized() {
  final tflite = globalContext['tflite'];
  if (!tflite.isA<JSObject>()) return false;
  return (tflite as JSObject).has('loadTFLiteModel');
}

/// Low-level JS binding for tflite.loadTFLiteModel().
@staticInterop
@JS('tflite.loadTFLiteModel')
external JSPromise<JSObject> _loadTFLiteModel(JSAny url);

@staticInterop
@JS('TFLiteModel')
class _JSTFLiteModel {}

extension _JSTFLiteModelExtensions on _JSTFLiteModel {
  @JS('inputs')
  external JSArray<JSAny> get _inputs;

  @JS('outputs')
  external JSArray<JSAny> get _outputs;

  external JSObject predict(JSAny inputs, JSAny? config);

  List<ModelTensorInfo> get inputs {
    final jsInputs = _inputs;
    return List<ModelTensorInfo>.generate(
      jsInputs.length,
      (i) => jsInputs[i] as ModelTensorInfo,
      growable: false,
    );
  }

  List<ModelTensorInfo> get outputs {
    final jsOutputs = _outputs;
    return List<ModelTensorInfo>.generate(
      jsOutputs.length,
      (i) => jsOutputs[i] as ModelTensorInfo,
      growable: false,
    );
  }
}

/// Dart wrapper around a loaded TFLite.js model.
class TFLiteModel {
  TFLiteModel._(this._model);

  final _JSTFLiteModel _model;

  /// Loads a TFLite model from a URL string.
  static Future<TFLiteModel> fromUrl(String url) => _load(url.toJS);

  /// Loads a TFLite model from in-memory bytes.
  static Future<TFLiteModel> fromMemory(List<int> data) {
    if (data is Uint8List) {
      return _load(data.toJS);
    }
    return _load(data.jsify()!);
  }

  /// Runs inference on the model.
  ///
  /// [inputs] must be a [JSTensor], [List<JSTensor>], or [NamedTensorMap].
  T predict<T>(Object inputs) {
    assert(
      // ignore: invalid_runtime_check_with_js_interop_types
      inputs is JSTensor ||
          inputs is List<JSTensor> ||
          // ignore: invalid_runtime_check_with_js_interop_types
          inputs is NamedTensorMap,
      'Input must be JSTensor or List<JSTensor> or NamedTensorMap',
    );

    final JSAny jsInput;
    if (inputs is List) {
      final arr = JSArray<JSAny>();
      for (final input in inputs) {
        arr.add(input as JSAny);
      }
      jsInput = arr;
    } else {
      jsInput = inputs as JSAny;
    }
    final output = _model.predict(jsInput, null);

    if (output.isA<JSArray<JSAny?>>()) {
      final arr = output as JSArray<JSAny?>;
      final outputs = List<JSTensor>.generate(
        arr.length,
        (i) => (arr[i] as JSTensor?)!,
        growable: false,
      );
      return outputs as T;
    }

    // ignore: invalid_runtime_check_with_js_interop_types
    return output as T;
  }

  /// Model input tensor metadata.
  List<ModelTensorInfo> get inputs => _model.inputs;

  /// Model output tensor metadata.
  List<ModelTensorInfo> get outputs => _model.outputs;
}

Future<TFLiteModel> _load(JSAny data) async {
  assert(isTFLiteInitialized(), 'TFLite.js must be initialized first');

  final promise = _loadTFLiteModel(data);
  final model = await promise.toDart;
  return TFLiteModel._(model as _JSTFLiteModel);
}
