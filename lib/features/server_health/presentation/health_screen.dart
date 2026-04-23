import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../domain/server_health.dart';
import 'health_notifier.dart';

/// Full-screen breakdown of server resource usage. Polls on its own while
/// open so the user can watch live numbers tick up.
class ServerHealthScreen extends ConsumerStatefulWidget {
  final String serverId;
  const ServerHealthScreen({super.key, required this.serverId});

  @override
  ConsumerState<ServerHealthScreen> createState() => _ServerHealthScreenState();
}

class _ServerHealthScreenState extends ConsumerState<ServerHealthScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(serverHealthProvider(widget.serverId).notifier).start();
      }
    });
  }

  @override
  void dispose() {
    ref.read(serverHealthProvider(widget.serverId).notifier).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serverHealthProvider(widget.serverId));
    final snap = state.latest;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Health'),
        actions: [
          IconButton(
            icon: state.loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5))
                : const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: state.loading
                ? null
                : () => ref
                    .read(serverHealthProvider(widget.serverId).notifier)
                    .refresh(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (state.error != null && snap == null)
            _ErrorCard(message: state.error!),
          if (snap == null && state.error == null)
            const _LoadingCard()
          else if (snap != null) ...[
            _SummaryRow(snap: snap),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'CPU',
              icon: Icons.memory,
              children: [
                _Row('Load (1 min)', snap.load1?.toStringAsFixed(2) ?? '–'),
                _Row('Load (5 min)', snap.load5?.toStringAsFixed(2) ?? '–'),
                _Row('Load (15 min)', snap.load15?.toStringAsFixed(2) ?? '–'),
                _Row('Cores', snap.cpuCores?.toString() ?? '–'),
                _Row(
                  'CPU saturation',
                  snap.cpuLoadPercent == null
                      ? '–'
                      : '${snap.cpuLoadPercent!.toStringAsFixed(1)}%',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Memory',
              icon: Icons.sd_storage_outlined,
              children: [
                _Row('Total', formatBytes(snap.memTotalBytes)),
                _Row('Used', formatBytes(snap.memUsedBytes)),
                _Row('Available', formatBytes(snap.memAvailableBytes)),
                _Row(
                  'Used %',
                  snap.memUsedPercent == null
                      ? '–'
                      : '${snap.memUsedPercent!.toStringAsFixed(1)}%',
                ),
                if ((snap.swapTotalBytes ?? 0) > 0) ...[
                  _Row('Swap total', formatBytes(snap.swapTotalBytes)),
                  _Row('Swap used', formatBytes(snap.swapUsedBytes)),
                ],
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Disk (${snap.diskMountPoint ?? '/'})',
              icon: Icons.storage_outlined,
              children: [
                _Row('Total', formatBytes(snap.diskTotalBytes)),
                _Row('Used', formatBytes(snap.diskUsedBytes)),
                _Row('Free', formatBytes(snap.diskAvailableBytes)),
                _Row(
                  'Used %',
                  snap.diskUsedPercent == null
                      ? '–'
                      : '${snap.diskUsedPercent!.toStringAsFixed(1)}%',
                ),
              ],
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Uptime',
              icon: Icons.schedule,
              children: [
                _Row('Running for', formatUptime(snap.uptimeSeconds)),
                _Row(
                  'Last probe',
                  snap.takenAt.toLocal().toString().split('.').first,
                ),
              ],
            ),
            if (state.error != null) ...[
              const SizedBox(height: 12),
              _ErrorCard(message: state.error!),
            ],
          ],
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final ServerHealthSnapshot snap;
  const _SummaryRow({required this.snap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _Stat('CPU', snap.cpuLoadPercent)),
          Expanded(child: _Stat('RAM', snap.memUsedPercent)),
          Expanded(child: _Stat('DISK', snap.diskUsedPercent)),
          Expanded(
              child: _StatText('UPTIME', formatUptime(snap.uptimeSeconds))),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final double? percent;
  const _Stat(this.label, this.percent);

  Color _c(double? p) {
    if (p == null) return AppTheme.cyan;
    if (p >= 90) return AppTheme.danger;
    if (p >= 70) return AppTheme.warning;
    return const Color(0xFF58D68D);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c(percent);
    return Column(
      children: [
        Text(
          percent == null ? '–' : '${percent!.toStringAsFixed(0)}%',
          style: AppTheme.mono(size: 20, weight: FontWeight.w800, color: c),
        ),
        const SizedBox(height: 4),
        Text(label,
            style: AppTheme.mono(
                size: 10, color: AppTheme.muted, weight: FontWeight.w700)),
      ],
    );
  }
}

class _StatText extends StatelessWidget {
  final String label;
  final String value;
  const _StatText(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: AppTheme.mono(
                size: 18, weight: FontWeight.w800, color: AppTheme.cyan)),
        const SizedBox(height: 4),
        Text(label,
            style: AppTheme.mono(
                size: 10, color: AppTheme.muted, weight: FontWeight.w700)),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _SectionCard(
      {required this.title, required this.icon, required this.children});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.cyan),
              const SizedBox(width: 8),
              Text(title,
                  style: AppTheme.mono(
                      size: 12,
                      weight: FontWeight.w700,
                      color: AppTheme.cyan)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: AppTheme.mono(size: 12, color: AppTheme.muted)),
          Text(value,
              style: AppTheme.mono(
                  size: 12, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppTheme.danger),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: AppTheme.mono(size: 12, color: AppTheme.danger))),
        ],
      ),
    );
  }
}
