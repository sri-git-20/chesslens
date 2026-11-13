import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'collection_repository.dart';
import 'models.dart';
import 'sqflite_collection_repository.dart';

/// The collection database. Tests override this with
/// `MemoryCollectionRepository`.
final collectionRepositoryProvider = Provider<CollectionRepository>((ref) {
  final repository = SqfliteCollectionRepository();
  ref.onDispose(repository.close);
  return repository;
});

/// Collections for the Home screen. Invalidate after any change.
final collectionsProvider = FutureProvider.autoDispose<List<CollectionSummary>>(
  (ref) => ref.watch(collectionRepositoryProvider).listCollections(),
);

/// Stores images that belong to puzzles (diagram crops, page photos).
///
/// Paths handed out and stored in the database are relative to the app's
/// documents folder (`crops/crop_123.png`), because the absolute path of that
/// folder can change when the app is updated or restored (iOS).
abstract interface class ImageStore {
  /// Writes [png] under the app's documents folder and returns its stored
  /// (relative) path.
  Future<String> saveCrop(Uint8List png);

  /// Deletes the stored files at [paths]. Missing files and paths that point
  /// outside the image folder are ignored; never throws for a single file.
  Future<void> delete(Iterable<String> paths);
}

/// The file for a stored image path inside [documents].
///
/// Both relative paths (`crops/a.png`) and the absolute paths that older
/// versions stored map to `<documents>/crops/<file name>`, so they keep
/// working after the documents folder moves.
File storedImageFile(Directory documents, String stored) =>
    File(p.join(documents.path, _imageFolder, p.basename(stored.replaceAll('\\', '/'))));

const String _imageFolder = 'crops';

class DocumentsImageStore implements ImageStore {
  DocumentsImageStore({Future<Directory> Function()? documents})
      : _documents = documents ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _documents;
  static int _counter = 0;

  @override
  Future<String> saveCrop(Uint8List png) async {
    final documents = await _documents();
    final folder = Directory(p.join(documents.path, _imageFolder));
    await folder.create(recursive: true);
    final name = 'crop_${DateTime.now().microsecondsSinceEpoch}_${_counter++}.png';
    await File(p.join(folder.path, name)).writeAsBytes(png, flush: true);
    return '$_imageFolder/$name';
  }

  @override
  Future<void> delete(Iterable<String> paths) async {
    final Directory documents;
    try {
      documents = await _documents();
    } catch (_) {
      return;
    }
    for (final stored in paths) {
      try {
        final file = storedImageFile(documents, stored);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // A file that cannot be deleted is left behind; nothing else to do.
      }
    }
  }
}

final imageStoreProvider = Provider<ImageStore>((ref) => DocumentsImageStore());
