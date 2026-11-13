import 'dart:typed_data';

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/analysis_screen.dart';
import '../board/review_args.dart';
import '../board/review_model.dart';
import '../board/review_screen.dart';
import 'geometry.dart';
import 'recognition_service.dart';
import 'region_screens.dart';
import 'scan_engine.dart';
import 'scan_save.dart';
import 'scan_selection_screen.dart';
import 'scan_session.dart';
import 'scan_widgets.dart';

/// Review arguments for one scanned board.
ReviewArgs reviewArgsFor(ScanBoard board) => ReviewArgs(
      boardFen: board.reading.placement,
      confidence: board.reading.confidence,
      sideToMove: Side.white,
      orientation: board.reading.orientation,
      sourceCrop: board.cropPng,
    );

/// Reads one image (a photo, screenshot or gallery pick). One board goes
/// straight to Review, several go to the selection screen.
class ScanRunScreen extends ConsumerStatefulWidget {
  const ScanRunScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  ConsumerState<ScanRunScreen> createState() => _ScanRunScreenState();
}

enum _Phase { reading, error, empty }

class _ScanRunScreenState extends ConsumerState<ScanRunScreen> {
  _Phase _phase = _Phase.reading;
  String _message = '';
  ScanSession? _session;
  ScanPage? _page;
  bool _handedOver = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    if (!_handedOver) _session?.dispose();
    super.dispose();
  }

  String _describe(Object error) =>
      error is ScanException ? error.message : 'Something went wrong. $error';

  Future<void> _run() async {
    setState(() => _phase = _Phase.reading);
    final service = ref.read(recognitionServiceProvider);
    try {
      final key = nextPageKey();
      final analysis = await service.analyzePage(key, EncodedInput(widget.bytes));
      if (!mounted) return;
      final page = ScanPage(
        key: key,
        jpeg: analysis.jpeg,
        width: analysis.width,
        height: analysis.height,
      );
      _session?.dispose();
      final session = ScanSession(service)..addPage(page, analysis.boards);
      _session = session;
      _page = page;
      if (session.boards.isEmpty) {
        setState(() => _phase = _Phase.empty);
      } else {
        _finish(session);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _message = _describe(error);
      });
    }
  }

  void _finish(ScanSession session) {
    final navigator = Navigator.of(context);
    if (session.boards.length == 1) {
      final args = reviewArgsFor(session.boards.single);
      // Every square read confidently and the position is legal: go straight
      // to the analysis board, with Edit position one tap away.
      final ready = confidentScanPosition(args);
      navigator.pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => ready == null
              ? ReviewScreen(args: args)
              : AnalysisScreen(
                  fen: ready.fen,
                  orientation: ready.args.orientation,
                  editArgs: ready.args,
                ),
        ),
      );
      return;
    }
    _handedOver = true;
    navigator.pushReplacement<void, void>(
      MaterialPageRoute(
        builder: (_) => ScanSelectionScreen(
          session: session,
          collectionName: scanCollectionName(DateTime.now()),
        ),
      ),
    );
  }

  Future<void> _selectManually() async {
    final page = _page;
    final session = _session;
    if (page == null || session == null) return;
    final region = await Navigator.of(context).push<Quad>(
      MaterialPageRoute(builder: (_) => RegionPickerScreen(page: page)),
    );
    if (region == null || !mounted) return;
    setState(() => _phase = _Phase.reading);
    try {
      final board = await session.addBoardIn(page, region);
      if (!mounted) return;
      if (board == null) return;
      _finish(session);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _message = _describe(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    switch (_phase) {
      case _Phase.reading:
        body = const ScanProgressView(message: 'Reading the image...');
      case _Phase.error:
        body = ScanMessageView(
          icon: Icons.error_outline,
          title: 'Scanning failed',
          body: _message,
          primaryLabel: 'Try again',
          onPrimary: _run,
          secondaryLabel: 'Back',
          onSecondary: () => Navigator.of(context).pop(),
        );
      case _Phase.empty:
        body = ScanMessageView(
          icon: Icons.search_off,
          title: 'No diagram found',
          body: 'Try a sharper photo, or draw a box around the board yourself.',
          primaryLabel: 'Select the board manually',
          onPrimary: _selectManually,
          secondaryLabel: 'Back',
          onSecondary: () => Navigator.of(context).pop(),
        );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
      body: SafeArea(child: body),
    );
  }
}
