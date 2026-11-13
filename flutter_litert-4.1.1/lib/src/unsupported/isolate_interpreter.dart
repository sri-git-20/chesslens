// Unsupported platform stub for IsolateInterpreter.
//
// This file is used when compiling for platforms where neither dart:io
// nor dart:js_interop is available.

import '../isolate_interpreter_state.dart';

/// Allows running LiteRT inference in a separate isolate.
class IsolateInterpreter {
  // Private constructor for the interpreter.
  IsolateInterpreter._({required this.address, required this.debugName}) {
    throw UnsupportedError(
      'IsolateInterpreter is not supported on this platform',
    );
  }

  // Factory method to create an instance of the IsolateInterpreter.
  static Future<IsolateInterpreter> create({
    required int address,
    String debugName = 'TfLiteInterpreterIsolate',
  }) => throw UnsupportedError(
    'IsolateInterpreter.create is not supported on this platform',
  );

  final int address;
  final String debugName;

  Stream<IsolateInterpreterState> get stateChanges => throw UnsupportedError(
    'IsolateInterpreter.stateChanges is not supported on this platform',
  );

  IsolateInterpreterState get state => throw UnsupportedError(
    'IsolateInterpreter.state is not supported on this platform',
  );

  /// Run LiteRT model for single input and output.
  Future<void> run(Object input, Object output) => throw UnsupportedError(
    'IsolateInterpreter.run is not supported on this platform',
  );

  /// Run LiteRT model for multiple inputs and outputs.
  Future<void> runForMultipleInputs(
    List<Object> inputs,
    Map<int, Object> outputs,
  ) => throw UnsupportedError(
    'IsolateInterpreter.runForMultipleInputs is not supported on this platform',
  );

  // Close resources and terminate the isolate.
  Future<void> close() => throw UnsupportedError(
    'IsolateInterpreter.close is not supported on this platform',
  );
}
