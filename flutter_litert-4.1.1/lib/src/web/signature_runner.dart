// Web platform stub for SignatureRunner.
//
// On-device training via SignatureRunner is not supported in the TFLite.js
// web runtime. Use native platforms (Android, iOS, macOS, Linux, Windows)
// for training workloads.

import 'tensor.dart';

/// Web platform stub for [SignatureRunner].
///
/// On-device training is not supported on web. Use native platforms instead.
class SignatureRunner {
  SignatureRunner(dynamic runner)
    : assert(false, 'SignatureRunner is not supported on web.');

  int get inputCount => throw UnsupportedError(
    'SignatureRunner is not supported on web. '
    'Use native platforms for on-device training.',
  );

  String getInputName(int index) =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  List<String> get inputNames =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  Tensor getInputTensor(String name) =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  List<Tensor> getInputTensors() =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  void resizeInputTensor(String name, List<int> shape) =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  void allocateTensors() =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  void invoke() =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  bool cancel() =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  int get outputCount =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  String getOutputName(int index) =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  List<String> get outputNames =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  Tensor getOutputTensor(String name) =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  List<Tensor> getOutputTensors() =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  void run(Map<String, Object> inputs, Map<String, Object> outputs) =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  void close() =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  bool get isClosed =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  int get lastInferenceDurationMicroseconds =>
      throw UnsupportedError('SignatureRunner is not supported on web.');

  @Deprecated(
    'Use lastInferenceDurationMicroseconds instead. '
    'This alias will be removed in a future major release.',
  )
  int get lastNativeInferenceDurationMicroSeconds =>
      throw UnsupportedError('SignatureRunner is not supported on web.');
}
