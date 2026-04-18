import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/core/widgets/loading_empty_error.dart';
import '../../../shared/models/command_template.dart';
import '../../../shared/models/quick_action.dart';
import '../../command_templates/data/command_template_repository_impl.dart';
import '../../command_templates/presentation/placeholder_prompt.dart';
import '../../providers/presentation/provider_fallback_dialog.dart';
import '../../ssh/presentation/command_runner.dart';
import '../../ssh/presentation/ssh_connection_notifier.dart';
import '../data/quick_action_repository_impl.dart';

// ── Palette ────────────────────────────────────────────────────────────────────
const _bg      = Color(0xFF000000);
const _surface = Color(0xFF0E0E0E);
const _card    = Color(0xFF111111);
const _border  = Color(0xFF222222);
const _white   = Color(0xFFFFFFFF);
const _muted   = Color(0xFF666666);
const _cyan    = Color(0xFF00E6FF);
const _green   = Color(0xFF32D74B);
const _amber   = Color(0xFFFFB800);
const _red     = Color(0xFFFF3B1F);
const _purple  = Color(0xFFB57BFF);
const _blue    = Color(0xFF4A9EFF);

// ── Icon + colour registry ─────────────────────────────────────────────────────

class _ActionMeta {
  final IconData icon;
  final Color color;
  const _ActionMeta(this.icon, this.color);
}

const _metaByTemplate = <String, _ActionMeta>{
  // Status / health
  'builtin.generic.status'            : _ActionMeta(Icons.monitor_heart_outlined, _cyan),
  'builtin.systemd.status'            : _ActionMeta(Icons.settings_applications_outlined, _cyan),
  'builtin.nginx.status'              : _ActionMeta(Icons.dns_outlined, _cyan),
  'builtin.openclaw.status'           : _ActionMeta(Icons.radar, _cyan),
  'builtin.openclaw.gateway-status'   : _ActionMeta(Icons.cell_tower, _cyan),
  'builtin.openclaw.channels-probe'   : _ActionMeta(Icons.wifi_tethering, _cyan),
  'builtin.openclaw.doctor'           : _ActionMeta(Icons.health_and_safety_outlined, _cyan),
  // Logs / view
  'builtin.journal.logs'              : _ActionMeta(Icons.article_outlined, _green),
  'builtin.docker.logs'               : _ActionMeta(Icons.terminal_outlined, _green),
  'builtin.docker.ps'                 : _ActionMeta(Icons.grid_view_outlined, _green),
  'builtin.pm2.list'                  : _ActionMeta(Icons.format_list_bulleted, _green),
  'builtin.file.tail'                 : _ActionMeta(Icons.subject_outlined, _green),
  'builtin.openclaw.logs'             : _ActionMeta(Icons.description_outlined, _green),
  'builtin.openclaw.logs-follow'      : _ActionMeta(Icons.dynamic_feed_outlined, _green),
  'builtin.openclaw.cron-list'        : _ActionMeta(Icons.schedule_outlined, _green),
  'builtin.openclaw.agents-list'      : _ActionMeta(Icons.smart_toy_outlined, _green),
  'builtin.openclaw.tasks-list'       : _ActionMeta(Icons.task_alt_outlined, _green),
  'builtin.openclaw.models-list'      : _ActionMeta(Icons.model_training_outlined, _green),
  'builtin.openclaw.config-get'       : _ActionMeta(Icons.tune, _green),
  'builtin.openclaw.skills-list'      : _ActionMeta(Icons.extension_outlined, _green),
  'builtin.tmux.attach-list'          : _ActionMeta(Icons.splitscreen_outlined, _green),
  // Process management — PM2 / nginx (restarts, amber)
  'builtin.pm2.restart'               : _ActionMeta(Icons.loop, _purple),
  'builtin.pm2.logs'                  : _ActionMeta(Icons.receipt_long_outlined, _purple),
  'builtin.nginx.restart'             : _ActionMeta(Icons.language, _blue),
  // Restarts (amber)
  'builtin.systemd.restart'           : _ActionMeta(Icons.restart_alt, _amber),
  'builtin.bot.restart-generic'       : _ActionMeta(Icons.smart_toy_outlined, _amber),
  'builtin.python.claude-restart'     : _ActionMeta(Icons.psychology_outlined, _amber),
  'builtin.openclaw.gateway-restart'  : _ActionMeta(Icons.refresh, _amber),
  'builtin.openclaw.systemd-restart'  : _ActionMeta(Icons.settings_backup_restore, _amber),
  'builtin.openclaw.systemd-logs'     : _ActionMeta(Icons.receipt_long_outlined, _green),
  'builtin.openclaw.systemd-status'   : _ActionMeta(Icons.verified_outlined, _cyan),
  'builtin.openclaw.gateway-start'    : _ActionMeta(Icons.play_circle_outline, _green),
  'builtin.openclaw.update'           : _ActionMeta(Icons.system_update_alt, _blue),
  'builtin.openclaw.backup'           : _ActionMeta(Icons.cloud_upload_outlined, _blue),
  'builtin.openclaw.skills-install'   : _ActionMeta(Icons.download_outlined, _blue),
  'builtin.openclaw.cron-add'         : _ActionMeta(Icons.add_alarm_outlined, _blue),
  // Dangerous (red)
  'builtin.docker.restart'            : _ActionMeta(Icons.storage, _red),
  'builtin.openclaw.gateway-stop'     : _ActionMeta(Icons.stop_circle_outlined, _red),
  'builtin.openclaw.cron-remove'      : _ActionMeta(Icons.alarm_off_outlined, _red),
  'builtin.server.reboot'             : _ActionMeta(Icons.power_settings_new, _red),
};

_ActionMeta _meta(String templateId) =>
    _metaByTemplate[templateId] ?? const _ActionMeta(Icons.terminal_outlined, _muted);

// ── Screen ─────────────────────────────────────────────────────────────────────

class QuickActionsScreen extends ConsumerWidget {
  final String serverId;
  const QuickActionsScreen({super.key, required this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = ref.watch(visibleQuickActionsProvider);
    final session = ref.watch(sshConnectionProvider(serverId));
    final connected = session.connectionState.name == 'connected';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: _white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Quick Actions',
          style: TextStyle(
            color: _white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: Column(
        children: [
          // ── Connection banner ──────────────────────────────────────────────
          if (!connected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.08),
                border: Border(bottom: BorderSide(color: _amber.withValues(alpha: 0.2))),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: _amber, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'SSH not connected — actions will prompt to connect first.',
                    style: TextStyle(color: _amber, fontSize: 12),
                  ),
                ],
              ),
            ),

          // ── Grid ──────────────────────────────────────────────────────────
          Expanded(
            child: actions.when(
              loading: () => StatusViews.loading(),
              error: (e, _) => StatusViews.error(error: e),
              data: (list) {
                if (list.isEmpty) {
                  return StatusViews.empty(
                    icon: Icons.bolt_outlined,
                    title: 'No quick actions',
                    description: 'Defaults seed automatically on first run.',
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                  itemCount: list.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.05,
                  ),
                  itemBuilder: (_, i) => _ActionTile(
                    action: list[i],
                    onTap: () => _run(context, ref, list[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _run(BuildContext context, WidgetRef ref, QuickAction action) async {
    final tpl = await ref.read(commandTemplateRepositoryProvider).getById(action.templateId);
    if (tpl == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _surface,
          content: Text('Template not found: ${action.templateId}',
              style: const TextStyle(color: _white),),
        ),
      );
      return;
    }
    await _runTemplate(context, ref, tpl);
  }

  Future<void> _runTemplate(
      BuildContext context, WidgetRef ref, CommandTemplate t,) async {
    String command;
    if (t.placeholders.isEmpty) {
      command = t.commandText;
    } else {
      final rendered = await PlaceholderPromptSheet.show(context: context, template: t);
      if (rendered == null) return;
      command = rendered;
    }

    try {
      final result = await ref.read(commandRunnerProvider).run(
            context: context,
            serverId: serverId,
            command: command,
            templateName: t.name,
            forceDangerous: t.dangerous,
          );
      if (!context.mounted) return;
      if (result == null) return;
      await _showResultSheet(context, t.name, result.combinedOutput(), result.success);
    } catch (e) {
      if (!context.mounted) return;
      final msg = e.toString();
      if (msg.contains('unreachable') || msg.contains('timed out')) {
        await ProviderFallbackDialog.show(context: context, ref: ref, serverId: serverId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: _surface,
            content: Text(msg, style: const TextStyle(color: _white)),
          ),
        );
      }
    }
  }

  Future<void> _showResultSheet(
      BuildContext context, String title, String output, bool success,) {
    final accent = success ? _green : _red;
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, controller) => Container(
          decoration: const BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: _border)),
          ),
          child: Column(
            children: [
              // drag handle
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 16),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: accent.withValues(alpha: 0.3)),
                      ),
                      child: Icon(
                        success ? Icons.check_rounded : Icons.error_outline_rounded,
                        color: accent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: _white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            ),
                          ),
                          Text(
                            success ? 'Completed successfully' : 'Exited with error',
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontFamily: 'JetBrainsMono',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_outlined, size: 18, color: _muted),
                      tooltip: 'Copy output',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: output));
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Copied to clipboard'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18, color: _muted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              const Divider(color: _border, height: 1),
              // output
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      controller: controller,
                      padding: const EdgeInsets.all(14),
                      child: SelectableText(
                        output.isEmpty ? '(no output)' : output,
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 12,
                          color: Color(0xFFCCCCCC),
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Action tile ────────────────────────────────────────────────────────────────

class _ActionTile extends StatefulWidget {
  final QuickAction action;
  final VoidCallback onTap;
  const _ActionTile({required this.action, required this.onTap});

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final meta = _meta(widget.action.templateId);
    final color = meta.color;
    final isDangerous = color == _red;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _pressed
                  ? color.withValues(alpha: 0.5)
                  : color.withValues(alpha: 0.18),
              width: 1,
            ),
            boxShadow: _pressed
                ? [BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 16)]
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Icon container ─────────────────────────────────────────
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withValues(alpha: 0.2)),
                ),
                child: Icon(meta.icon, color: color, size: 22),
              ),
              const Spacer(),
              // ── Label ─────────────────────────────────────────────────
              Text(
                widget.action.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              // ── Category chip ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isDangerous ? 'DANGER' : _categoryLabel(widget.action.templateId),
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 9,
                    color: color.withValues(alpha: 0.8),
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _categoryLabel(String templateId) {
    if (templateId.contains('openclaw')) return 'OPENCLAW';
    if (templateId.contains('nginx'))    return 'NGINX';
    if (templateId.contains('pm2'))      return 'PM2';
    if (templateId.contains('docker'))   return 'DOCKER';
    if (templateId.contains('systemd'))  return 'SYSTEMD';
    if (templateId.contains('journal'))  return 'JOURNAL';
    if (templateId.contains('server'))   return 'SERVER';
    if (templateId.contains('tmux'))     return 'TMUX';
    return 'SYSTEM';
  }
}
