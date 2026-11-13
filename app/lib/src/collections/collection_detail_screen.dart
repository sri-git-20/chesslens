import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../board/review_args.dart';
import '../board/review_screen.dart';
import '../board/static_board.dart';
import '../chess/fen_input.dart';
import '../export/pgn.dart';
import '../export/share_actions.dart';
import 'collection_providers.dart';
import 'models.dart';
import 'name_dialog.dart';

enum _MenuAction { rename, exportPgn, delete }

/// The puzzles of one collection as a grid of small boards.
class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({super.key, required this.collection});

  final Collection collection;

  @override
  ConsumerState<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends ConsumerState<CollectionDetailScreen> {
  late String _name = widget.collection.name;
  late Future<List<Puzzle>> _puzzles = _load();

  Future<List<Puzzle>> _load() =>
      ref.read(collectionRepositoryProvider).puzzlesIn(widget.collection.id);

  void _reload() {
    setState(() => _puzzles = _load());
    ref.invalidate(collectionsProvider);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _rename() async {
    final name = await showNameDialog(
      context,
      title: 'Rename collection',
      initial: _name,
    );
    if (name == null || name == _name) return;
    try {
      await ref.read(collectionRepositoryProvider).renameCollection(widget.collection.id, name);
      if (!mounted) return;
      setState(() => _name = name);
      ref.invalidate(collectionsProvider);
    } catch (error) {
      _message('Could not rename the collection. $error');
    }
  }

  Future<void> _exportPgn() async {
    try {
      final puzzles = await ref.read(collectionRepositoryProvider).puzzlesIn(widget.collection.id);
      if (puzzles.isEmpty) {
        _message('This collection has no puzzles to export.');
        return;
      }
      if (!mounted) return;
      await sharePgnFile(context, _name, buildCollectionPgn(_name, puzzles));
    } catch (error) {
      _message('Could not export the collection. $error');
    }
  }

  Future<void> _deleteCollection() async {
    final confirmed = await _confirm(
      title: 'Delete collection?',
      body: 'This deletes "$_name" and all its puzzles. This cannot be undone.',
    );
    if (confirmed != true) return;
    try {
      final orphans =
          await ref.read(collectionRepositoryProvider).deleteCollection(widget.collection.id);
      await ref.read(imageStoreProvider).delete(orphans);
      if (!mounted) return;
      ref.invalidate(collectionsProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      _message('Could not delete the collection. $error');
    }
  }

  Future<void> _deletePuzzle(Puzzle puzzle) async {
    final confirmed = await _confirm(
      title: 'Delete puzzle?',
      body: 'This puzzle is removed from "$_name".',
    );
    if (confirmed != true) return;
    try {
      final orphans = await ref.read(collectionRepositoryProvider).deletePuzzle(puzzle.id);
      await ref.read(imageStoreProvider).delete(orphans);
      if (!mounted) return;
      _reload();
    } catch (error) {
      _message('Could not delete the puzzle. $error');
    }
  }

  Future<bool?> _confirm({required String title, required String body}) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _open(Puzzle puzzle) async {
    FenInput input;
    try {
      input = parseFenInput(puzzle.fen);
    } on FenInputException catch (error) {
      _message('This puzzle could not be opened. ${error.message}');
      return;
    }
    await openReview<void>(
      context,
      ReviewArgs(
        boardFen: input.placement,
        sideToMove: input.turn,
        orientation: puzzle.orientation,
        puzzleId: puzzle.id,
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          PopupMenuButton<_MenuAction>(
            tooltip: 'More',
            onSelected: (action) => switch (action) {
              _MenuAction.rename => _rename(),
              _MenuAction.exportPgn => _exportPgn(),
              _MenuAction.delete => _deleteCollection(),
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: _MenuAction.rename, child: Text('Rename')),
              PopupMenuItem(value: _MenuAction.exportPgn, child: Text('Export as PGN')),
              PopupMenuItem(value: _MenuAction.delete, child: Text('Delete collection')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<List<Puzzle>>(
        future: _puzzles,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'The puzzles could not be loaded.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            );
          }
          final puzzles = snapshot.data;
          if (puzzles == null) return const Center(child: CircularProgressIndicator());
          if (puzzles.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('This collection has no puzzles yet.'),
              ),
            );
          }
          return Column(
            children: [
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: puzzles.length,
                  itemBuilder: (context, index) => _PuzzleTile(
                    puzzle: puzzles[index],
                    number: index + 1,
                    onTap: () => _open(puzzles[index]),
                    onLongPress: () => _deletePuzzle(puzzles[index]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Tap a puzzle to open it. Press and hold to delete it.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PuzzleTile extends StatelessWidget {
  const _PuzzleTile({
    required this.puzzle,
    required this.number,
    required this.onTap,
    required this.onLongPress,
  });

  final Puzzle puzzle;
  final int number;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.maxWidth - 16;
            return Padding(
              padding: const EdgeInsets.all(8),
              child: Stack(
                children: [
                  StaticBoard(
                    fen: puzzle.fen,
                    size: size,
                    orientation: puzzle.orientation,
                    showCoordinates: false,
                  ),
                  Positioned(
                    left: 4,
                    top: 4,
                    child: _Badge(
                      color: scheme.surface,
                      child: Text(
                        '$number',
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  if (puzzle.status != PuzzleStatus.unsolved)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: _Badge(
                        color: puzzle.status == PuzzleStatus.solved
                            ? Colors.green.shade700
                            : scheme.error,
                        child: Icon(
                          puzzle.status == PuzzleStatus.solved ? Icons.check : Icons.close,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(11)),
      child: child,
    );
  }
}
