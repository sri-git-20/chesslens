import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'pgn.dart';

void _message(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<void> copyToClipboard(BuildContext context, String text, String what) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
    _message(context, '$what copied.');
  } catch (error) {
    _message(context, 'Could not copy. $error');
  }
}

Future<void> openInLichess(BuildContext context, String fen) async {
  final url = lichessAnalysisUrl(fen);
  var opened = false;
  try {
    opened = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) {
    await Clipboard.setData(ClipboardData(text: url));
    _message(context, 'Could not open the browser. The link was copied.');
  }
}

/// Renders the [RepaintBoundary] with [boundaryKey] to PNG bytes.
Future<Uint8List?> capturePng(GlobalKey boundaryKey, {double pixelRatio = 3}) async {
  final object = boundaryKey.currentContext?.findRenderObject();
  if (object is! RenderRepaintBoundary) return null;
  final image = await object.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

Future<File> _writeTemp(String name, List<int> bytes) async {
  final folder = Directory(p.join((await getTemporaryDirectory()).path, 'export'));
  await folder.create(recursive: true);
  final file = File(p.join(folder.path, name));
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<void> shareBoardImage(BuildContext context, GlobalKey boundaryKey) async {
  try {
    final png = await capturePng(boundaryKey);
    if (png == null) {
      _message(context, 'The board is not ready yet.');
      return;
    }
    final file = await _writeTemp('chesslens-board.png', png);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'image/png')]),
    );
  } catch (error) {
    _message(context, 'Could not share the board image. $error');
  }
}

/// Writes [pgn] to a temporary `.pgn` file named after [name] and shares it.
Future<void> sharePgnFile(BuildContext context, String name, String pgn) async {
  try {
    final file = await _writeTemp('${safeFileName(name)}.pgn', utf8.encode(pgn));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/x-chess-pgn')],
        subject: name,
      ),
    );
  } catch (error) {
    _message(context, 'Could not export the PGN. $error');
  }
}
