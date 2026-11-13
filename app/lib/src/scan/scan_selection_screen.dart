import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../collections/collection_detail_screen.dart';
import '../collections/collection_providers.dart';
import '../collections/save_dialog.dart';
import 'geometry.dart';
import 'region_screens.dart';
import 'scan_engine.dart' show ScanException;
import 'scan_save.dart';
import 'scan_session.dart';
import 'scan_widgets.dart';

/// Shows the scanned pages with numbered boxes. The user ticks the diagrams
/// to load, fixes corners, adds missed boards and saves them to a collection.
///
/// Takes ownership of [session] and disposes it.
class ScanSelectionScreen extends ConsumerStatefulWidget {
  const ScanSelectionScreen({
    super.key,
    required this.session,
    required this.collectionName,
  });

  final ScanSession session;

  /// Suggested name for the new collection.
  final String collectionName;

  @override
  ConsumerState<ScanSelectionScreen> createState() => _ScanSelectionScreenState();
}

class _ScanSelectionScreenState extends ConsumerState<ScanSelectionScreen> {
  final TextEditingController _range = TextEditingController();
  String? _rangeError;
  bool _saving = false;

  ScanSession get _session => widget.session;

  @override
  void dispose() {
    _range.dispose();
    _session.dispose();
    super.dispose();
  }

  void _applyRange() {
    final error = _session.selectRange(_range.text);
    setState(() => _rangeError = error);
  }

  Future<void> _edit(ScanBoard board) async {
    final quad = await Navigator.of(context).push<Quad>(
      MaterialPageRoute(
        builder: (_) => QuadEditorScreen(page: board.page, quad: board.quad),
      ),
    );
    if (quad == null || !mounted) return;
    try {
      await _session.adjustCorners(board, quad);
    } catch (error) {
      if (mounted) showScanMessage(context, _describe(error));
    }
  }

  Future<void> _add(ScanPage page) async {
    final region = await Navigator.of(context).push<Quad>(
      MaterialPageRoute(builder: (_) => RegionPickerScreen(page: page)),
    );
    if (region == null || !mounted) return;
    try {
      await _session.addBoardIn(page, region);
    } catch (error) {
      if (mounted) showScanMessage(context, _describe(error));
    }
  }

  String _describe(Object error) =>
      error is ScanException ? error.message : 'Reading the board failed. $error';

  Future<void> _load() async {
    final boards = _session.selected;
    if (boards.isEmpty || _saving) return;
    final target = await showSaveToCollectionDialog(
      context,
      suggestedName: widget.collectionName,
    );
    if (target == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final collection = await saveScannedBoards(
        repository: ref.read(collectionRepositoryProvider),
        images: ref.read(imageStoreProvider),
        boards: boards,
        target: target,
      );
      ref.invalidate(collectionsProvider);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => CollectionDetailScreen(collection: collection),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        showScanMessage(context, 'Could not save the puzzles. $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose diagrams')),
      body: ListenableBuilder(
        listenable: _session,
        builder: (context, _) {
          final busy = _session.busy != null || _saving;
          final count = _session.selected.length;
          return Column(
            children: [
              if (busy) const LinearProgressIndicator(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                  children: [
                    for (final page in _session.pages)
                      _PageCard(
                        page: page,
                        boards: _session.boardsOn(page),
                        enabled: !busy,
                        onToggle: _session.toggle,
                        onEdit: _edit,
                        onAdd: () => _add(page),
                      ),
                  ],
                ),
              ),
              _SelectionBar(
                total: _session.boards.length,
                count: count,
                controller: _range,
                rangeError: _rangeError,
                enabled: !busy,
                onAll: () {
                  _range.clear();
                  setState(() => _rangeError = null);
                  _session.selectAll();
                },
                onNone: () {
                  _range.clear();
                  setState(() => _rangeError = null);
                  _session.selectNone();
                },
                onRange: _applyRange,
                onLoad: _load,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.total,
    required this.count,
    required this.controller,
    required this.rangeError,
    required this.enabled,
    required this.onAll,
    required this.onNone,
    required this.onRange,
    required this.onLoad,
  });

  final int total;
  final int count;
  final TextEditingController controller;
  final String? rangeError;
  final bool enabled;
  final VoidCallback onAll;
  final VoidCallback onNone;
  final VoidCallback onRange;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  TextButton(onPressed: enabled ? onAll : null, child: const Text('Select all')),
                  TextButton(onPressed: enabled ? onNone : null, child: const Text('Select none')),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: enabled,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => onRange(),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: 'Range',
                        hintText: '3-7, 9',
                        errorText: rangeError,
                        suffixIcon: IconButton(
                          tooltip: 'Select this range',
                          icon: const Icon(Icons.check),
                          onPressed: enabled ? onRange : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: enabled && count > 0 ? onLoad : null,
                  child: Text(count == 1 ? 'Load 1 puzzle' : 'Load $count puzzles'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.page,
    required this.boards,
    required this.enabled,
    required this.onToggle,
    required this.onEdit,
    required this.onAdd,
  });

  final ScanPage page;
  final List<ScanBoard> boards;
  final bool enabled;
  final void Function(ScanBoard) onToggle;
  final void Function(ScanBoard) onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = boards.length == 1 ? '1 diagram' : '${boards.length} diagrams';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: theme.colorScheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    page.label.isEmpty ? found : '${page.label} · $found',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: enabled ? onAdd : null,
                  icon: const Icon(Icons.add_box_outlined),
                  label: const Text('Add a board'),
                ),
              ],
            ),
          ),
          if (boards.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text('No diagram found on this page.'),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final scale = constraints.maxWidth / page.width;
              final height = page.height * scale;
              final pixelRatio = MediaQuery.devicePixelRatioOf(context);
              return SizedBox(
                width: constraints.maxWidth,
                height: height,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Image.memory(
                        page.jpeg,
                        fit: BoxFit.fill,
                        cacheWidth: (constraints.maxWidth * pixelRatio).round(),
                        gaplessPlayback: true,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _BoxesPainter(
                            quads: [for (final b in boards) b.quad],
                            selected: [for (final b in boards) b.selected],
                            scale: scale,
                            on: theme.colorScheme.primary,
                            off: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ),
                    for (final board in boards) ...[
                      Positioned(
                        left: board.quad.minX * scale,
                        top: board.quad.minY * scale,
                        width: board.quad.width * scale,
                        height: board.quad.height * scale,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: enabled ? () => onEdit(board) : null,
                        ),
                      ),
                      Positioned(
                        left: board.quad.minX * scale - 2,
                        top: board.quad.minY * scale - 2,
                        child: _Badge(
                          board: board,
                          onTap: enabled ? () => onToggle(board) : null,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          if (boards.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text('Tap a number to tick or untick. Tap a box to adjust its corners.'),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.board, required this.onTap});

  final ScanBoard board;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = board.selected;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected ? scheme.primary : scheme.surfaceContainerHighest,
            border: Border.all(
              color: board.reading.isLegal ? scheme.onPrimary : Colors.amber,
              width: 2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check, size: 14, color: scheme.onPrimary),
                const SizedBox(width: 2),
              ],
              Text(
                '${board.number}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
              if (!board.reading.isLegal) ...[
                const SizedBox(width: 2),
                const Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BoxesPainter extends CustomPainter {
  _BoxesPainter({
    required this.quads,
    required this.selected,
    required this.scale,
    required this.on,
    required this.off,
  });

  final List<Quad> quads;
  final List<bool> selected;
  final double scale;
  final Color on;
  final Color off;

  @override
  void paint(Canvas canvas, Size size) {
    for (var q = 0; q < quads.length; q++) {
      final path = Path();
      for (var i = 0; i < 4; i++) {
        final p = quads[q].points[i];
        if (i == 0) {
          path.moveTo(p.x * scale, p.y * scale);
        } else {
          path.lineTo(p.x * scale, p.y * scale);
        }
      }
      path.close();
      final color = selected[q] ? on : off;
      canvas.drawPath(
        path,
        Paint()..color = color.withValues(alpha: selected[q] ? 0.18 : 0.08),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected[q] ? 3 : 2,
      );
    }
  }

  @override
  bool shouldRepaint(_BoxesPainter old) => true;
}
