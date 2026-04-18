import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/core/widgets/loading_empty_error.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/models/server_profile.dart';
import '../../server_profiles/data/server_profile_repository_impl.dart';
import '../data/audit_repository_impl.dart';

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});

  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  String? _serverId;
  bool? _successOnly;

  @override
  Widget build(BuildContext context) {
    final stream = ref.watch(auditStreamProvider((
      serverId: _serverId,
      successOnly: _successOnly,
    ),),);
    final serversAsync = ref.watch(serverProfilesStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit trail'),
        actions: [
          PopupMenuButton<bool?>(
            icon: const Icon(Icons.filter_alt_outlined),
            tooltip: 'Filter by result',
            initialValue: _successOnly,
            onSelected: (v) => setState(() => _successOnly = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: null, child: Text('All')),
              PopupMenuItem(value: true, child: Text('Successes')),
              PopupMenuItem(value: false, child: Text('Failures')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: serversAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (servers) => DropdownButton<String?>(
                value: _serverId,
                isExpanded: true,
                hint: const Text('All servers'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All servers')),
                  ...servers.map((ServerProfile s) => DropdownMenuItem(value: s.id, child: Text(s.nickname))),
                ],
                onChanged: (v) => setState(() => _serverId = v),
              ),
            ),
          ),
          Expanded(
            child: stream.when(
              loading: () => StatusViews.loading(),
              error: (e, _) => StatusViews.error(error: e),
              data: (entries) {
                if (entries.isEmpty) {
                  return StatusViews.empty(
                    title: 'Nothing logged yet',
                    description: 'Every SSH command, provider action, and setting change shows up here.',
                    icon: Icons.history,
                  );
                }
                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _AuditTile(entry: entries[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditTile extends StatelessWidget {
  final AuditLogEntry entry;
  const _AuditTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final color = entry.success ? AppTheme.accent : AppTheme.danger;
    final ts = DateFormat('MMM d HH:mm:ss').format(entry.timestamp);

    return ExpansionTile(
      leading: Icon(
        entry.success ? Icons.check_circle_outline : Icons.cancel_outlined,
        color: color,
      ),
      title: Text(
        '${_actionLabel(entry.actionType)}${entry.serverNickname != null ? ' · ${entry.serverNickname}' : ''}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '$ts · ${entry.transport.name}',
        style: TextStyle(color: AppTheme.muted, fontSize: 12),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.commandTemplateName != null) _row('Template', entry.commandTemplateName!),
              if (entry.rawCommand != null) _row('Command', entry.rawCommand!),
              if (entry.shortOutputSummary != null) _row('Output', entry.shortOutputSummary!),
              if (entry.errorSummary != null) _row('Error', entry.errorSummary!, color: AppTheme.danger),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k, style: TextStyle(color: AppTheme.muted, fontSize: 11)),
            const SizedBox(height: 2),
            SelectableText(v, style: AppTheme.mono(size: 12, color: color ?? Colors.white)),
          ],
        ),
      );

  String _actionLabel(dynamic t) {
    switch (t.name) {
      case 'sshConnect':
        return 'SSH connect';
      case 'sshDisconnect':
        return 'SSH disconnect';
      case 'runCommand':
        return 'Run command';
      case 'runQuickAction':
        return 'Quick action';
      case 'runTemplate':
        return 'Run template';
      case 'providerReboot':
        return 'Provider reboot';
      case 'providerPowerCycle':
        return 'Provider power-cycle';
      case 'providerStatus':
        return 'Provider status';
      case 'settingsChange':
        return 'Settings change';
      case 'appUnlock':
        return 'App unlock';
      case 'appLock':
        return 'App lock';
      case 'dangerousConfirm':
        return 'Dangerous confirm';
      default:
        return t.name.toString();
    }
  }
}
