import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chess/fen_input.dart';

/// Asks for a FEN (full or piece placement only). Returns the parsed
/// position, or `null` when cancelled.
Future<FenInput?> showPasteFenDialog(BuildContext context) {
  return showDialog<FenInput>(
    context: context,
    builder: (context) => const PasteFenDialog(),
  );
}

class PasteFenDialog extends StatefulWidget {
  const PasteFenDialog({super.key});

  @override
  State<PasteFenDialog> createState() => _PasteFenDialogState();
}

class _PasteFenDialogState extends State<PasteFenDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      setState(() => _error = 'The clipboard has no text.');
      return;
    }
    _controller.text = text.trim();
    setState(() => _error = null);
  }

  void _submit() {
    try {
      final input = parseFenInput(_controller.text);
      Navigator.of(context).pop(input);
    } on FenInputException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paste FEN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 2,
            maxLines: 4,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'FEN',
              hintText: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
              helperText: 'A full FEN or just the piece placement.',
              helperMaxLines: 2,
              errorText: _error,
              errorMaxLines: 3,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            icon: const Icon(Icons.content_paste),
            label: const Text('Paste from clipboard'),
            onPressed: _paste,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
