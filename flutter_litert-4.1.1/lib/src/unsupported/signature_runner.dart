// Unsupported platform stub for SignatureRunner.
//
// This file is used when compiling for platforms where neither dart:io
// nor dart:js_interop is available.

import 'tensor.dart';

/// Unsupported platform stub for [SignatureRunner].
class SignatureRunner {
  SignatureRunner(dynamic runner) {
    throw UnsupportedError('SignatureRunner is not supported on this platform');
  }

  int get inputCount => throw UnsupportedError(
    'SignatureRunner.inputCount is not supported on this platform',
  );

  String getInputName(int index) => throw UnsupportedError(
    'SignatureRunner.getInputName is not supported on this platform',
  );

  List<String> get inputNames => throw UnsupportedError(
    'SignatureRunner.inputNames is not supported on this platform',
  );

  Tensor getInputTensor(String name) => throw UnsupportedError(
    'SignatureRunner.getInputTensor is not supported on this platform',
  );

  List<Tensor> getInputTensors() => throw UnsupportedError(
    'SignatureRunner.getInputTensors is not supported on this platform',
  );

  void resizeInputTensor(String name, List<int> shape) =>
      throw UnsupportedError(
        'SignatureRunner.resizeInputTensor is not supported on this platform',
      );

  void allocateTensors() => throw UnsupportedError(
    'SignatureRunner.allocateTensors is not supported on this platform',
  );

  void invoke() => throw UnsupportedError(
    'SignatureRunner.invoke is not supported on this platform',
  );

  bool cancel() => throw UnsupportedError(
    'SignatureRunner.cancel is not supported on this platform',
  );

  int get outputCount => throw UnsupportedError(
    'SignatureRunner.outputCount is not supported on this platform',
  );

  String getOutputName(int index) => throw UnsupportedError(
    'SignatureRunner.getOutputName is not supported on this platform',
  );

  List<String> get outputNames => throw UnsupportedError(
    'SignatureRunner.outputNames is not supported on this platform',
  );

  Tensor getOutputTensor(String name) => throw UnsupportedError(
    'SignatureRunner.getOutputTensor is not supported on this platform',
  );

  List<Tensor> getOutputTensors() => throw UnsupportedError(
    'SignatureRunner.getOutputTensors is not supported on this platform',
  );

  void run(Map<String, Object> inputs, Map<String, Object> outputs) =>
      throw UnsupportedError(
        'SignatureRunner.run is not supported on this platform',
      );

  void close() => throw UnsupportedError(
    'SignatureRunner.close is not supported on this platform',
  );

  bool get isClosed => throw UnsupportedError(
    'SignatureRunner.isClosed is not supported on this platform',
  );

  int get lastInferenceDurationMicroseconds => throw UnsupportedError(
    'SignatureRunner.lastInferenceDurationMicroseconds is not supported on this platform',
  );

  @Deprecated(
    'Use lastInferenceDurationMicroseconds instead. '
    'This alias will be removed in a future major release.',
  )
  int get lastNativeInferenceDurationMicroSeconds => throw UnsupportedError(
    'SignatureRunner.lastNativeInferenceDurationMicroSeconds is not supported on this platform',
  );
}
