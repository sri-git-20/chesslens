import 'dart:typed_data';

import '../native/interpreter.dart';

/// Cached [Float32List] views of an [Interpreter]'s input and output tensors.
///
/// Capture once after [Interpreter.allocateTensors] and reuse the views on
/// every inference. The views alias the underlying tensor native memory,
/// so writing to [inputs] stages data directly into the input tensor and
/// reading from [outputs] reads the latest values after
/// [Interpreter.invoke] (or `runForMultipleInputs`).
///
/// This avoids recreating `Float32List` wrapper objects every inference
/// and avoids repeated `getInputTensor` / `getOutputTensor` lookups on
/// the hot path.
///
/// Validity:
/// - [Interpreter.allocateTensors] must have been called before capture.
/// - Views become stale after any [Interpreter.resizeInputTensor] or
///   subsequent `allocateTensors`. Recapture in that case.
/// - Only meaningful for tensors whose element type is float32. For
///   quantized tensors, interpreting bytes as Float32 will produce
///   garbage; use the raw `Tensor.data` bytes instead.
///
/// Example:
/// ```dart
/// interp.allocateTensors();
/// final views = TensorFloat32Views.capture(interp);
///
/// // Hot path:
/// views.inputs[0].setAll(0, preparedNHWC);
/// interp.invoke();
/// final scores = views.outputs[1]; // aliases tensor native memory
/// ```
class TensorFloat32Views {
  /// One [Float32List] view per input tensor, in declaration order.
  final List<Float32List> inputs;

  /// One [Float32List] view per output tensor, in declaration order.
  final List<Float32List> outputs;

  const TensorFloat32Views._(this.inputs, this.outputs);

  /// Captures Float32List views of every input and output tensor of [interp].
  ///
  /// Returned lists are unmodifiable (the views themselves can be written
  /// to, but the list of views can't be reassigned).
  factory TensorFloat32Views.capture(Interpreter interp) {
    // Views must come from asFloat32View(), not Tensor.data: the data getter
    // returns an unmodifiable view, and writes through its buffer would rely
    // on a Dart VM enforcement gap (indexed stores throw; setAll only works
    // because the memmove fast path skips the unmodifiable check).
    final int inCount = interp.getInputTensors().length;
    final List<Float32List> inputs = List<Float32List>.unmodifiable(
      <Float32List>[
        for (int i = 0; i < inCount; i++)
          interp.getInputTensor(i).asFloat32View(),
      ],
    );

    final int outCount = interp.getOutputTensors().length;
    final List<Float32List> outputs = List<Float32List>.unmodifiable(
      <Float32List>[
        for (int i = 0; i < outCount; i++)
          interp.getOutputTensor(i).asFloat32View(),
      ],
    );

    return TensorFloat32Views._(inputs, outputs);
  }
}
