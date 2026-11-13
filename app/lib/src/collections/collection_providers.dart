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
abstract interface class ImageStore {
  /// Writes [png] to the app's documents folder and returns its path.
  Future<String> saveCrop(Uint8List png);
}

class DocumentsImageStore implements ImageStore {
  @override
  Future<String> saveCrop(Uint8List png) async {
    final documents = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(documents.path, 'crops'));
    await folder.create(recursive: true);
    final name = 'crop_${DateTime.now().microsecondsSinceEpoch}.png';
    final file = File(p.join(folder.path, name));
    await file.writeAsBytes(png, flush: true);
    return file.path;
  }
}

final imageStoreProvider = Provider<ImageStore>((ref) => DocumentsImageStore());
