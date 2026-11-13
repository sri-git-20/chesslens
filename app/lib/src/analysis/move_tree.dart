import 'package:dartchess/dartchess.dart';

/// One position in the analysis tree, reached by [move] from [parent].
class MoveNode {
  MoveNode._({
    required this.id,
    required this.position,
    this.parent,
    this.move,
    this.san,
  });

  final int id;
  final Position position;
  final MoveNode? parent;

  /// The move that led here; `null` for the root.
  final NormalMove? move;
  final String? san;

  /// The first child is the main continuation, the others are variations.
  final List<MoveNode> children = [];

  bool get isRoot => parent == null;

  /// Number of half-moves from the root.
  int get depth => parent == null ? 0 : parent!.depth + 1;
}

/// A tree of moves with a current position: a mainline with variations.
///
/// Playing a move that already exists from the current position just selects
/// it; a different move adds a new branch.
class MoveTree {
  MoveTree(Position start) : root = MoveNode._(id: 0, position: start) {
    current = root;
  }

  final MoveNode root;
  late MoveNode current;
  int _nextId = 1;

  bool get canGoBack => current.parent != null;
  bool get canGoForward => current.children.isNotEmpty;

  /// Plays [move] from the current position. Returns the node, or `null` when
  /// the move is not legal.
  MoveNode? play(NormalMove move) {
    final position = current.position;
    final normalized = position.normalizeMove(move);
    if (normalized is! NormalMove || !position.isLegal(normalized)) return null;
    for (final child in current.children) {
      if (child.move == normalized) {
        current = child;
        return child;
      }
    }
    final (next, san) = position.makeSan(normalized);
    final node = MoveNode._(
      id: _nextId++,
      position: next,
      parent: current,
      move: normalized,
      san: san,
    );
    current.children.add(node);
    current = node;
    return node;
  }

  void back() {
    final parent = current.parent;
    if (parent != null) current = parent;
  }

  void forward() {
    if (current.children.isNotEmpty) current = current.children.first;
  }

  void goToStart() => current = root;

  /// Selects the end of the line that follows the first child at each step.
  void goToEnd() {
    while (current.children.isNotEmpty) {
      current = current.children.first;
    }
  }

  void goTo(MoveNode node) => current = node;
}
