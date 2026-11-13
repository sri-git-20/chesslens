import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'pdf_scan_screen.dart';
import 'scan_run_screen.dart';
import 'scan_widgets.dart';

/// Longest side asked from the picker, in pixels.
const double _pickerMaxSide = 2400;

/// Takes a photo and scans it.
Future<void> scanFromCamera(BuildContext context) =>
    _scanFromPicker(context, ImageSource.camera);

/// Picks an image from the gallery and scans it.
Future<void> scanFromGallery(BuildContext context) =>
    _scanFromPicker(context, ImageSource.gallery);

/// Picks a PDF and shows its pages to choose from.
Future<void> scanFromPdf(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => const PdfScanScreen()),
  );
}

Future<void> _scanFromPicker(BuildContext context, ImageSource source) async {
  final what = source == ImageSource.camera ? 'camera' : 'gallery';
  try {
    final file = await ImagePicker().pickImage(
      source: source,
      maxWidth: _pickerMaxSide,
      maxHeight: _pickerMaxSide,
      imageQuality: 95,
    );
    if (file == null || !context.mounted) return;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ScanRunScreen(bytes: bytes)),
    );
  } catch (error) {
    if (context.mounted) {
      showScanMessage(context, 'The $what could not be opened. $error');
    }
  }
}
