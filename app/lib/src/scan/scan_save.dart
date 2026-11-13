import 'package:dartchess/dartchess.dart' show Board;

import '../chess/castling.dart';
import '../collections/collection_providers.dart';
import '../collections/collection_repository.dart';
import '../collections/models.dart';
import '../collections/save_dialog.dart';
import 'scan_session.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Default collection name for a photo or screenshot, like "Scan 13 Nov 14:05".
String scanCollectionName(DateTime now) =>
    'Scan ${now.day} ${_months[now.month - 1]} ${_two(now.hour)}:${_two(now.minute)}';

/// Default collection name for a PDF, like "Endgames p. 42" or
/// "Endgames pp. 42-45".
String pdfCollectionName(String fileName, Iterable<int> pageNumbers) {
  final base = fileName.toLowerCase().endsWith('.pdf')
      ? fileName.substring(0, fileName.length - 4)
      : fileName;
  final pages = pageNumbers.toList()..sort();
  if (pages.isEmpty) return base;
  if (pages.first == pages.last) return '$base p. ${pages.first}';
  return '$base pp. ${pages.first}-${pages.last}';
}

/// The full FEN saved for a scanned board: placement, White to move and the
/// castling rights the pieces allow.
String scannedFullFen(String placement) {
  final castling = inferCastlingRights(Board.parseFen(placement));
  return '$placement w ${castling.fen} - 0 1';
}

/// Saves [boards] as puzzles and returns the collection they went to.
Future<Collection> saveScannedBoards({
  required CollectionRepository repository,
  required ImageStore images,
  required List<ScanBoard> boards,
  required SaveTarget target,
  DateTime? now,
}) async {
  final Collection collection;
  if (target.newName != null) {
    collection = await repository.createCollection(target.newName!);
  } else {
    final all = await repository.listCollections();
    collection = all
        .firstWhere((s) => s.collection.id == target.collectionId)
        .collection;
  }
  final pagePaths = <int, String>{};
  for (final board in boards) {
    final pagePath = pagePaths[board.page.key] ??=
        await images.saveCrop(board.page.jpeg);
    final cropPath = await images.saveCrop(board.cropPng);
    await repository.addPuzzle(
      Puzzle(
        id: 0,
        collectionId: collection.id,
        fen: scannedFullFen(board.reading.placement),
        orientation: board.reading.orientation,
        pageImagePath: pagePath,
        cropImagePath: cropPath,
        pageNumber: board.page.pageNumber,
        indexOnPage: board.indexOnPage,
        createdAt: now ?? DateTime.now(),
      ),
    );
  }
  return collection;
}
