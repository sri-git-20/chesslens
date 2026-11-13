import 'dart:io';

import 'package:chesslens/src/collections/collection_repository.dart';
import 'package:chesslens/src/collections/memory_collection_repository.dart';
import 'package:chesslens/src/collections/models.dart';
import 'package:chesslens/src/collections/sqflite_collection_repository.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String fenA = '4k3/8/8/8/8/8/4P3/4K3 w - - 0 1';
const String fenB = '4k3/8/8/8/8/8/8/R3K3 b Q - 0 1';

Puzzle newPuzzle(int collectionId, String fen, {int? page, int? index, Side side = Side.white}) =>
    Puzzle(
      id: 0,
      collectionId: collectionId,
      fen: fen,
      orientation: side,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      pageNumber: page,
      indexOnPage: index,
    );

/// The checks every implementation must pass.
void repositoryContract(Future<CollectionRepository> Function() create) {
  late CollectionRepository repository;

  setUp(() async {
    repository = await create();
  });

  tearDown(() => repository.close());

  test('starts empty', () async {
    expect(await repository.listCollections(), isEmpty);
  });

  test('creates, lists and renames collections', () async {
    final first = await repository.createCollection('  Endgames ');
    final second = await repository.createCollection('Tactics');
    expect(first.name, 'Endgames');
    expect(first.id, isNot(second.id));

    var list = await repository.listCollections();
    expect(list.map((s) => s.collection.name), ['Tactics', 'Endgames']);
    expect(list.every((s) => s.puzzleCount == 0 && s.solvedCount == 0), isTrue);

    await repository.renameCollection(first.id, 'Rook endgames');
    list = await repository.listCollections();
    expect(list.map((s) => s.collection.name), contains('Rook endgames'));
  });

  test('adds puzzles and reads them back', () async {
    final collection = await repository.createCollection('Book');
    final saved = await repository.addPuzzle(newPuzzle(collection.id, fenA, side: Side.black));
    expect(saved.id, greaterThan(0));

    final loaded = await repository.getPuzzle(saved.id);
    expect(loaded, isNotNull);
    expect(loaded!.fen, fenA);
    expect(loaded.orientation, Side.black);
    expect(loaded.status, PuzzleStatus.unsolved);
    expect(loaded.attempts, 0);
    expect(loaded.collectionId, collection.id);
    expect(loaded.createdAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    expect(await repository.getPuzzle(9999), isNull);
  });

  test('puzzles come back in reading order', () async {
    final collection = await repository.createCollection('Book');
    final third = await repository.addPuzzle(newPuzzle(collection.id, fenA, page: 2, index: 1));
    final second = await repository.addPuzzle(newPuzzle(collection.id, fenA, page: 1, index: 2));
    final first = await repository.addPuzzle(newPuzzle(collection.id, fenB, page: 1, index: 1));
    final puzzles = await repository.puzzlesIn(collection.id);
    expect(puzzles.map((p) => p.id), [first.id, second.id, third.id]);
  });

  test('summaries count puzzles and solved puzzles', () async {
    final collection = await repository.createCollection('Book');
    final a = await repository.addPuzzle(newPuzzle(collection.id, fenA));
    await repository.addPuzzle(newPuzzle(collection.id, fenB));
    await repository.recordAttempt(a.id, status: PuzzleStatus.solved);

    final summary = (await repository.listCollections()).single;
    expect(summary.puzzleCount, 2);
    expect(summary.solvedCount, 1);
    expect(summary.previewFen, fenA);
  });

  test('updates a puzzle', () async {
    final collection = await repository.createCollection('Book');
    final saved = await repository.addPuzzle(newPuzzle(collection.id, fenA));
    await repository.updatePuzzle(saved.copyWith(fen: fenB, orientation: Side.black, notes: 'x'));
    final loaded = (await repository.getPuzzle(saved.id))!;
    expect(loaded.fen, fenB);
    expect(loaded.orientation, Side.black);
    expect(loaded.notes, 'x');
  });

  test('records attempts', () async {
    final collection = await repository.createCollection('Book');
    final saved = await repository.addPuzzle(newPuzzle(collection.id, fenA));
    await repository.recordAttempt(saved.id, status: PuzzleStatus.failed);
    await repository.recordAttempt(saved.id, status: PuzzleStatus.solved);
    final loaded = (await repository.getPuzzle(saved.id))!;
    expect(loaded.attempts, 2);
    expect(loaded.status, PuzzleStatus.solved);
  });

  test('deletes a puzzle', () async {
    final collection = await repository.createCollection('Book');
    final a = await repository.addPuzzle(newPuzzle(collection.id, fenA));
    final b = await repository.addPuzzle(newPuzzle(collection.id, fenB));
    await repository.deletePuzzle(a.id);
    expect((await repository.puzzlesIn(collection.id)).map((p) => p.id), [b.id]);
    expect(await repository.getPuzzle(a.id), isNull);
  });

  Puzzle withImages(int collectionId, String page, String crop) => Puzzle(
        id: 0,
        collectionId: collectionId,
        fen: fenA,
        orientation: Side.white,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        pageImagePath: page,
        cropImagePath: crop,
      );

  test('deleting a puzzle reports only the images nobody else uses', () async {
    final collection = await repository.createCollection('Book');
    final a = await repository.addPuzzle(withImages(collection.id, 'crops/page.png', 'crops/a.png'));
    final b = await repository.addPuzzle(withImages(collection.id, 'crops/page.png', 'crops/b.png'));
    expect(await repository.deletePuzzle(a.id), ['crops/a.png']);
    expect((await repository.deletePuzzle(b.id))..sort(), ['crops/b.png', 'crops/page.png']);
    expect(await repository.deletePuzzle(b.id), isEmpty);
  });

  test('deleting a collection reports its unused images', () async {
    final keep = await repository.createCollection('Keep');
    final drop = await repository.createCollection('Drop');
    await repository.addPuzzle(withImages(keep.id, 'crops/shared.png', 'crops/k.png'));
    await repository.addPuzzle(withImages(drop.id, 'crops/shared.png', 'crops/d.png'));
    expect(await repository.deleteCollection(drop.id), ['crops/d.png']);
  });

  test('addPuzzles saves all puzzles with ids', () async {
    final collection = await repository.createCollection('Book');
    final saved = await repository.addPuzzles([
      newPuzzle(collection.id, fenA, page: 1, index: 1),
      newPuzzle(collection.id, fenB, page: 1, index: 2),
    ]);
    expect(saved.map((p) => p.id).toSet(), hasLength(2));
    expect(await repository.puzzlesIn(collection.id), hasLength(2));
    expect(await repository.addPuzzles(const []), isEmpty);
  });

  test('deleting a collection deletes its puzzles only', () async {
    final keep = await repository.createCollection('Keep');
    final drop = await repository.createCollection('Drop');
    final kept = await repository.addPuzzle(newPuzzle(keep.id, fenA));
    final dropped = await repository.addPuzzle(newPuzzle(drop.id, fenB));
    await repository.deleteCollection(drop.id);

    expect((await repository.listCollections()).map((s) => s.collection.id), [keep.id]);
    expect(await repository.getPuzzle(dropped.id), isNull);
    expect(await repository.getPuzzle(kept.id), isNotNull);
    expect(await repository.puzzlesIn(drop.id), isEmpty);
  });
}

void main() {
  group('in-memory repository', () {
    repositoryContract(() async => MemoryCollectionRepository());
  });

  group('sqflite repository (sqlite through ffi)', () {
    setUpAll(sqfliteFfiInit);

    repositoryContract(
      () async => SqfliteCollectionRepository(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      ),
    );

    test('addPuzzles is all or nothing', () async {
      final repository = SqfliteCollectionRepository(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
      );
      addTearDown(repository.close);
      final collection = await repository.createCollection('Book');
      // The second puzzle points at a collection that does not exist, which
      // the foreign key rejects.
      await expectLater(
        repository.addPuzzles([
          newPuzzle(collection.id, fenA),
          newPuzzle(collection.id + 100, fenB),
        ]),
        throwsA(anything),
      );
      expect(await repository.puzzlesIn(collection.id), isEmpty);
    });

    test('data survives closing and reopening the file', () async {
      final path = '${Directory.systemTemp.createTempSync('chesslens_db').path}/test.db';
      final first = SqfliteCollectionRepository(factory: databaseFactoryFfi, path: path);
      final collection = await first.createCollection('Saved');
      await first.addPuzzle(newPuzzle(collection.id, fenA));
      await first.close();

      final second = SqfliteCollectionRepository(factory: databaseFactoryFfi, path: path);
      final list = await second.listCollections();
      expect(list.single.collection.name, 'Saved');
      expect(list.single.puzzleCount, 1);
      await second.close();
    });
  });
}
