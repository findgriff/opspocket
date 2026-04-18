import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/core/widgets/loading_empty_error.dart';
import '../../../app/theme/app_theme.dart';
import '../../../shared/models/server_profile.dart';
import '../../../shared/models/session_state.dart';
import '../../ssh/presentation/ssh_connection_notifier.dart';
import '../../tunnel/domain/claw_gate_state.dart';
import '../../tunnel/presentation/claw_gate_notifier.dart';
import '../../mission_control/presentation/deploy_screen.dart';
import '../../tunnel/presentation/openclaw_ui_screen.dart';
import '../../tunnel/presentation/mission_control_screen.dart';
import '../data/server_profile_repository_impl.dart';

class ServerDetailScreen extends ConsumerWidget {
  final String serverId;
  const ServerDetailScreen({super.key, required this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverAsync = ref.watch(serverProfileByIdProvider(serverId));
    final session = ref.watch(sshConnectionProvider(serverId));

    return Scaffold(
      appBar: AppBar(
        title: serverAsync.when(
          loading: () => const Text('Server'),
          error: (_, __) => const Text('Server'),
          data: (s) => Text(s?.nickname ?? 'Server'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => context.push('/servers/$serverId/edit'),
          ),
        ],
      ),
      body: serverAsync.when(
        loading: () => StatusViews.loading(),
        error: (e, _) => StatusViews.error(error: e),
        data: (server) {
          if (server == null) {
            return StatusViews.empty(
              title: 'Server not found',
              icon: Icons.error_outline,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ConnectionBanner(state: session),
              const SizedBox(height: 16),
              _MetaCard(server: server),
              const SizedBox(height: 16),
              _ActionTile(
                icon: Icons.bolt_outlined,
                label: 'Quick Actions',
                subtitle: 'Restart services, OpenClaw, PM2, reboot',
                onTap: () => context.push('/servers/$serverId/quick-actions'),
                color: AppTheme.accent,
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.terminal_outlined,
                label: 'Terminal',
                subtitle: 'Run custom commands',
                onTap: () => context.push('/servers/$serverId/terminal'),
              ),
              const SizedBox(height: 12),
              // _ActionTile(
              //   icon: Icons.article_outlined,
              //   label: 'Logs',
              //   subtitle: 'Tail journald, Docker, PM2, files',
              //   onTap: () => context.push('/servers/$serverId/logs'),
              // ),
              // const SizedBox(height: 12),
              // Native MCScreen removed — use Tunnel → Mission button below for
              // live data from the deployed Next.js app instead.
              // _ActionTile(
              //   icon: Icons.crisis_alert,
              //   label: 'Mission Control',
              //   subtitle: 'Tasks, agents, projects, memory',
              //   color: const Color(0xFFFF3B1F),
              //   onTap: () {
              //     final name = server.nickname.isNotEmpty ? server.nickname : server.hostnameOrIp;
              //     Navigator.push(context, MaterialPageRoute(
              //       builder: (_) => MCScreen(serverId: serverId, serverName: name),
              //       fullscreenDialog: true,
              //     ));
              //   },
              // ),
              // const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.rocket_launch_outlined,
                label: 'Deploy Mission Control',
                subtitle: 'Pull latest & rebuild from GitHub',
                color: const Color(0xFFB57BFF),
                onTap: () {
                  final name = server.nickname.isNotEmpty
                      ? server.nickname
                      : server.hostnameOrIp;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeployScreen(
                        serverId: serverId,
                        serverName: name,
                      ),
                      fullscreenDialog: true,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _ClawGateTile(serverId: serverId),
              const SizedBox(height: 24),
              Text(
                'SSH',
                style: TextStyle(color: AppTheme.muted, fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => ref.read(sshConnectionProvider(serverId).notifier).connect(),
                      icon: const Icon(Icons.link),
                      label: const Text('Connect'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: () => ref.read(sshConnectionProvider(serverId).notifier).disconnect(),
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  final dynamic state;
  const _ConnectionBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final status = state.connectionState.toString().split('.').last;
    Color bg;
    IconData icon;
    switch (status) {
      case 'connected':
        bg = AppTheme.cyan.withValues(alpha: 0.15);
        icon = Icons.check_circle_outline;
        break;
      case 'connecting':
      case 'reconnecting':
        bg = AppTheme.warning.withValues(alpha: 0.15);
        icon = Icons.hourglass_bottom;
        break;
      case 'error':
        bg = AppTheme.danger.withValues(alpha: 0.18);
        icon = Icons.error_outline;
        break;
      default:
        bg = Colors.white.withValues(alpha: 0.05);
        icon = Icons.link_off;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SSH: $status', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (state.lastError != null)
                  Text(
                    state.lastError!,
                    style: TextStyle(color: AppTheme.muted, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaCard extends StatelessWidget {
  final ServerProfile server;
  const _MetaCard({required this.server});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Host', '${server.hostnameOrIp}:${server.port}'),
            _row('User', server.username),
            _row('Auth', server.authMethod.name),
            if (server.tags.isNotEmpty) _row('Tags', server.tags.join(', ')),
            if (server.notes != null && server.notes!.isNotEmpty) _row('Notes', server.notes!),
            if (server.providerType.name != 'none')
              _row('Provider', '${server.providerType.name} ${server.providerResourceId ?? ''}'),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 80, child: Text(k, style: TextStyle(color: AppTheme.muted, fontSize: 12))),
            Expanded(child: Text(v, style: const TextStyle(fontFamily: 'monospace', fontSize: 13))),
          ],
        ),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final Color? color;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return Card(
      child: ListTile(
        leading: Icon(icon, color: c),
        title: Text(label, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ── ClawGate tile ─────────────────────────────────────────────────────────────

class _ClawGateTile extends ConsumerWidget {
  final String serverId;
  const _ClawGateTile({required this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(clawGateProvider(serverId));
    final session = ref.watch(sshConnectionProvider(serverId));
    final isConnected =
        session.connectionState == SshConnectionState.connected;
    final notifier = ref.read(clawGateProvider(serverId).notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────────
            Row(
              children: [
                _statusDot(gate.status),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gate.isActive
                            ? gate.activeTarget!.label
                            : 'Tunnel',
                        style: TextStyle(
                          color: isConnected ? Colors.white : AppTheme.muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _subtitle(gate, isConnected),
                        style: TextStyle(color: AppTheme.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                // ── Action buttons ──────────────────────────────────────────
                if (gate.isActive)
                  _TabButtons(
                    onOpen: () {
                      final url = gate.tunnelUrl;
                      if (url != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                gate.activeTarget == TunnelTarget.missionControl
                                    ? MissionControlScreen(url: url)
                                    : OpenClawUiScreen(url: url),
                            fullscreenDialog: true,
                          ),
                        );
                      }
                    },
                    onStop: notifier.stop,
                  )
                else if (gate.isBusy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  _DestinationButtons(
                    enabled: isConnected,
                    onTap: isConnected
                        ? (target) => notifier.start(target)
                        : null,
                  ),
              ],
            ),
            // ── Error message ────────────────────────────────────────────────
            if (gate.status == ClawGateStatus.error &&
                gate.errorMessage != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline,
                        size: 16, color: AppTheme.danger,),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        gate.errorMessage!,
                        style: TextStyle(
                            fontSize: 12, color: AppTheme.warning,),
                      ),
                    ),
                    GestureDetector(
                      onTap: notifier.stop,
                      child: Icon(Icons.close,
                          size: 16, color: AppTheme.muted,),
                    ),
                  ],
                ),
              ),
            ],
            // ── Active port info ─────────────────────────────────────────────
            if (gate.isActive && gate.localPort != null) ...[
              const SizedBox(height: 8),
              Text(
                '127.0.0.1:${gate.localPort}  →  VPS:18789',
                style: AppTheme.mono(
                    size: 11, color: AppTheme.cyan.withValues(alpha: 0.7),),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusDot(ClawGateStatus status) {
    Color color;
    switch (status) {
      case ClawGateStatus.active:
        color = AppTheme.cyan;
        break;
      case ClawGateStatus.error:
        color = AppTheme.danger;
        break;
      case ClawGateStatus.fetchingToken:
      case ClawGateStatus.starting:
        color = AppTheme.warning;
        break;
      case ClawGateStatus.idle:
        color = AppTheme.muted;
    }
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: status == ClawGateStatus.active
            ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]
            : null,
      ),
    );
  }

  String _subtitle(ClawGateState gate, bool isConnected) {
    switch (gate.status) {
      case ClawGateStatus.idle:
        return isConnected ? 'Choose a destination' : 'Connect SSH first';
      case ClawGateStatus.fetchingToken:
        return 'Fetching token…';
      case ClawGateStatus.starting:
        return 'Starting tunnel…';
      case ClawGateStatus.active:
        return 'Port ${gate.localPort} → VPS:${gate.activeTarget?.remotePort}';
      case ClawGateStatus.error:
        return 'Tap × to dismiss';
    }
  }
}

// ── Destination picker (idle state) ──────────────────────────────────────────

class _DestinationButtons extends StatelessWidget {
  final bool enabled;
  final void Function(TunnelTarget)? onTap;
  const _DestinationButtons({required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill(
          label: 'OpenClaw UI',
          icon: Icons.smart_toy_outlined,
          color: AppTheme.cyan,
          onTap: enabled ? () => onTap?.call(TunnelTarget.clawbot) : null,
        ),
        const SizedBox(width: 6),
        _pill(
          label: 'Mission',
          icon: Icons.dashboard_outlined,
          color: const Color(0xFFB57BFF),
          onTap: enabled ? () => onTap?.call(TunnelTarget.missionControl) : null,
        ),
      ],
    );
  }

  Widget _pill({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    final c = onTap != null ? color : AppTheme.muted;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: c.withValues(alpha: onTap != null ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: c),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: c,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Open / Stop tab buttons (active state) ────────────────────────────────────

class _TabButtons extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onStop;
  const _TabButtons({required this.onOpen, required this.onStop});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tab(
            label: 'Open',
            color: AppTheme.cyan,
            onTap: onOpen,
            leftRounded: true,
          ),
          Container(width: 1, height: 30, color: const Color(0xFF3A3A3A)),
          _tab(
            label: 'Stop',
            color: AppTheme.muted,
            onTap: onStop,
            rightRounded: true,
          ),
        ],
      ),
    );
  }

  Widget _tab({
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool leftRounded = false,
    bool rightRounded = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: leftRounded ? const Radius.circular(7) : Radius.zero,
            right: rightRounded ? const Radius.circular(7) : Radius.zero,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
