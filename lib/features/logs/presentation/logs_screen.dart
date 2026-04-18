import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/core/constants/app_constants.dart';
import '../../../app/core/utils/placeholder_utils.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/models/command_template.dart';
import '../../ssh/presentation/command_runner.dart';
import '../../ssh/presentation/ssh_connection_notifier.dart';

enum LogPreset { journal, docker, pm2, file }

String _presetLabel(LogPreset p) {
  switch (p) {
    case LogPreset.journal:
      return 'journalctl';
    case LogPreset.docker:
      return 'docker';
    case LogPreset.pm2:
      return 'pm2';
    case LogPreset.file:
      return 'file';
  }
}

class LogsScreen extends ConsumerStatefulWidget {
  final String serverId;
  const LogsScreen({super.key, required this.serverId});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  LogPreset _preset = LogPreset.journal;
  final _target = TextEditingController();
  final _lines = TextEditingController(text: '${AppConstants.defaultLogLines}');

  String _output = '';
  bool _busy = false;
  DateTime? _fetchedAt;

  @override
  void dispose() {
    _target.dispose();
    _lines.dispose();
    super.dispose();
  }

  String _renderCommand() {
    final n = _lines.text.trim().isEmpty ? '${AppConstants.defaultLogLines}' : _lines.text.trim();
    final target = _target.text.trim();
    switch (_preset) {
      case LogPreset.journal:
        return 'journalctl -u ${target.isEmpty ? 'SERVICE' : target} -n $n --no-pager';
      case LogPreset.docker:
        return 'docker logs --tail $n ${target.isEmpty ? 'CONTAINER' : target}';
      case LogPreset.pm2:
        return 'pm2 logs ${target.isEmpty ? 'APP' : target} --lines $n --nostream';
      case LogPreset.file:
        return 'tail -n $n ${target.isEmpty ? '/path/to/log' : target}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sshConnectionProvider(widget.serverId));
    final rendered = _renderCommand();
    final needsTarget = _target.text.trim().isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Logs'),
        actions: [
          IconButton(
            tooltip: 'Copy output',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: _output.isEmpty ? null : () => Clipboard.setData(ClipboardData(text: _output)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: session.connectionState.name == 'connected'
                ? AppTheme.accent.withValues(alpha: 0.1)
                : AppTheme.warning.withValues(alpha: 0.1),
            child: Text(
              'SSH: ${session.connectionState.name}',
              style: TextStyle(
                color: session.connectionState.name == 'connected' ? AppTheme.accent : AppTheme.warning,
                fontSize: 12,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<LogPreset>(
              segments: LogPreset.values
                  .map((p) => ButtonSegment(value: p, label: Text(_presetLabel(p))))
                  .toList(),
              selected: {_preset},
              onSelectionChanged: (s) => setState(() => _preset = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _target,
                    decoration: InputDecoration(
                      hintText: _preset == LogPreset.file ? '/var/log/app.log' : 'service / container / app',
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _lines,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: 'lines', isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(rendered, style: AppTheme.mono(size: 12, color: AppTheme.muted)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy || needsTarget || PlaceholderUtils.hasUnresolved(rendered) ? null : _fetch,
                    icon: const Icon(Icons.refresh),
                    label: Text(_busy ? 'Fetching…' : 'Fetch logs'),
                  ),
                ),
              ],
            ),
          ),
          if (_fetchedAt != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Last fetched ${DateFormat.Hms().format(_fetchedAt!)}',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ),
            ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(10)),
              child: SingleChildScrollView(
                child: SelectableText(
                  _output.isEmpty ? '(no logs yet)' : _capOutput(_output),
                  style: AppTheme.mono(size: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _capOutput(String out) {
    if (out.length <= AppConstants.outputDisplayMaxChars) return out;
    return '...${out.substring(out.length - AppConstants.outputDisplayMaxChars)}';
  }

  CommandTemplate _asTemplate(String rendered) {
    final now = DateTime.now();
    return CommandTemplate(
      id: 'logs.ephemeral',
      name: 'Logs (${_presetLabel(_preset)})',
      category: CommandCategory.logs,
      commandText: rendered,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _fetch() async {
    setState(() {
      _busy = true;
      _output = '';
    });
    try {
      final rendered = _renderCommand();
      final tpl = _asTemplate(rendered);
      final result = await ref.read(commandRunnerProvider).run(
            context: context,
            serverId: widget.serverId,
            command: rendered,
            templateName: tpl.name,
          );
      if (result != null) {
        setState(() {
          _output = result.combinedOutput();
          _fetchedAt = DateTime.now();
        });
      }
    } catch (e) {
      setState(() => _output = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
