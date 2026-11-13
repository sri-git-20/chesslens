/// A point with x, y, and optional z coordinates.
///
/// Used to represent landmarks with optional depth information.
/// The x and y coordinates are in absolute pixel positions relative to the original image.
/// The z coordinate represents relative depth (scale-dependent) when 3D computation is enabled.
///
/// When [z] is null, this represents a 2D point. When [z] is non-null, it represents
/// a 3D point with depth information.
class Point {
  /// The x-coordinate in absolute pixels.
  final double x;

  /// The y-coordinate in absolute pixels.
  final double y;

  /// The z-coordinate representing relative depth, or null for 2D points.
  ///
  /// This is a scale-dependent depth value. The magnitude depends on the face size
  /// and alignment used during detection. Negative values indicate points closer to
  /// the camera, positive values indicate points further away.
  ///
  /// Will be null for 2D-only landmarks (such as face detection keypoints).
  /// Face mesh and iris landmarks always include z-coordinates.
  final double? z;

  /// Creates a point with the given x, y, and optional z coordinates.
  const Point(this.x, this.y, [this.z]);

  /// Whether this point has depth information (z-coordinate).
  ///
  /// Returns true if z-coordinate is non-null, false otherwise.
  bool get is3D => z != null;

  @override
  String toString() => z != null ? 'Point($x, $y, $z)' : 'Point($x, $y)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Point &&
          runtimeType == other.runtimeType &&
          x == other.x &&
          y == other.y &&
          z == other.z;

  @override
  int get hashCode => Object.hash(x, y, z);

  /// Converts this point to a map for isolate serialization.
  Map<String, dynamic> toMap() => {'x': x, 'y': y, if (z != null) 'z': z};

  /// Creates a point from a map (isolate deserialization).
  factory Point.fromMap(Map<String, dynamic> map) => Point(
    (map['x'] as num).toDouble(),
    (map['y'] as num).toDouble(),
    map['z'] == null ? null : (map['z'] as num).toDouble(),
  );
}
