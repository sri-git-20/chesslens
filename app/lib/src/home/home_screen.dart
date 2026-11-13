import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import '../board/review_args.dart';
import '../board/review_screen.dart';
import '../board/static_board.dart';
import '../chess/board_utils.dart';
import '../collections/collection_detail_screen.dart';
import '../collections/collection_providers.dart';
import '../collections/models.dart';
import '../collections/save_dialog.dart';
import '../scan/scan_launcher.dart';
import '../settings/settings_screen.dart';
import 'paste_fen_dialog.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _pasteFen(BuildContext context) async {
    final input = await showPasteFenDialog(context);
    if (input == null || !context.mounted) return;
    await openReview<void>(
      context,
      ReviewArgs(
        boardFen: input.placement,
        sideToMove: input.turn,
        orientation: Side.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final collections = ref.watch(collectionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(appName),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text('Scan a chess diagram', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'From a book page, a screenshot or a scanned PDF. '
            'Everything stays on your phone.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          _SourceTile(
            icon: Icons.photo_camera_outlined,
            title: 'Camera',
            subtitle: 'Photograph a page or a single diagram',
            onTap: () => scanFromCamera(context),
          ),
          _SourceTile(
            icon: Icons.photo_library_outlined,
            title: 'Gallery',
            subtitle: 'Pick a photo or screenshot',
            onTap: () => scanFromGallery(context),
          ),
          _SourceTile(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF',
            subtitle: 'Choose pages from a scanned book',
            onTap: () => scanFromPdf(context),
          ),
          _SourceTile(
            icon: Icons.content_paste_outlined,
            title: 'Paste FEN',
            subtitle: 'Set up a position from text',
            onTap: () => _pasteFen(context),
          ),
          _SourceTile(
            icon: Icons.grid_on_outlined,
            title: 'Set up a position',
            subtitle: 'Start from an empty board',
            onTap: () => openReview<void>(
              context,
              const ReviewArgs(boardFen: emptyPlacement),
            ),
          ),
          const SizedBox(height: 24),
          Text('Collections', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          collections.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => _InfoCard(
              text: 'Collections could not be loaded.',
              color: theme.colorScheme.errorContainer,
              textColor: theme.colorScheme.onErrorContainer,
            ),
            data: (list) => list.isEmpty
                ? _InfoCard(
                    text: 'No collections yet. Save a position from Review to '
                        'start one.',
                    color: theme.colorScheme.surfaceContainerHighest,
                  )
                : Column(
                    children: [
                      for (final summary in list)
                        _CollectionTile(
                          summary: summary,
                          onTap: () async {
                            await Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                builder: (_) => CollectionDetailScreen(
                                  collection: summary.collection,
                                ),
                              ),
                            );
                            ref.invalidate(collectionsProvider);
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text, required this.color, this.textColor});

  final String text;
  final Color color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(text, style: TextStyle(color: textColor)),
      ),
    );
  }
}

class _CollectionTile extends StatelessWidget {
  const _CollectionTile({required this.summary, required this.onTap});

  final CollectionSummary summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = summary.previewFen;
    final solved = summary.puzzleCount == 0
        ? ''
        : ' · ${summary.solvedCount} solved';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minVerticalPadding: 10,
        leading: preview == null
            ? CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: const Icon(Icons.folder_outlined),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: StaticBoard(fen: preview, size: 48, showCoordinates: false),
              ),
        title: Text(summary.collection.name),
        subtitle: Text('${puzzleCountLabel(summary.puzzleCount)}$solved'),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minVerticalPadding: 14,
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
