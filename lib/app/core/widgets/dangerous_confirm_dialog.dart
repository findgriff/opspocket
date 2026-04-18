import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Confirmation dialog for destructive actions. Requires typing a confirmation
/// word to proceed — reduces accidental taps during an incident.
class DangerousConfirmDialog extends StatefulWidget {
  final String title;
  final String description;
  final String confirmWord;
  final String confirmButtonLabel;

  const DangerousConfirmDialog({
    super.key,
    required this.title,
    required this.description,
    this.confirmWord = 'CONFIRM',
    this.confirmButtonLabel = 'Proceed',
  });

  @override
  State<DangerousConfirmDialog> createState() => _DangerousConfirmDialogState();

  /// Convenience wrapper. Returns true if the user confirmed.
  static Future<bool> show({
    required BuildContext context,
    required String title,
    required String description,
    String confirmWord = 'CONFIRM',
    String confirmButtonLabel = 'Proceed',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DangerousConfirmDialog(
        title: title,
        description: description,
        confirmWord: confirmWord,
        confirmButtonLabel: confirmButtonLabel,
      ),
    );
    return result ?? false;
  }
}

class _DangerousConfirmDialogState extends State<DangerousConfirmDialog> {
  final _controller = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
          const SizedBox(width: 8),
          Expanded(child: Text(widget.title)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.description),
          const SizedBox(height: 16),
          Text(
            'Type ${widget.confirmWord} to confirm:',
            style: TextStyle(color: AppTheme.muted),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(hintText: 'CONFIRM'),
            onChanged: (v) => setState(() => _matches = v.trim() == widget.confirmWord),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _matches ? AppTheme.danger : AppTheme.danger.withValues(alpha: 0.4),
            foregroundColor: Colors.white,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.confirmButtonLabel),
        ),
      ],
    );
  }
}
