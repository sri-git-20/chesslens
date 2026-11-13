import 'package:chessground/chessground.dart' show PieceSet, PieceWidget;
import 'package:dartchess/dartchess.dart' show Piece;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import '../board/static_board.dart';
import '../chess/board_utils.dart';
import '../report/report_builder.dart';
import '../report/report_screen.dart';
import '../theme/board_themes.dart';
import 'network_tile.dart';
import 'settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const _SectionHeader('Appearance'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {settings.themeMode},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  controller.setThemeMode(selection.first),
            ),
          ),
          SwitchListTile(
            title: const Text('True black'),
            subtitle: const Text(
              'Pure black backgrounds in dark mode. Saves battery on OLED '
              'screens.',
            ),
            value: settings.trueBlack,
            onChanged: controller.setTrueBlack,
          ),
          const Divider(height: 32),
          const _SectionHeader('Board'),
          const _BoardPreview(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final boardTheme in BoardTheme.values)
                  ChoiceChip(
                    label: Text(boardTheme.label),
                    selected: settings.boardTheme == boardTheme,
                    onSelected: (_) => controller.setBoardTheme(boardTheme),
                  ),
              ],
            ),
          ),
          ListTile(
            title: const Text('Piece set'),
            subtitle: Text(settings.pieceSet.label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final chosen = await showDialog<PieceSet>(
                context: context,
                builder: (_) => _PieceSetDialog(selected: settings.pieceSet),
              );
              if (chosen != null) controller.setPieceSet(chosen);
            },
          ),
          SwitchListTile(
            title: const Text('Show coordinates'),
            subtitle: const Text('Letters and numbers on the board edge.'),
            value: settings.showCoordinates,
            onChanged: controller.setShowCoordinates,
          ),
          const Divider(height: 32),
          const _SectionHeader('Engine'),
          _ChoiceRow<int>(
            title: 'Threads',
            subtitle: 'More threads are faster but use more battery.',
            values: const [1, 2, 3, 4],
            selected: settings.engineThreads,
            label: (value) => '$value',
            onChanged: controller.setEngineThreads,
          ),
          _ChoiceRow<int>(
            title: 'Hash',
            subtitle: 'Memory for the engine, in MB.',
            values: hashOptionsMb,
            selected: settings.engineHashMb,
            label: (value) => '$value',
            onChanged: controller.setEngineHashMb,
          ),
          _ChoiceRow<int>(
            title: 'Lines in analysis',
            subtitle: 'How many best lines to show (MultiPV).',
            values: const [1, 2, 3],
            selected: settings.multiPv,
            label: (value) => '$value',
            onChanged: controller.setMultiPv,
          ),
          _DropdownTile(
            title: 'Depth limit',
            subtitle: 'Analysis stops at this depth.',
            values: depthLimitOptions,
            selected: settings.depthLimit,
            label: (value) => value == 0 ? 'No limit' : 'Depth $value',
            onChanged: controller.setDepthLimit,
          ),
          _DropdownTile(
            title: 'Time limit',
            subtitle: 'Analysis stops after this long.',
            values: timeLimitOptions,
            selected: settings.timeLimitSeconds,
            label: (value) => value == 0
                ? 'No limit'
                : (value >= 60 ? '${value ~/ 60} min' : '$value s'),
            onChanged: controller.setTimeLimitSeconds,
          ),
          const NetworkTile(),
          const Divider(height: 32),
          const _SectionHeader('Help'),
          ListTile(
            leading: const Icon(Icons.bug_report_outlined),
            title: const Text('Report a problem'),
            subtitle: const Text('Preview a message to the developer. Nothing is sent without you.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openReportScreen(context, kind: ReportKind.problem),
          ),
          const Divider(height: 32),
          const _SectionHeader('About'),
          const ListTile(
            title: Text('Version'),
            subtitle: Text('$appVersion (build $buildNumber)'),
          ),
          ListTile(
            title: const Text('Licences'),
            subtitle: const Text('GPLv3, Stockfish and other components'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(
              context: context,
              applicationName: appName,
              applicationVersion: '$appVersion (build $buildNumber)',
              applicationLegalese: legalese,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text(
              'ChessLens works offline and collects no data.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _BoardPreview extends StatelessWidget {
  const _BoardPreview();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: StaticBoard(fen: startPlacement, size: 200),
      ),
    );
  }
}

class _PieceSetDialog extends StatelessWidget {
  const _PieceSetDialog({required this.selected});

  final PieceSet selected;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Piece set'),
      children: [
        for (final set in PieceSet.values)
          ListTile(
            selected: set == selected,
            leading: PieceWidget(
              piece: Piece.whiteKnight,
              size: 36,
              pieceAssets: set.assets,
            ),
            title: Text(set.label),
            trailing: set == selected ? const Icon(Icons.check) : null,
            onTap: () => Navigator.of(context).pop(set),
          ),
      ],
    );
  }
}

/// A title with a row of choices below it.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyLarge),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SegmentedButton<T>(
            segments: [
              for (final value in values)
                ButtonSegment<T>(value: value, label: Text(label(value))),
            ],
            selected: {selected},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => onChanged(selection.first),
          ),
        ],
      ),
    );
  }
}

class _DropdownTile<T> extends StatelessWidget {
  const _DropdownTile({
    required this.title,
    required this.subtitle,
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: DropdownButton<T>(
        value: selected,
        underline: const SizedBox.shrink(),
        items: [
          for (final value in values)
            DropdownMenuItem<T>(value: value, child: Text(label(value))),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}
