import 'package:flutter/services.dart';

/// Loads a Flutter asset by name and returns its raw bytes.
Future<Uint8List> loadAssetBytes(String assetFileName) async {
  final rawAssetFile = await rootBundle.load(assetFileName);
  return rawAssetFile.buffer.asUint8List();
}
