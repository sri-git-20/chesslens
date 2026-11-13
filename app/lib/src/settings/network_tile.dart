import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/network_download.dart';
import 'settings_controller.dart';

/// Shows which network the engine uses, and lets the user download the
/// full-strength one or go back to the built-in one.
class NetworkTile extends ConsumerWidget {
  const NetworkTile({super.key});

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(networkDownloadProvider.notifier);
    final size = await controller.checkSize();
    if (size == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download full network?'),
        content: Text('Download about ${formatMegabytes(size)}? Needs internet once.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await controller.download();
    if (ok && context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('The full network is now in use.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final path = ref.watch(settingsProvider.select((s) => s.engineNetworkPath));
    final size = ref.watch(installedNetworkSizeProvider).value;
    final state = ref.watch(networkDownloadProvider);
    final controller = ref.read(networkDownloadProvider.notifier);

    final Widget content;
    switch (state.status) {
      case NetworkStatus.checking:
        content = const _Busy(text: 'Checking the download size...');
      case NetworkStatus.downloading:
      case NetworkStatus.verifying:
        final verifying = state.status == NetworkStatus.verifying;
        final total = state.totalBytes;
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: verifying ? null : state.progress),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    verifying
                        ? 'Checking the file...'
                        : total == null
                            ? 'Downloading ${formatMegabytes(state.receivedBytes)}'
                            : 'Downloading ${formatMegabytes(state.receivedBytes)} '
                                'of ${formatMegabytes(total)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (!verifying)
                  TextButton(onPressed: controller.cancel, child: const Text('Cancel')),
              ],
            ),
          ],
        );
      case NetworkStatus.failed:
        content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(state.error ?? 'The download failed.',
                style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: () => _download(context, ref),
                  child: const Text('Try again'),
                ),
                TextButton(onPressed: controller.dismissError, child: const Text('Dismiss')),
              ],
            ),
          ],
        );
      case NetworkStatus.idle:
        content = path == null
            ? Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('Download full-strength network'),
                  onPressed: () => _download(context, ref),
                ),
              )
            : Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton(
                  onPressed: controller.useBuiltIn,
                  child: const Text('Use built-in network'),
                ),
              );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Network', style: theme.textTheme.bodyLarge),
          Text(
            networkLabel(path, size),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.primary),
          ),
          Text(
            path == null
                ? 'The light network works offline and is small. The full '
                    'network is stronger.'
                : 'Stronger analysis. Stored on this phone.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          content,
        ],
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(text),
      ],
    );
  }
}
