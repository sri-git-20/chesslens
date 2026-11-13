import 'package:flutter/material.dart';

import '../app_info.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  void _comingSoon(BuildContext context, String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('$what arrives in a later test build.')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            onTap: () => _comingSoon(context, 'Scanning'),
          ),
          _SourceTile(
            icon: Icons.photo_library_outlined,
            title: 'Gallery',
            subtitle: 'Pick a photo or screenshot',
            onTap: () => _comingSoon(context, 'Scanning'),
          ),
          _SourceTile(
            icon: Icons.picture_as_pdf_outlined,
            title: 'PDF',
            subtitle: 'Choose pages from a scanned book',
            onTap: () => _comingSoon(context, 'PDF import'),
          ),
          _SourceTile(
            icon: Icons.content_paste_outlined,
            title: 'Paste FEN',
            subtitle: 'Set up a position from text',
            onTap: () => _comingSoon(context, 'Position entry'),
          ),
          const SizedBox(height: 24),
          Text('Collections', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'No collections yet. Puzzles you load from a page are saved '
                'here.',
              ),
            ),
          ),
        ],
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
