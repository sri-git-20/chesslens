import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_litert/flutter_litert.dart';

import 'model_decode.dart';
import 'pipeline.dart';

/// The three LiteRT interpreters behind a [RecognitionPipeline]. Create and
/// use them on the same isolate.
class InterpreterModels {
  InterpreterModels._(this._interpreters, this.pipeline);

  /// Creates the interpreters from model files.
  factory InterpreterModels.fromFiles({
    required String detector,
    required String corners,
    required String squares,
  }) =>
      InterpreterModels.fromBytes(
        detector: File(detector).readAsBytesSync(),
        corners: File(corners).readAsBytesSync(),
        squares: File(squares).readAsBytesSync(),
      );

  /// Creates the interpreters from model bytes. Throws when a model does not
  /// have the output size of the contract in `docs/ARCHITECTURE.md`.
  factory InterpreterModels.fromBytes({
    required Uint8List detector,
    required Uint8List corners,
    required Uint8List squares,
    int threads = 4,
  }) {
    final created = <Interpreter>[];
    try {
      ModelFn load(String name, Uint8List bytes, int outputLength) {
        final options = InterpreterOptions()..threads = threads;
        final Interpreter interpreter;
        try {
          interpreter = Interpreter.fromBuffer(bytes, options: options);
        } finally {
          options.delete();
        }
        created.add(interpreter);
        final shape = interpreter.getOutputTensor(0).shape;
        final length = shape.fold<int>(1, (a, b) => a * b);
        if (length != outputLength) {
          throw StateError(
            'The $name model has output shape $shape, expected $outputLength values.',
          );
        }
        return (Float32List input) {
          final out = Float32List(length);
          interpreter.run(input, out);
          return out;
        };
      }

      final pipeline = RecognitionPipeline(
        detector: load('detector', detector, detectorGrid * detectorGrid * detectorChannels),
        corners: load('corners', corners, cornersGrid * cornersGrid * 4),
        squares: load('squares', squares, 64 * classCount),
      );
      return InterpreterModels._(created, pipeline);
    } catch (_) {
      for (final i in created) {
        i.close();
      }
      rethrow;
    }
  }

  final List<Interpreter> _interpreters;
  final RecognitionPipeline pipeline;

  void close() {
    for (final i in _interpreters) {
      i.close();
    }
    _interpreters.clear();
  }
}
