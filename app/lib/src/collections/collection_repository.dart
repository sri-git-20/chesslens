import 'models.dart';

/// Storage for collections and puzzles.
abstract interface class CollectionRepository {
  /// All collections, newest first, with counts.
  Future<List<CollectionSummary>> listCollections();

  Future<Collection> createCollection(String name);

  Future<void> renameCollection(int id, String name);

  /// Deletes the collection and all its puzzles.
  Future<void> deleteCollection(int id);

  /// Puzzles of a collection in reading order (page, index, then creation).
  Future<List<Puzzle>> puzzlesIn(int collectionId);

  Future<Puzzle?> getPuzzle(int id);

  /// Saves a new puzzle ([Puzzle.id] is ignored) and returns it with its id.
  Future<Puzzle> addPuzzle(Puzzle puzzle);

  /// Replaces the stored puzzle with the same id.
  Future<void> updatePuzzle(Puzzle puzzle);

  Future<void> deletePuzzle(int id);

  /// Counts one attempt and sets the status.
  Future<void> recordAttempt(int puzzleId, {required PuzzleStatus status});

  Future<void> close();
}
