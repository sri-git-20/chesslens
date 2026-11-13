import 'dart:typed_data';

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/analysis_screen.dart';
import '../chess/fen_input.dart';
import '../collections/collection_providers.dart';
import '../collections/models.dart';
import '../collections/save_dialog.dart';
import '../export/export_menu.dart';
import '../export/pgn.dart';
import '../play/play_screen.dart';
import '../report/report_builder.dart';
import '../report/report_screen.dart';
import '../solve/solve_screen.dart';
import 'board_providers.dart';
import 'board_size.dart';
import 'piece_palette.dart';
import 'review_args.dart';
import 'review_model.dart';

/// Opens the Review screen for [args].
Future<T?> openReview<T>(BuildContext context, ReviewArgs args) {
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(builder: (_) => ReviewScreen(args: args)),
  );
}

/// Check and correct a position before using it: edit pieces, choose the side
/// to move and castling rights, then analyze, play, solve or save it.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.args});

  final ReviewArgs args;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  late final ReviewModel _model;
  EditorTool _tool = const MoveTool();
  bool _saving = false;
  final GlobalKey _boardKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    final (model, error) = ReviewModel.fromArgs(widget.args);
    _model = model;
    if (error != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showMessage(error));
    }
    final puzzleId = widget.args.puzzleId;
    if (puzzleId != null) _loadSavedCastling(puzzleId);
  }

  Future<void> _loadSavedCastling(int puzzleId) async {
    try {
      final puzzle = await ref.read(collectionRepositoryProvider).getPuzzle(puzzleId);
      if (puzzle == null || !mounted) return;
      final input = parseFenInput(puzzle.fen);
      _model.applyCastling(input.castling);
    } catch (_) {
      // The inferred castling rights are a fine fallback.
    }
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _onEditedSquare(Square square) {
    final tool = _tool;
    switch (tool) {
      case PlaceTool(:final piece):
        _model.putPiece(square, piece);
      case EraseTool():
        _model.removePiece(square);
      case MoveTool():
        break;
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _save() async {
    final fen = _model.fullFen;
    if (fen == null || _saving) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(collectionRepositoryProvider);
      final puzzleId = widget.args.puzzleId;
      if (puzzleId != null) {
        final existing = await repository.getPuzzle(puzzleId);
        if (existing == null) {
          _showMessage('This puzzle no longer exists.');
          return;
        }
        await repository.updatePuzzle(
          existing.copyWith(fen: fen, orientation: _model.orientation),
        );
        ref.invalidate(collectionsProvider);
        _showMessage('Changes saved.');
        return;
      }

      final target = await showSaveToCollectionDialog(context);
      if (target == null || !mounted) return;
      final images = ref.read(imageStoreProvider);
      Collection? created;
      var savedName = '';
      String? cropPath;
      try {
        final Collection collection;
        if (target.newName != null) {
          collection = created = await repository.createCollection(target.newName!);
        } else {
          final all = await repository.listCollections();
          collection = all
              .firstWhere((summary) => summary.collection.id == target.collectionId)
              .collection;
        }
        final crop = widget.args.sourceCrop;
        if (crop != null) cropPath = await images.saveCrop(crop);
        await repository.addPuzzle(
          Puzzle(
            id: 0,
            collectionId: collection.id,
            fen: fen,
            orientation: _model.orientation,
            cropImagePath: cropPath,
            createdAt: DateTime.now(),
          ),
        );
        savedName = collection.name;
      } catch (_) {
        // Do not leave an empty collection or an unused image behind.
        try {
          if (cropPath != null) await images.delete([cropPath]);
          if (created != null) await repository.deleteCollection(created.id);
        } catch (_) {}
        rethrow;
      }
      if (!mounted) return;
      ref.invalidate(collectionsProvider);
      _showMessage('Saved to "$savedName".');
    } catch (error) {
      _showMessage('Could not save the position. $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reportRecognition() {
    final crop = widget.args.sourceCrop;
    if (crop == null) return;
    openReportScreen(
      context,
      kind: ReportKind.recognition,
      recognition: RecognitionReportData(
        detectedFen: widget.args.boardFen,
        correctedFen: _model.fullFen ?? _model.board.fen,
        image: crop,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boardSettings = ref.watch(chessboardSettingsProvider);
    final editing = widget.args.puzzleId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review'),
        actions: [
          ExportMenuButton(
            fen: () => _model.fullFen,
            pgn: () {
              final fen = _model.fullFen;
              return fen == null ? null : buildPgn(fen: fen);
            },
            boardKey: _boardKey,
            onReportRecognition:
                widget.args.sourceCrop == null ? null : _reportRecognition,
          ),
          IconButton(
            tooltip: 'Flip board',
            icon: const Icon(Icons.swap_vert),
            onPressed: _model.flip,
          ),
        ],
      ),
      bottomNavigationBar: ListenableBuilder(
        listenable: _model,
        builder: (context, _) {
          final fen = _model.fullFen;
          final legal = fen != null;
          final theme = Theme.of(context);
          return Material(
            color: theme.colorScheme.surfaceContainer,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!legal)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          'Fix the position above to analyze, play or solve.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.analytics_outlined),
                            label: const Text('Analyze'),
                            onPressed: fen == null
                                ? null
                                : () => _open(AnalysisScreen(
                                      fen: fen,
                                      orientation: _model.orientation,
                                    )),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.smart_toy_outlined),
                            label: const Text('Play'),
                            onPressed: fen == null
                                ? null
                                : () => _open(PlayScreen(
                                      fen: fen,
                                      orientation: _model.orientation,
                                    )),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.extension_outlined),
                            label: const Text('Solve'),
                            onPressed: fen == null
                                ? null
                                : () => _open(SolveScreen(
                                      fen: fen,
                                      orientation: _model.orientation,
                                      puzzleId: widget.args.puzzleId,
                                    )),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.bookmark_add_outlined),
                      label: Text(editing ? 'Save changes' : 'Save to collection'),
                      onPressed: legal && !_saving ? _save : null,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _model,
          builder: (context, _) {
            final fen = _model.fullFen;
            final legal = fen != null;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                if (widget.args.sourceCrop != null) ...[
                  _SourceCrop(bytes: widget.args.sourceCrop!),
                  const SizedBox(height: 12),
                ],
                BoardSize(
                  maxHeightFraction: 0.5,
                  builder: (context, size) => RepaintBoundary(
                    key: _boardKey,
                    child: ChessboardEditor(
                    size: size,
                    orientation: _model.orientation,
                    pieces: _model.pieces,
                    settings: boardSettings,
                    pointerMode: _tool is MoveTool
                        ? EditorPointerMode.drag
                        : EditorPointerMode.edit,
                    squareHighlights: {
                      for (final square in _model.flagged) square: const _AmberOutline(),
                    },
                    onEditedSquare: _onEditedSquare,
                    onDroppedPiece: _model.dropPiece,
                    onDiscardedPiece: _model.removePiece,
                    ),
                  ),
                ),
                if (_model.flagged.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Squares outlined in amber were hard to read. Please check them.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                const SizedBox(height: 12),
                PiecePalette(
                  tool: _tool,
                  pieceAssets: boardSettings.pieceAssets,
                  onToolChanged: (tool) => setState(() => _tool = tool),
                ),
                const SizedBox(height: 16),
                SegmentedButton<Side>(
                  segments: const [
                    ButtonSegment(value: Side.white, label: Text('White to move')),
                    ButtonSegment(value: Side.black, label: Text('Black to move')),
                  ],
                  selected: {_model.turn},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => _model.setTurn(selection.first),
                ),
                const SizedBox(height: 12),
                _CastlingChips(model: _model),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Clear board'),
                        onPressed: _model.clear,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Start position'),
                        onPressed: _model.startPosition,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _LegalityMessages(problems: _model.report.problems, legal: legal),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Outlines a square in amber: the recognizer was not sure about it.
class _AmberOutline extends SquareHighlight {
  const _AmberOutline()
      : super(details: const HighlightDetails(solidColor: Color(0x00000000)));

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFFFB300), width: 3),
      ),
    );
  }
}

class _SourceCrop extends StatelessWidget {
  const _SourceCrop({required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text('Original diagram', style: theme.textTheme.labelLarge),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SizedBox(
              width: double.infinity,
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _CastlingChips extends StatelessWidget {
  const _CastlingChips({required this.model});

  final ReviewModel model;

  @override
  Widget build(BuildContext context) {
    final available = model.availableCastling;
    Widget chip(String label, Side side, CastlingSide castlingSide) {
      return FilterChip(
        label: Text(label),
        selected: model.castling.has(side, castlingSide),
        onSelected: available.has(side, castlingSide)
            ? (value) => model.setCastling(side, castlingSide, value)
            : null,
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Castling', style: Theme.of(context).textTheme.labelLarge),
        chip('White O-O', Side.white, CastlingSide.king),
        chip('White O-O-O', Side.white, CastlingSide.queen),
        chip('Black O-O', Side.black, CastlingSide.king),
        chip('Black O-O-O', Side.black, CastlingSide.queen),
      ],
    );
  }
}

class _LegalityMessages extends StatelessWidget {
  const _LegalityMessages({required this.problems, required this.legal});

  final List<String> problems;
  final bool legal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (legal) {
      return Row(
        children: [
          Icon(Icons.check_circle_outline, color: scheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('The position is legal.')),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final problem in problems)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.error_outline, size: 20, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(child: Text(problem, style: TextStyle(color: scheme.error))),
              ],
            ),
          ),
      ],
    );
  }
}
