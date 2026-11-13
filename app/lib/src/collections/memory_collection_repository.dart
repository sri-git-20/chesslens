import 'collection_repository.dart';
import 'models.dart';

/// A [CollectionRepository] that keeps everything in memory. For tests.
class MemoryCollectionRepository implements CollectionRepository {
  final Map<int, Collection> _collections = {};
  final Map<int, Puzzle> _puzzles = {};
  int _nextCollectionId = 1;
  int _nextPuzzleId = 1;

  @override
  Future<List<CollectionSummary>> listCollections() async {
    final list = _collections.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt) != 0
          ? b.createdAt.compareTo(a.createdAt)
          : b.id.compareTo(a.id));
    return [
      for (final collection in list)
        () {
          final puzzles = _puzzlesOf(collection.id);
          return CollectionSummary(
            collection: collection,
            puzzleCount: puzzles.length,
            solvedCount:
                puzzles.where((p) => p.status == PuzzleStatus.solved).length,
            previewFen: puzzles.isEmpty ? null : puzzles.first.fen,
          );
        }(),
    ];
  }

  List<Puzzle> _puzzlesOf(int collectionId) {
    final list = _puzzles.values.where((p) => p.collectionId == collectionId).toList()
      ..sort((a, b) {
        final page = (a.pageNumber ?? 0).compareTo(b.pageNumber ?? 0);
        if (page != 0) return page;
        final index = (a.indexOnPage ?? 0).compareTo(b.indexOnPage ?? 0);
        if (index != 0) return index;
        return a.id.compareTo(b.id);
      });
    return list;
  }

  @override
  Future<Collection> createCollection(String name) async {
    final now = DateTime.now();
    final collection = Collection(
      id: _nextCollectionId++,
      name: name.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _collections[collection.id] = collection;
    return collection;
  }

  @override
  Future<void> renameCollection(int id, String name) async {
    final existing = _collections[id];
    if (existing == null) return;
    _collections[id] = existing.copyWith(name: name.trim(), updatedAt: DateTime.now());
  }

  Set<String> _imagePaths(Iterable<Puzzle> puzzles) => {
        for (final puzzle in puzzles) ...[
          if (puzzle.pageImagePath != null) puzzle.pageImagePath!,
          if (puzzle.cropImagePath != null) puzzle.cropImagePath!,
        ],
      };

  List<String> _orphans(Set<String> candidates) {
    final used = _imagePaths(_puzzles.values);
    return [for (final path in candidates) if (!used.contains(path)) path];
  }

  @override
  Future<List<String>> deleteCollection(int id) async {
    final doomed = _puzzles.values.where((p) => p.collectionId == id).toList();
    _collections.remove(id);
    _puzzles.removeWhere((_, puzzle) => puzzle.collectionId == id);
    return _orphans(_imagePaths(doomed));
  }

  @override
  Future<List<Puzzle>> puzzlesIn(int collectionId) async => _puzzlesOf(collectionId);

  @override
  Future<Puzzle?> getPuzzle(int id) async => _puzzles[id];

  @override
  Future<Puzzle> addPuzzle(Puzzle puzzle) async {
    final saved = puzzle.copyWith(id: _nextPuzzleId++);
    _puzzles[saved.id] = saved;
    final collection = _collections[saved.collectionId];
    if (collection != null) {
      _collections[collection.id] = collection.copyWith(updatedAt: DateTime.now());
    }
    return saved;
  }

  @override
  Future<List<Puzzle>> addPuzzles(List<Puzzle> puzzles) async {
    final saved = <Puzzle>[];
    for (final puzzle in puzzles) {
      saved.add(await addPuzzle(puzzle));
    }
    return saved;
  }

  @override
  Future<void> updatePuzzle(Puzzle puzzle) async {
    if (_puzzles.containsKey(puzzle.id)) _puzzles[puzzle.id] = puzzle;
  }

  @override
  Future<List<String>> deletePuzzle(int id) async {
    final doomed = _puzzles.remove(id);
    return doomed == null ? const [] : _orphans(_imagePaths([doomed]));
  }

  @override
  Future<void> recordAttempt(int puzzleId, {required PuzzleStatus status}) async {
    final existing = _puzzles[puzzleId];
    if (existing == null) return;
    _puzzles[puzzleId] = existing.copyWith(
      status: status,
      attempts: existing.attempts + 1,
    );
  }

  @override
  Future<void> close() async {}
}
