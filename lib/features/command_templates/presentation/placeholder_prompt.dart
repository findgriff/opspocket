import 'package:flutter/material.dart';

import '../../../app/core/utils/danger_detector.dart';
import '../../../app/core/utils/placeholder_utils.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/models/command_template.dart';

/// Sheet that prompts the user to fill in {{placeholders}} then previews the
/// rendered command before execution.
class PlaceholderPromptSheet extends StatefulWidget {
  final CommandTemplate template;
  final Map<String, String> seedValues;
  const PlaceholderPromptSheet({super.key, required this.template, this.seedValues = const {}});

  @override
  State<PlaceholderPromptSheet> createState() => _PlaceholderPromptSheetState();

  /// Returns the final rendered command, or null if cancelled.
  static Future<String?> show({
    required BuildContext context,
    required CommandTemplate template,
    Map<String, String> seedValues = const {},
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).cardColor,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: PlaceholderPromptSheet(template: template, seedValues: seedValues),
      ),
    );
  }
}

class _PlaceholderPromptSheetState extends State<PlaceholderPromptSheet> {
  final Map<String, TextEditingController> _controllers = {};
  late final List<String> _fields;

  @override
  void initState() {
    super.initState();
    _fields = widget.template.placeholders.isEmpty
        ? PlaceholderUtils.extract(widget.template.commandText)
        : widget.template.placeholders;
    for (final name in _fields) {
      _controllers[name] = TextEditingController(text: widget.seedValues[name] ?? _defaultFor(name));
    }
  }

  String _defaultFor(String name) {
    switch (name) {
      case 'line_count':
        return '200';
      default:
        return '';
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _values() => {
        for (final e in _controllers.entries) e.key: e.value.text.trim(),
      };

  String _rendered() => PlaceholderUtils.substitute(widget.template.commandText, _values());

  @override
  Widget build(BuildContext context) {
    final missing = PlaceholderUtils.missing(widget.template.commandText, _values());
    final rendered = _rendered();
    final isDangerous = widget.template.dangerous || DangerDetector.isDangerous(rendered);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    isDangerous ? Icons.warning_amber_rounded : Icons.bolt_outlined,
                    color: isDangerous ? AppTheme.danger : AppTheme.accent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.template.name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              if (widget.template.description != null) ...[
                const SizedBox(height: 4),
                Text(widget.template.description!, style: TextStyle(color: AppTheme.muted)),
              ],
              const SizedBox(height: 16),
              if (_fields.isEmpty)
                Text('No placeholders — preview below.', style: TextStyle(color: AppTheme.muted))
              else
                for (final name in _fields) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: TextStyle(color: AppTheme.muted, fontSize: 12)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _controllers[name],
                          autofocus: name == _fields.first,
                          autocorrect: false,
                          onChanged: (_) => setState(() {}),
                        ),
                      ],
                    ),
                  ),
                ],
              const SizedBox(height: 4),
              Text('Preview', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(rendered, style: AppTheme.mono(size: 13)),
              ),
              if (isDangerous) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppTheme.danger),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('This command is flagged as dangerous. You will be asked to confirm.'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDangerous ? AppTheme.danger : AppTheme.accent,
                        foregroundColor: isDangerous ? Colors.white : Colors.black,
                      ),
                      onPressed: missing.isEmpty ? () => Navigator.of(context).pop(rendered) : null,
                      child: Text(isDangerous ? 'Run (danger)' : 'Run'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
