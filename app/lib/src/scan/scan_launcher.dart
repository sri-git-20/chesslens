import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
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

/// On Android the system can kill the app while the camera or gallery is
/// open (low memory). The photo then arrives after the app restarted and no
/// call is waiting for it; this picks it up and scans it.
Future<void> recoverLostPick(BuildContext context) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final response = await ImagePicker().retrieveLostData();
    if (response.isEmpty) return;
    final files = response.files;
    if (files == null || files.isEmpty) {
      if (context.mounted) {
        showScanMessage(context, 'The last photo could not be recovered. Please try again.');
      }
      return;
    }
    final bytes = await files.first.readAsBytes();
    if (!context.mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ScanRunScreen(bytes: bytes)),
    );
  } catch (_) {
    // Nothing to recover, or the plugin is not available (tests, other platforms).
  }
}

/// Runs [recoverLostPick] once when it is first shown.
class LostPickRecovery extends StatefulWidget {
  const LostPickRecovery({super.key, required this.child});

  final Widget child;

  @override
  State<LostPickRecovery> createState() => _LostPickRecoveryState();
}

class _LostPickRecoveryState extends State<LostPickRecovery> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) recoverLostPick(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
