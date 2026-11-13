import 'models.dart';

/// Storage for collections and puzzles.
abstract interface class CollectionRepository {
  /// All collections, newest first, with counts.
  Future<List<CollectionSummary>> listCollections();

  Future<Collection> createCollection(String name);

  Future<void> renameCollection(int id, String name);

  /// Deletes the collection and all its puzzles. Returns the stored image
  /// paths that no remaining puzzle uses any more, for the caller to delete.
  Future<List<String>> deleteCollection(int id);

  /// Puzzles of a collection in reading order (page, index, then creation).
  Future<List<Puzzle>> puzzlesIn(int collectionId);

  Future<Puzzle?> getPuzzle(int id);

  /// Saves a new puzzle ([Puzzle.id] is ignored) and returns it with its id.
  Future<Puzzle> addPuzzle(Puzzle puzzle);

  /// Saves all [puzzles] or none of them, in one transaction, and returns them
  /// with their ids.
  Future<List<Puzzle>> addPuzzles(List<Puzzle> puzzles);

  /// Replaces the stored puzzle with the same id.
  Future<void> updatePuzzle(Puzzle puzzle);

  /// Deletes a puzzle. Returns the stored image paths that no remaining puzzle
  /// uses any more (a page image is shared by the puzzles of that page).
  Future<List<String>> deletePuzzle(int id);

  /// Counts one attempt and sets the status.
  Future<void> recordAttempt(int puzzleId, {required PuzzleStatus status});

  Future<void> close();
}
