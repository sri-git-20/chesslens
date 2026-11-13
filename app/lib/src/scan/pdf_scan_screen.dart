import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart' show PdfDocument, PdfPage, pdfrxFlutterInitialize;

import 'recognition_service.dart';
import 'scan_engine.dart';
import 'scan_save.dart';
import 'scan_selection_screen.dart';
import 'scan_session.dart';
import 'scan_widgets.dart';

/// Resolution used to read selected pages.
const double _scanDpi = 200;

/// Longest side of a rendered page, in pixels.
const double _scanMaxSide = 2400;

/// Longest side of a thumbnail, in pixels.
const double _thumbSide = 320;

/// Picks a PDF, shows a grid of page thumbnails to select from, then reads
/// the selected pages and opens the selection screen.
class PdfScanScreen extends ConsumerStatefulWidget {
  const PdfScanScreen({super.key});

  @override
  ConsumerState<PdfScanScreen> createState() => _PdfScanScreenState();
}

enum _Phase { opening, grid, reading, error }

class _PdfScanScreenState extends ConsumerState<PdfScanScreen> {
  _Phase _phase = _Phase.opening;
  PdfDocument? _document;
  String _name = 'PDF';
  final Set<int> _selected = {};
  String _status = '';
  String? _detail;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _pick();
  }

  @override
  void dispose() {
    final document = _document;
    if (document != null) unawaited(document.dispose());
    super.dispose();
  }

  Future<void> _pick() async {
    setState(() => _phase = _Phase.opening);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (file == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      await pdfrxFlutterInitialize();
      final path = file.path;
      final PdfDocument document;
      if (path != null) {
        document = await PdfDocument.openFile(path);
      } else {
        document = await PdfDocument.openData(
          await file.readAsBytes(),
          sourceName: file.name,
        );
      }
      if (!mounted) {
        unawaited(document.dispose());
        return;
      }
      if (document.pages.isEmpty) {
        unawaited(document.dispose());
        setState(() {
          _phase = _Phase.error;
          _error = 'This PDF has no pages.';
        });
        return;
      }
      final old = _document;
      if (old != null) unawaited(old.dispose());
      setState(() {
        _document = document;
        _name = file.name;
        _selected.clear();
        _phase = _Phase.grid;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = 'The PDF could not be opened. It may be damaged or protected '
            'by a password. $error';
      });
    }
  }

  void _toggle(int pageNumber) {
    setState(() {
      if (!_selected.remove(pageNumber)) _selected.add(pageNumber);
    });
  }

  void _selectAll() {
    final document = _document;
    if (document == null) return;
    setState(() {
      if (_selected.length == document.pages.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(List.generate(document.pages.length, (i) => i + 1));
      }
    });
  }

  Future<BgraInput> _render(PdfPage page) async {
    var scale = _scanDpi / 72;
    final longest = math.max(page.width, page.height);
    if (longest * scale > _scanMaxSide) scale = _scanMaxSide / longest;
    final width = math.max(1, (page.width * scale).round());
    final height = math.max(1, (page.height * scale).round());
    final image = await page.render(
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
    );
    if (image == null) {
      throw const ScanException('A page could not be drawn.');
    }
    try {
      return BgraInput(image.width, image.height, Uint8List.fromList(image.pixels));
    } finally {
      image.dispose();
    }
  }

  Future<void> _scan() async {
    final document = _document;
    if (document == null || _selected.isEmpty) return;
    final service = ref.read(recognitionServiceProvider);
    final session = ScanSession(service);
    final numbers = _selected.toList()..sort();
    setState(() {
      _phase = _Phase.reading;
      _status = 'Reading page 1 of ${numbers.length}...';
      _detail = null;
    });
    try {
      for (var i = 0; i < numbers.length; i++) {
        final number = numbers[i];
        if (!mounted) {
          session.dispose();
          return;
        }
        setState(() {
          _status = 'Reading page ${i + 1} of ${numbers.length}...';
          _detail = session.boards.isEmpty
              ? null
              : 'Found ${_diagrams(session.boards.length)}';
        });
        final input = await _render(document.pages[number - 1]);
        final key = nextPageKey();
        final analysis = await service.analyzePage(key, input);
        session.addPage(
          ScanPage(
            key: key,
            jpeg: analysis.jpeg,
            width: analysis.width,
            height: analysis.height,
            pageNumber: number,
            label: 'Page $number',
          ),
          analysis.boards,
        );
      }
    } catch (error) {
      session.dispose();
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = error is ScanException ? error.message : 'Reading failed. $error';
      });
      return;
    }
    if (!mounted) {
      session.dispose();
      return;
    }
    // Even with no boards found, the pages stay so that "Add a board" works.
    unawaited(
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => ScanSelectionScreen(
            session: session,
            collectionName: pdfCollectionName(_name, numbers),
          ),
        ),
      ),
    );
  }

  String _diagrams(int n) => n == 1 ? '1 diagram' : '$n diagrams';

  @override
  Widget build(BuildContext context) {
    final document = _document;
    final Widget body;
    switch (_phase) {
      case _Phase.opening:
        body = const ScanProgressView(message: 'Opening the PDF...');
      case _Phase.reading:
        body = ScanProgressView(message: _status, detail: _detail);
      case _Phase.error:
        body = ScanMessageView(
          icon: Icons.error_outline,
          title: 'PDF scanning failed',
          body: _error,
          primaryLabel: document == null ? 'Choose another PDF' : 'Back to the pages',
          onPrimary: document == null
              ? _pick
              : () => setState(() => _phase = _Phase.grid),
          secondaryLabel: 'Close',
          onSecondary: () => Navigator.of(context).pop(),
        );
      case _Phase.grid:
        body = _PageGrid(
          document: document!,
          selected: _selected,
          onToggle: _toggle,
          onSelectAll: _selectAll,
          onScan: _scan,
        );
    }
    return Scaffold(
      appBar: AppBar(title: Text(_phase == _Phase.grid ? _name : 'PDF')),
      body: SafeArea(child: body),
    );
  }
}

class _PageGrid extends StatelessWidget {
  const _PageGrid({
    required this.document,
    required this.selected,
    required this.onToggle,
    required this.onSelectAll,
    required this.onScan,
  });

  final PdfDocument document;
  final Set<int> selected;
  final void Function(int) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = document.pages.length;
    final all = selected.length == total;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Tap the pages with diagrams.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: onSelectAll,
                child: Text(all ? 'Select none' : 'Select all'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
            ),
            itemCount: total,
            itemBuilder: (context, index) {
              final number = index + 1;
              return _PageThumb(
                key: ValueKey(number),
                page: document.pages[index],
                selected: selected.contains(number),
                onTap: () => onToggle(number),
              );
            },
          ),
        ),
        Material(
          color: theme.colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: selected.isEmpty ? null : onScan,
                child: Text(
                  selected.length == 1 ? 'Scan 1 page' : 'Scan ${selected.length} pages',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PageThumb extends StatefulWidget {
  const _PageThumb({
    super.key,
    required this.page,
    required this.selected,
    required this.onTap,
  });

  final PdfPage page;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PageThumb> createState() => _PageThumbState();
}

class _PageThumbState extends State<_PageThumb> {
  ui.Image? _image;
  bool _failed = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final page = widget.page;
      final scale = _thumbSide / math.max(page.width, page.height);
      final rendered = await page.render(
        fullWidth: math.max(1.0, (page.width * scale).roundToDouble()),
        fullHeight: math.max(1.0, (page.height * scale).roundToDouble()),
      );
      if (rendered == null) throw StateError('no image');
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        Uint8List.fromList(rendered.pixels),
        rendered.width,
        rendered.height,
        ui.PixelFormat.bgra8888,
        completer.complete,
      );
      rendered.dispose();
      final image = await completer.future;
      if (_disposed) {
        image.dispose();
        return;
      }
      setState(() => _image = image);
    } catch (_) {
      if (!_disposed) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final image = _image;
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.selected ? scheme.primary : scheme.outlineVariant,
                width: widget.selected ? 3 : 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: image != null
                  ? RawImage(image: image, fit: BoxFit.contain)
                  : Center(
                      child: _failed
                          ? const Icon(Icons.broken_image_outlined, color: Colors.black45)
                          : const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                    ),
            ),
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${widget.page.pageNumber}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
          if (widget.selected)
            Positioned(
              right: 6,
              top: 6,
              child: CircleAvatar(
                radius: 12,
                backgroundColor: scheme.primary,
                child: Icon(Icons.check, size: 16, color: scheme.onPrimary),
              ),
            ),
        ],
      ),
    );
  }
}
