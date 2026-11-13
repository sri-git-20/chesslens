import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'collection_providers.dart';
import 'models.dart';

/// Where to save a puzzle: an existing collection or a new one.
class SaveTarget {
  const SaveTarget.existing(int this.collectionId) : newName = null;
  const SaveTarget.create(String this.newName) : collectionId = null;

  final int? collectionId;
  final String? newName;
}

/// Asks where to save. Returns `null` when cancelled. [suggestedName] fills
/// the new-collection field.
Future<SaveTarget?> showSaveToCollectionDialog(
  BuildContext context, {
  String? suggestedName,
}) {
  return showDialog<SaveTarget>(
    context: context,
    builder: (context) => SaveToCollectionDialog(suggestedName: suggestedName),
  );
}

class SaveToCollectionDialog extends ConsumerStatefulWidget {
  const SaveToCollectionDialog({super.key, this.suggestedName});

  final String? suggestedName;

  @override
  ConsumerState<SaveToCollectionDialog> createState() => _SaveToCollectionDialogState();
}

class _SaveToCollectionDialogState extends ConsumerState<SaveToCollectionDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.suggestedName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _create() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(SaveTarget.create(name));
  }

  @override
  Widget build(BuildContext context) {
    final collections = ref.watch(collectionsProvider);
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Save to collection'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'New collection',
                hintText: 'For example: Endgames, chapter 3',
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _create(),
            ),
            collections.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 16),
                child: LinearProgressIndicator(),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Collections could not be loaded.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
              data: (list) => list.isEmpty
                  ? const SizedBox.shrink()
                  : Flexible(child: _ExistingList(list: list)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _create,
          child: const Text('Create and save'),
        ),
      ],
    );
  }
}

class _ExistingList extends StatelessWidget {
  const _ExistingList({required this.list});

  final List<CollectionSummary> list;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 16, bottom: 4),
          child: Text('Or add to an existing one'),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final summary in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(summary.collection.name),
                  subtitle: Text(puzzleCountLabel(summary.puzzleCount)),
                  onTap: () => Navigator.of(context)
                      .pop(SaveTarget.existing(summary.collection.id)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String puzzleCountLabel(int count) => count == 1 ? '1 puzzle' : '$count puzzles';
