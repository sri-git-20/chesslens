import 'point.dart';

/// An axis-aligned or rotated bounding box defined by four corner points.
class BoundingBox {
  /// Top-left corner point in absolute pixel coordinates.
  final Point topLeft;

  /// Top-right corner point in absolute pixel coordinates.
  final Point topRight;

  /// Bottom-right corner point in absolute pixel coordinates.
  final Point bottomRight;

  /// Bottom-left corner point in absolute pixel coordinates.
  final Point bottomLeft;

  /// Creates a bounding box with four corner points.
  ///
  /// Points should be in order: top-left, top-right, bottom-right, bottom-left.
  const BoundingBox({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// Creates an axis-aligned bounding box from left, top, right, and bottom edges.
  factory BoundingBox.ltrb(
    double left,
    double top,
    double right,
    double bottom,
  ) => BoundingBox(
    topLeft: Point(left, top),
    topRight: Point(right, top),
    bottomRight: Point(right, bottom),
    bottomLeft: Point(left, bottom),
  );

  /// The four corner points as a list in order: top-left, top-right,
  /// bottom-right, bottom-left.
  ///
  /// Useful for iteration or when you need all corners at once.
  List<Point> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  /// Width of the bounding box in pixels.
  double get width => topRight.x - topLeft.x;

  /// Height of the bounding box in pixels.
  double get height => bottomLeft.y - topLeft.y;

  /// Center point of the bounding box in absolute pixel coordinates.
  Point get center => Point(
    (topLeft.x + topRight.x + bottomRight.x + bottomLeft.x) / 4,
    (topLeft.y + topRight.y + bottomRight.y + bottomLeft.y) / 4,
  );

  /// Left edge of the bounding box (x-coordinate of top-left corner).
  double get left => topLeft.x;

  /// Top edge of the bounding box (y-coordinate of top-left corner).
  double get top => topLeft.y;

  /// Right edge of the bounding box (x-coordinate of bottom-right corner).
  double get right => bottomRight.x;

  /// Bottom edge of the bounding box (y-coordinate of bottom-right corner).
  double get bottom => bottomRight.y;

  /// Converts this bounding box to a map for isolate serialization.
  Map<String, dynamic> toMap() => {
    'topLeft': topLeft.toMap(),
    'topRight': topRight.toMap(),
    'bottomRight': bottomRight.toMap(),
    'bottomLeft': bottomLeft.toMap(),
  };

  /// Creates a bounding box from a map (isolate deserialization).
  factory BoundingBox.fromMap(Map<String, dynamic> map) => BoundingBox(
    topLeft: Point.fromMap(map['topLeft']),
    topRight: Point.fromMap(map['topRight']),
    bottomRight: Point.fromMap(map['bottomRight']),
    bottomLeft: Point.fromMap(map['bottomLeft']),
  );
}
