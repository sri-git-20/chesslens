import 'dart:typed_data';

import 'package:chesslens/src/chess/board_utils.dart';
import 'package:chesslens/src/collections/collection_providers.dart';
import 'package:chesslens/src/collections/memory_collection_repository.dart';
import 'package:chesslens/src/collections/models.dart';
import 'package:chesslens/src/collections/save_dialog.dart';
import 'package:chesslens/src/scan/geometry.dart';
import 'package:chesslens/src/scan/model_decode.dart';
import 'package:chesslens/src/scan/recognition_service.dart';
import 'package:chesslens/src/scan/scan_engine.dart';
import 'package:chesslens/src/scan/scan_save.dart';
import 'package:chesslens/src/scan/scan_session.dart';
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter_test/flutter_test.dart';

Float32List probsFor(String placement) {
  const letters = 'PNBRQKpnbrqk';
  final probs = Float32List(64 * classCount);
  var i = 0;
  for (final rank in placement.split('/')) {
    for (final ch in rank.split('')) {
      final n = int.tryParse(ch);
      if (n != null) {
        for (var k = 0; k < n; k++) {
          probs[i++ * classCount] = 0.95;
        }
      } else {
        probs[i++ * classCount + letters.indexOf(ch) + 1] = 0.95;
      }
    }
  }
  return probs;
}

RawBoard rawBoard(Quad quad, {String placement = startPlacement}) => RawBoard(
      corners: Float64List.fromList(quad.toList()),
      probs: probsFor(placement),
      cropPng: Uint8List.fromList([1, 2, 3]),
    );

class FakeService implements RecognitionService {
  final List<String> calls = [];

  @override
  Future<PageAnalysis> analyzePage(int pageKey, ScanInput input) =>
      throw UnimplementedError();

  @override
  Future<RawBoard> readQuad(int pageKey, Uint8List pageJpeg, Quad quad) async {
    calls.add('quad');
    return rawBoard(quad, placement: '4k3/8/8/8/8/8/8/4K3');
  }

  @override
  Future<RawBoard> readRegion(int pageKey, Uint8List pageJpeg, Quad region) async {
    calls.add('region');
    return rawBoard(region);
  }

  @override
  Future<void> dispose() async {}
}

class FakeImages implements ImageStore {
  final List<Uint8List> saved = [];
  final List<String> deleted = [];

  @override
  Future<String> saveCrop(Uint8List png) async {
    saved.add(png);
    return 'crops/${saved.length}.png';
  }

  @override
  Future<void> delete(Iterable<String> paths) async => deleted.addAll(paths);
}

/// A repository whose bulk insert fails, to test the clean-up.
class FailingRepository extends MemoryCollectionRepository {
  @override
  Future<List<Puzzle>> addPuzzles(List<Puzzle> puzzles) async =>
      throw StateError('disk full');
}

ScanPage page(int number) => ScanPage(
      key: nextPageKey(),
      jpeg: Uint8List.fromList([9, number]),
      width: 1000,
      height: 1400,
      pageNumber: number,
      label: 'Page $number',
    );

void main() {
  group('ScanSession', () {
    test('numbers boards over pages in reading order', () {
      final session = ScanSession(FakeService());
      session.addPage(page(4), [
        rawBoard(Quad.fromRect(500, 100, 800, 400)), // right column
        rawBoard(Quad.fromRect(100, 600, 400, 900)), //  left, lower
        rawBoard(Quad.fromRect(100, 100, 400, 400)), //  left, upper
      ]);
      session.addPage(page(5), [rawBoard(Quad.fromRect(100, 100, 400, 400))]);

      final boards = session.boards;
      expect(boards.map((b) => b.number), [1, 2, 3, 4]);
      expect(boards[0].quad.minY, 100);
      expect(boards[0].quad.minX, 100);
      expect(boards[1].quad.minY, 600);
      expect(boards[2].quad.minX, 500);
      expect(boards.map((b) => b.indexOnPage), [1, 2, 3, 1]);
      expect(boards.every((b) => b.selected), isTrue);
    });

    test('select all, none and ranges', () {
      final session = ScanSession(FakeService());
      session.addPage(page(1), [
        for (var i = 0; i < 6; i++) rawBoard(Quad.fromRect(100, 100.0 + i * 200, 300, 300.0 + i * 200)),
      ]);
      session.selectNone();
      expect(session.selected, isEmpty);
      expect(session.selectRange('2-3, 6'), isNull);
      expect(session.selected.map((b) => b.number), [2, 3, 6]);
      expect(session.selectRange('9'), 'Numbers go from 1 to 6.');
      expect(session.selectRange('99999999999999999999999'), 'Numbers go from 1 to 6.');
      expect(session.selectRange('1-99999999999999999999999'), 'Numbers go from 1 to 6.');
      expect(session.selected.map((b) => b.number), [2, 3, 6]);
      session.selectAll();
      expect(session.selected, hasLength(6));
      session.toggle(session.boards.first);
      expect(session.selected, hasLength(5));
    });

    test('adjusting corners re-reads the board', () async {
      final service = FakeService();
      final session = ScanSession(service);
      final p = page(1);
      session.addPage(p, [rawBoard(Quad.fromRect(100, 100, 400, 400))]);
      final board = session.boards.single;
      expect(board.reading.placement, startPlacement);
      await session.adjustCorners(board, Quad.fromRect(90, 90, 410, 410));
      expect(service.calls, ['quad']);
      expect(board.quad.minX, 90);
      expect(board.reading.placement, '4k3/8/8/8/8/8/8/4K3');
      expect(session.busy, isNull);
    });

    test('adding a board in a region puts it in reading order and selects it', () async {
      final service = FakeService();
      final session = ScanSession(service);
      final p = page(1);
      session.addPage(p, [rawBoard(Quad.fromRect(100, 500, 400, 800))]);
      final added = await session.addBoardIn(p, Quad.fromRect(100, 50, 400, 350));
      expect(added, isNotNull);
      expect(service.calls, ['region']);
      expect(session.boards.first, added);
      expect(session.boards.map((b) => b.number), [1, 2]);
    });
  });

  group('names', () {
    test('scan collection name', () {
      expect(scanCollectionName(DateTime(2026, 11, 13, 14, 5)), 'Scan 13 Nov 14:05');
    });

    test('pdf collection name', () {
      expect(pdfCollectionName('Endgames.pdf', [42]), 'Endgames p. 42');
      expect(pdfCollectionName('Endgames.PDF', [45, 42, 43]), 'Endgames pp. 42-45');
      expect(pdfCollectionName('notes', []), 'notes');
    });
  });

  group('saving', () {
    test('full FEN has White to move and the castling the pieces allow', () {
      expect(
        scannedFullFen(startPlacement),
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      );
      expect(scannedFullFen('4k3/8/8/8/8/8/8/4K3'), '4k3/8/8/8/8/8/8/4K3 w - - 0 1');
    });

    test('saves puzzles with page, crop, page number and index', () async {
      final repository = MemoryCollectionRepository();
      final images = FakeImages();
      final session = ScanSession(FakeService());
      final p = page(42);
      session.addPage(p, [
        rawBoard(Quad.fromRect(100, 700, 400, 1000), placement: '4k3/8/8/8/8/8/8/4K3'),
        rawBoard(Quad.fromRect(100, 100, 400, 400)),
      ]);
      session.boards.first.selected = false;

      final collection = await saveScannedBoards(
        repository: repository,
        images: images,
        boards: session.selected,
        target: const SaveTarget.create('Endgames p. 42'),
      );
      expect(collection.name, 'Endgames p. 42');
      final puzzles = await repository.puzzlesIn(collection.id);
      expect(puzzles, hasLength(1));
      final puzzle = puzzles.single;
      expect(puzzle.fen, '4k3/8/8/8/8/8/8/4K3 w - - 0 1');
      expect(puzzle.orientation, Side.white);
      expect(puzzle.pageNumber, 42);
      expect(puzzle.indexOnPage, 2);
      expect(puzzle.cropImagePath, isNotNull);
      expect(puzzle.pageImagePath, isNotNull);
      expect(images.saved, hasLength(2));
    });

    test('boards of one page share a single page image', () async {
      final repository = MemoryCollectionRepository();
      final images = FakeImages();
      final session = ScanSession(FakeService());
      session.addPage(page(7), [
        rawBoard(Quad.fromRect(100, 100, 400, 400)),
        rawBoard(Quad.fromRect(100, 600, 400, 900)),
      ]);
      final existing = await repository.createCollection('Mine');
      await saveScannedBoards(
        repository: repository,
        images: images,
        boards: session.selected,
        target: SaveTarget.existing(existing.id),
      );
      final puzzles = await repository.puzzlesIn(existing.id);
      expect(puzzles, hasLength(2));
      expect(puzzles[0].pageImagePath, puzzles[1].pageImagePath);
      expect(images.saved, hasLength(3));
    });

    test('a failed save leaves no new collection and no image files', () async {
      final repository = FailingRepository();
      final images = FakeImages();
      final session = ScanSession(FakeService());
      session.addPage(page(7), [
        rawBoard(Quad.fromRect(100, 100, 400, 400)),
        rawBoard(Quad.fromRect(100, 600, 400, 900)),
      ]);
      await expectLater(
        saveScannedBoards(
          repository: repository,
          images: images,
          boards: session.selected,
          target: const SaveTarget.create('New'),
        ),
        throwsStateError,
      );
      expect(await repository.listCollections(), isEmpty);
      expect(images.deleted, unorderedEquals(['crops/1.png', 'crops/2.png', 'crops/3.png']));
    });

    test('a failed save into an existing collection keeps that collection', () async {
      final repository = FailingRepository();
      final existing = await repository.createCollection('Mine');
      final images = FakeImages();
      final session = ScanSession(FakeService());
      session.addPage(page(7), [rawBoard(Quad.fromRect(100, 100, 400, 400))]);
      await expectLater(
        saveScannedBoards(
          repository: repository,
          images: images,
          boards: session.selected,
          target: SaveTarget.existing(existing.id),
        ),
        throwsStateError,
      );
      expect((await repository.listCollections()).single.collection.id, existing.id);
      expect(images.deleted, hasLength(2));
    });
  });
}
