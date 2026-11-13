import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/engine_providers.dart';
import '../settings/settings_controller.dart';
import 'device_summary.dart';
import 'report_builder.dart';
import 'report_sender.dart';
import 'reporting.dart';

/// Opens the report preview.
Future<void> openReportScreen(
  BuildContext context, {
  required ReportKind kind,
  RecognitionReportData? recognition,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ReportScreen(kind: kind, recognition: recognition),
    ),
  );
}

/// Shows exactly what a report contains. Nothing leaves the phone until the
/// user taps Send in their mail app.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.kind, this.recognition});

  final ReportKind kind;
  final RecognitionReportData? recognition;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  final TextEditingController _description = TextEditingController();
  late final String _logText;
  late final String _engine;
  late final Future<DeviceSummary> _device;
  bool _includeImage = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _logText = buildLogText(
      appLog: ref.read(reportingProvider)?.log.read() ?? '',
      engineLines: ref.read(engineLogProvider).lines,
    );
    _engine = describeEngine(ref.read(settingsProvider));
    _device = ref.read(deviceSummaryProvider.future).catchError((Object _) => DeviceSummary.unknown);
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  ReportEnvironment _environment(DeviceSummary device) => ReportEnvironment(
        os: device.os,
        deviceModel: device.model,
        locale: WidgetsBinding.instance.platformDispatcher.locale.toLanguageTag(),
        engine: _engine,
      );

  Future<void> _send(DeviceSummary device) async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final message = ReportMessage(
        to: reportRecipient,
        subject: reportSubject(widget.kind),
        body: buildReportBody(
          kind: widget.kind,
          description: _description.text,
          environment: _environment(device),
          recognition: widget.recognition,
        ),
        attachments: buildAttachments(
          logText: _logText,
          recognition: widget.recognition,
          includeImage: _includeImage,
        ),
      );
      final sender = ref.read(reportSenderProvider);
      final reporting = ref.read(reportingProvider);
      final outcome = await sender.send(message);
      reporting?.reportSent(widget.kind.label);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            outcome == SendOutcome.mailApp
                ? 'Your mail app is open. Tap Send there to send the report.'
                : 'No mail app found. Choose where to share the report.',
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ref.read(reportingProvider)?.log.error('Could not open the report', error);
        setState(() {
          _sending = false;
          _error = 'Could not open a mail app or the share sheet. $error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recognition = widget.recognition;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.kind.label} report')),
      body: FutureBuilder<DeviceSummary>(
        future: _device,
        builder: (context, snapshot) {
          final device = snapshot.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'This is exactly what will be sent. Nothing is sent until you '
                'tap Send in your mail app.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              _Field(label: 'To', value: reportRecipient),
              _Field(label: 'Subject', value: reportSubject(widget.kind)),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                minLines: 3,
                maxLines: 6,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What happened? (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text('Message', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              _PreviewBox(
                child: device == null
                    ? const Center(child: CircularProgressIndicator())
                    : ListenableBuilder(
                        listenable: _description,
                        builder: (context, _) => SelectableText(
                          buildReportBody(
                            kind: widget.kind,
                            description: _description.text,
                            environment: _environment(device),
                            recognition: recognition,
                          ),
                          style: _mono(theme),
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Text('Attachments', style: theme.textTheme.titleSmall),
              if (recognition != null && recognition.image != null) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Include the image'),
                  subtitle: const Text('The diagram that was scanned.'),
                  value: _includeImage,
                  onChanged: (value) => setState(() => _includeImage = value ?? true),
                ),
                if (_includeImage)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Image.memory(
                          recognition.image!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stack) =>
                              const Text('The image cannot be shown here.'),
                        ),
                      ),
                    ),
                  ),
              ],
              for (final attachment in buildAttachments(
                logText: _logText,
                recognition: recognition,
                includeImage: _includeImage,
              ))
                if (attachment.name == 'chesslens-log.txt')
                  _LogTile(logText: _logText, size: attachment.size)
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      attachment.mimeType == 'image/png'
                          ? Icons.image_outlined
                          : Icons.description_outlined,
                    ),
                    title: Text(attachment.name),
                    subtitle: Text(formatFileSize(attachment.size)),
                  ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text('Send'),
                onPressed: device == null || _sending ? null : () => _send(device),
              ),
              const SizedBox(height: 8),
              Text(
                'Send opens your mail app with this message ready. If you '
                'have no mail app, you can share the report instead.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static TextStyle? _mono(ThemeData theme) =>
      theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.logText, required this.size});

  final String logText;
  final int size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      leading: const Icon(Icons.description_outlined),
      title: const Text('chesslens-log.txt'),
      subtitle: Text('${formatFileSize(size)}. Tap to read it.'),
      children: [
        _PreviewBox(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: SelectableText(
                logText,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Copy log'),
            onPressed: () => Clipboard.setData(ClipboardData(text: logText)),
          ),
        ),
      ],
    );
  }
}
