/// Returns the total number of elements from a tensor shape.
int computeNumElements(List<int> shape) {
  int n = 1;
  for (var i = 0; i < shape.length; i++) {
    n *= shape[i];
  }
  return n;
}

/// Returns shape of an object as an int list.
List<int> computeShapeOf(Object o) {
  int size = computeNumDimensions(o);
  List<int> dimensions = List.filled(size, 0, growable: false);
  fillShape(o, 0, dimensions);
  return dimensions;
}

/// Returns the number of dimensions of a multi-dimensional array, otherwise 0.
int computeNumDimensions(Object? o) {
  if (o == null || o is! List) {
    return 0;
  }
  if (o.isEmpty) {
    throw ArgumentError('Array lengths cannot be 0.');
  }
  return 1 + computeNumDimensions(o.elementAt(0));
}

/// Recursively populates the shape dimensions for a given (multi-dimensional) array.
void fillShape(Object o, int dim, List<int>? shape) {
  if (shape == null || dim == shape.length) {
    return;
  }
  final len = (o as List).length;
  if (shape[dim] == 0) {
    shape[dim] = len;
  } else if (shape[dim] != len) {
    throw ArgumentError(
      'Mismatched lengths ${shape[dim]} and $len in dimension $dim',
    );
  }
  for (var i = 0; i < len; ++i) {
    fillShape(o.elementAt(i), dim + 1, shape);
  }
}
