import 'dart:typed_data';

/// Allocates a nested list structure matching the given tensor [shape].
///
/// Recursively builds nested lists where the innermost dimension contains
/// doubles initialized to 0.0.
Object allocTensorShape(List<int> shape) {
  if (shape.isEmpty) return <double>[];

  Object build(int depth) {
    final int size = shape[depth];

    if (depth == shape.length - 1) {
      return List<double>.filled(size, 0.0, growable: false);
    }

    switch (shape.length - depth) {
      case 2:
        return List<List<double>>.generate(
          size,
          (_) => build(depth + 1) as List<double>,
          growable: false,
        );
      case 3:
        return List<List<List<double>>>.generate(
          size,
          (_) => build(depth + 1) as List<List<double>>,
          growable: false,
        );
      case 4:
        return List<List<List<List<double>>>>.generate(
          size,
          (_) => build(depth + 1) as List<List<List<double>>>,
          growable: false,
        );
      default:
        return List.generate(size, (_) => build(depth + 1), growable: false);
    }
  }

  return build(0);
}

/// Creates output buffers matching the given output tensor [shapes].
///
/// Returns a map from output index to the allocated buffer.
Map<int, Object> createOutputBuffers(List<List<int>> shapes) {
  return {
    for (int i = 0; i < shapes.length; i++) i: allocTensorShape(shapes[i]),
  };
}

/// Zeros all values in pre-allocated output buffers.
void zeroOutputBuffers(Map<int, Object> outputs, List<List<int>> shapes) {
  for (int i = 0; i < shapes.length; i++) {
    final List<int> shape = shapes[i];
    final Object buf = outputs[i]!;
    if (shape.length == 3) {
      final list3d = buf as List<List<List<double>>>;
      for (int j = 0; j < shape[0]; j++) {
        for (int k = 0; k < shape[1]; k++) {
          list3d[j][k].fillRange(0, shape[2], 0.0);
        }
      }
    } else if (shape.length == 2) {
      final list2d = buf as List<List<double>>;
      for (int j = 0; j < shape[0]; j++) {
        list2d[j].fillRange(0, shape[1], 0.0);
      }
    } else {
      final list1d = buf as List<double>;
      list1d.fillRange(0, list1d.length, 0.0);
    }
  }
}

/// Creates a pre-allocated `[1][height][width][3]` tensor structure.
List<List<List<List<double>>>> createNHWCTensor4D(int height, int width) {
  return allocTensorShape([1, height, width, 3])
      as List<List<List<List<double>>>>;
}

/// Fills an NHWC 4D tensor cache from a flat Float32List.
@pragma('vm:prefer-inline')
void fillNHWC4D(
  Float32List flat,
  List<List<List<List<double>>>> cache,
  int inH,
  int inW,
) {
  int k = 0;
  final List<List<List<double>>> plane = cache[0];
  for (int y = 0; y < inH; y++) {
    final List<List<double>> row = plane[y];
    for (int x = 0; x < inW; x++) {
      final List<double> px = row[x];
      px[0] = flat[k++];
      px[1] = flat[k++];
      px[2] = flat[k++];
    }
  }
}

/// Flattens an arbitrarily nested tensor to a flat Float32List.
Float32List flattenDynamicTensor(Object? out) {
  if (out == null) {
    throw TypeError();
  }

  // Fast paths for common concrete shapes produced by allocTensorShape.
  if (out is List<double>) {
    final int n = out.length;
    final Float32List result = Float32List(n);
    for (int i = 0; i < n; i++) {
      result[i] = out[i];
    }
    return result;
  }
  if (out is List<List<double>>) {
    int total = 0;
    for (int i = 0; i < out.length; i++) {
      total += out[i].length;
    }
    final Float32List result = Float32List(total);
    int w = 0;
    for (int i = 0; i < out.length; i++) {
      final List<double> row = out[i];
      for (int j = 0; j < row.length; j++) {
        result[w++] = row[j];
      }
    }
    return result;
  }
  if (out is List<List<List<double>>>) {
    int total = 0;
    for (int i = 0; i < out.length; i++) {
      final List<List<double>> plane = out[i];
      for (int j = 0; j < plane.length; j++) {
        total += plane[j].length;
      }
    }
    final Float32List result = Float32List(total);
    int w = 0;
    for (int i = 0; i < out.length; i++) {
      final List<List<double>> plane = out[i];
      for (int j = 0; j < plane.length; j++) {
        final List<double> row = plane[j];
        for (int k = 0; k < row.length; k++) {
          result[w++] = row[k];
        }
      }
    }
    return result;
  }
  if (out is List<List<List<List<double>>>>) {
    int total = 0;
    for (int i = 0; i < out.length; i++) {
      final List<List<List<double>>> cube = out[i];
      for (int j = 0; j < cube.length; j++) {
        final List<List<double>> plane = cube[j];
        for (int k = 0; k < plane.length; k++) {
          total += plane[k].length;
        }
      }
    }
    final Float32List result = Float32List(total);
    int w = 0;
    for (int i = 0; i < out.length; i++) {
      final List<List<List<double>>> cube = out[i];
      for (int j = 0; j < cube.length; j++) {
        final List<List<double>> plane = cube[j];
        for (int k = 0; k < plane.length; k++) {
          final List<double> row = plane[k];
          for (int l = 0; l < row.length; l++) {
            result[w++] = row[l];
          }
        }
      }
    }
    return result;
  }

  // Fallback: recursive walk for unknown shapes.
  final List<double> flat = <double>[];
  void walk(dynamic x) {
    if (x is num) {
      flat.add(x.toDouble());
    } else if (x is List) {
      for (final e in x) {
        walk(e);
      }
    } else {
      throw StateError('Unexpected output element type: ${x.runtimeType}');
    }
  }

  walk(out);
  return Float32List.fromList(flat);
}
