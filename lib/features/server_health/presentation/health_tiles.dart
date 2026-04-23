import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../domain/server_health.dart';
import 'health_notifier.dart';

/// Embedded 4-tile health strip for the server detail screen.
///
/// Auto-starts polling when mounted, stops when disposed. Colour-coded:
/// green < 70 %, amber 70–90 %, red > 90 %. Taps open the full breakdown.
class ServerHealthTiles extends ConsumerStatefulWidget {
  final String serverId;
  /// Optional host:port label rendered in the header (replaces the old meta
  /// card when the server is connected).
  final String? hostLabel;
  const ServerHealthTiles({super.key, required this.serverId, this.hostLabel});

  @override
  ConsumerState<ServerHealthTiles> createState() => _ServerHealthTilesState();
}

class _ServerHealthTilesState extends ConsumerState<ServerHealthTiles> {
  /// Captured once so we can stop the notifier in dispose without touching
  /// `ref` — newer flutter_riverpod marks the Consumer element defunct
  /// before dispose runs, which would throw if we called `ref.read` there.
  ServerHealthNotifier? _notifier;

  @override
  void initState() {
    super.initState();
    // Start polling on the next frame so the provider is fully initialised.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notifier = ref.read(serverHealthProvider(widget.serverId).notifier);
      _notifier!.start();
    });
  }

  @override
  void dispose() {
    _notifier?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(serverHealthProvider(widget.serverId));
    final snap = state.latest;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.push('/servers/${widget.serverId}/health'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.monitor_heart_outlined,
                    size: 16, color: AppTheme.cyan),
                const SizedBox(width: 8),
                Text(
                  'Server Health',
                  style: AppTheme.mono(
                      size: 12, weight: FontWeight.w700, color: AppTheme.cyan),
                ),
                if (widget.hostLabel != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.hostLabel!,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.mono(
                        size: 11,
                        color: AppTheme.muted.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (state.loading)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  )
                else if (state.error != null)
                  Icon(Icons.error_outline,
                      size: 14, color: AppTheme.danger.withValues(alpha: 0.8))
                else if (snap != null)
                  Text(
                    _relativeTime(snap.takenAt),
                    style: AppTheme.mono(
                        size: 10, color: AppTheme.muted.withValues(alpha: 0.7)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (snap == null && state.error == null)
              _LoadingRow()
            else if (snap == null)
              _ErrorRow(message: state.error!)
            else
              Row(
                children: [
                  Expanded(child: _MetricTile.cpu(snap)),
                  const SizedBox(width: 8),
                  Expanded(child: _MetricTile.memory(snap)),
                  const SizedBox(width: 8),
                  Expanded(child: _MetricTile.disk(snap)),
                  const SizedBox(width: 8),
                  Expanded(child: _MetricTile.uptime(snap)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final d = DateTime.now().toUtc().difference(t);
    if (d.inSeconds < 5) return 'live';
    if (d.inMinutes < 1) return '${d.inSeconds}s ago';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    return '${d.inHours}h ago';
  }
}

/// One of the four mini-cards.
class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final double? percent; // 0..100, null = informational only
  final IconData icon;

  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    this.percent,
  });

  factory _MetricTile.cpu(ServerHealthSnapshot s) {
    final p = s.cpuLoadPercent;
    return _MetricTile(
      label: 'CPU',
      value: p == null ? '–' : '${p.toStringAsFixed(0)}%',
      icon: Icons.memory,
      percent: p,
    );
  }

  factory _MetricTile.memory(ServerHealthSnapshot s) {
    final p = s.memUsedPercent;
    return _MetricTile(
      label: 'RAM',
      value: p == null ? '–' : '${p.toStringAsFixed(0)}%',
      icon: Icons.sd_storage_outlined,
      percent: p,
    );
  }

  factory _MetricTile.disk(ServerHealthSnapshot s) {
    final p = s.diskUsedPercent;
    return _MetricTile(
      label: 'DISK',
      value: p == null ? '–' : '${p.toStringAsFixed(0)}%',
      icon: Icons.storage_outlined,
      percent: p,
    );
  }

  factory _MetricTile.uptime(ServerHealthSnapshot s) {
    return _MetricTile(
      label: 'UPTIME',
      value: formatUptime(s.uptimeSeconds),
      icon: Icons.schedule,
    );
  }

  Color _colorFor(double? p) {
    if (p == null) return AppTheme.cyan;
    if (p >= 90) return AppTheme.danger;
    if (p >= 70) return AppTheme.warning;
    return const Color(0xFF58D68D); // soft green
  }

  @override
  Widget build(BuildContext context) {
    final c = _colorFor(percent);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.mono(size: 13, weight: FontWeight.w700, color: c),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: AppTheme.mono(
              size: 9,
              color: AppTheme.muted,
              weight: FontWeight.w600,
            ),
          ),
          if (percent != null) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                minHeight: 3,
                value: (percent!.clamp(0, 100)) / 100.0,
                backgroundColor: Colors.white.withValues(alpha: 0.07),
                valueColor: AlwaysStoppedAnimation(c),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadingRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5)),
          const SizedBox(width: 10),
          Text('Reading server…',
              style: AppTheme.mono(size: 11, color: AppTheme.muted)),
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  final String message;
  const _ErrorRow({required this.message});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              size: 14, color: AppTheme.danger.withValues(alpha: 0.9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.mono(size: 11, color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
  }
}
