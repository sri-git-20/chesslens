import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'report_builder.dart';
import 'report_screen.dart';
import 'reporting.dart';

/// Wraps the Home screen. If the last session ended badly, asks once whether
/// to send a report.
class CrashReportPrompt extends ConsumerStatefulWidget {
  const CrashReportPrompt({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CrashReportPrompt> createState() => _CrashReportPromptState();
}

class _CrashReportPromptState extends ConsumerState<CrashReportPrompt> {
  @override
  void initState() {
    super.initState();
    final reporting = ref.read(reportingProvider);
    if (reporting != null && reporting.previousSessionProblem) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask(reporting));
    }
  }

  Future<void> _ask(Reporting reporting) async {
    if (!mounted) return;
    final send = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send a report?'),
        content: const Text('ChessLens closed unexpectedly last time. Send a report?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Send report'),
          ),
        ],
      ),
    );
    reporting.promptDismissed();
    if (send == true && mounted) {
      await openReportScreen(context, kind: ReportKind.crash);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
