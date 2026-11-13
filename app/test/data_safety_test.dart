import 'dart:io';
import 'dart:typed_data';

import 'package:chesslens/src/collections/collection_providers.dart';
import 'package:chesslens/src/settings/settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('chesslens_safety'));
  tearDown(() => root.deleteSync(recursive: true));

  group('DocumentsImageStore', () {
    test('stores relative paths and deletes the files again', () async {
      final store = DocumentsImageStore(documents: () async => root);
      final a = await store.saveCrop(Uint8List.fromList([1, 2, 3]));
      final b = await store.saveCrop(Uint8List.fromList([4]));
      expect(a, startsWith('crops/'));
      expect(a, isNot(b));
      expect(File('${root.path}/$a').existsSync(), isTrue);

      await store.delete([a, 'crops/never-existed.png']);
      expect(File('${root.path}/$a').existsSync(), isFalse);
      expect(File('${root.path}/$b').existsSync(), isTrue);
    });

    test('an absolute path from an older version still finds the file', () async {
      final store = DocumentsImageStore(documents: () async => root);
      final stored = await store.saveCrop(Uint8List.fromList([7]));
      final name = stored.split('/').last;
      // The documents folder had another location when this was stored.
      final old = '/var/mobile/Containers/OLD-UUID/Documents/crops/$name';
      expect(storedImageFile(root, old).path, '${root.path}/crops/$name');
      await store.delete([old]);
      expect(File('${root.path}/$stored').existsSync(), isFalse);
    });

    test('a path outside the image folder cannot delete other files', () async {
      final other = File('${root.path}/precious.txt')..writeAsStringSync('keep');
      final store = DocumentsImageStore(documents: () async => root);
      await store.delete(['../precious.txt', other.path]);
      expect(other.existsSync(), isTrue);
    });
  });

  group('repairNetworkPath', () {
    late SharedPreferences prefs;
    const key = SettingsController.engineNetworkPathKey;

    Future<void> withStored(String? path) async {
      SharedPreferences.setMockInitialValues({if (path != null) key: path});
      prefs = await SharedPreferences.getInstance();
    }

    test('keeps a path whose file exists', () async {
      final file = File('${root.path}/nn-1.nnue')..writeAsBytesSync([1]);
      await withStored(file.path);
      await repairNetworkPath(prefs, root);
      expect(prefs.getString(key), file.path);
    });

    test('follows the file when the app folder moved', () async {
      final file = File('${root.path}/nn-1.nnue')..writeAsBytesSync([1]);
      await withStored('/old/container/nn-1.nnue');
      await repairNetworkPath(prefs, root);
      expect(prefs.getString(key), file.path);
    });

    test('forgets a network file that is gone, so the built-in engine is used', () async {
      await withStored('/old/container/nn-1.nnue');
      await repairNetworkPath(prefs, root);
      expect(prefs.containsKey(key), isFalse);
    });

    test('does nothing without a stored path', () async {
      await withStored(null);
      await repairNetworkPath(prefs, root);
      expect(prefs.containsKey(key), isFalse);
    });
  });
}
