import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/deploy_state.dart';
import 'deploy_notifier.dart';
import 'mc_screen.dart';

// ── Palette (same as mc_screen.dart) ──────────────────────────────────────────
const _bg = Color(0xFF000000);
const _surface = Color(0xFF0E0E0E);
const _card = Color(0xFF161616);
const _border = Color(0xFF252525);
const _red = Color(0xFFFF3B1F);
const _cyan = Color(0xFF00E6FF);
const _purple = Color(0xFFB57BFF);
const _green = Color(0xFF4CAF50);
const _white = Color(0xFFFFFFFF);
const _muted = Color(0xFF888888);

// ── Entry point ────────────────────────────────────────────────────────────────

class DeployScreen extends ConsumerStatefulWidget {
  final String serverId;
  final String serverName;

  const DeployScreen({
    super.key,
    required this.serverId,
    required this.serverName,
  });

  @override
  ConsumerState<DeployScreen> createState() => _DeployScreenState();
}

class _DeployScreenState extends ConsumerState<DeployScreen> {
  @override
  void initState() {
    super.initState();
    // Auto-start deploy as soon as the screen is visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(deployProvider(widget.serverId).notifier).deploy();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deployProvider(widget.serverId));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              _DeployHeader(
                serverName: widget.serverName,
                onClose: () => Navigator.pop(context),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    for (int i = 0; i < state.steps.length; i++)
                      _StepRow(
                        step: state.steps[i],
                        isExpandable: i == 3, // Build step shows full output
                      ),
                  ],
                ),
              ),
              _Footer(
                state: state,
                serverId: widget.serverId,
                serverName: widget.serverName,
                onRetry: () =>
                    ref.read(deployProvider(widget.serverId).notifier).deploy(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _DeployHeader extends StatelessWidget {
  final String serverName;
  final VoidCallback onClose;

  const _DeployHeader({required this.serverName, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onClose,
            child: const Icon(Icons.close, color: _muted, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DEPLOY',
                  style: TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 13,
                    color: _purple,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  serverName,
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 11,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step row ───────────────────────────────────────────────────────────────────

class _StepRow extends StatefulWidget {
  final DeployStep step;
  final bool isExpandable;

  const _StepRow({required this.step, this.isExpandable = false});

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    final hasOutput = step.output.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main row ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  _StatusIcon(status: step.status),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      step.label,
                      style: TextStyle(
                        color: _labelColor(step.status),
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  // Show toggle button for expandable steps that have output.
                  if (widget.isExpandable && hasOutput)
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4,),
                        decoration: BoxDecoration(
                          color: _cyan.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border:
                              Border.all(color: _cyan.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          _expanded ? 'Hide' : 'Logs',
                          style: const TextStyle(
                              color: _cyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,),
                        ),
                      ),
                    ),
                  // For non-expandable steps show inline error snippet.
                  if (!widget.isExpandable &&
                      step.status == DeployStepStatus.failure &&
                      hasOutput) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.info_outline, size: 16, color: _muted),
                  ],
                ],
              ),
            ),
            // ── Expandable output (build step) ──────────────────────────────
            if (widget.isExpandable && _expanded && hasOutput)
              _OutputBox(output: step.output, isError: false),
            // ── Error output for non-expandable failure steps ───────────────
            if (!widget.isExpandable &&
                step.status == DeployStepStatus.failure &&
                hasOutput)
              _OutputBox(output: step.output, isError: true),
          ],
        ),
      ),
    );
  }

  Color _labelColor(DeployStepStatus status) {
    switch (status) {
      case DeployStepStatus.pending:
        return _muted;
      case DeployStepStatus.running:
        return _white;
      case DeployStepStatus.success:
        return _white;
      case DeployStepStatus.failure:
        return _red;
    }
  }
}

// ── Status icon ────────────────────────────────────────────────────────────────

class _StatusIcon extends StatelessWidget {
  final DeployStepStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case DeployStepStatus.pending:
        return const SizedBox(
          width: 20,
          height: 20,
          child: Icon(Icons.radio_button_unchecked, size: 20, color: _muted),
        );
      case DeployStepStatus.running:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(_cyan),
          ),
        );
      case DeployStepStatus.success:
        return const Icon(Icons.check_circle, size: 20, color: _green);
      case DeployStepStatus.failure:
        return const Icon(Icons.cancel, size: 20, color: _red);
    }
  }
}

// ── Output box with copy button ────────────────────────────────────────────────

class _OutputBox extends StatelessWidget {
  final String output;
  final bool isError;
  const _OutputBox({required this.output, required this.isError});

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isError ? _red.withValues(alpha: 0.2) : _border;
    final bgColor =
        isError ? _red.withValues(alpha: 0.06) : _card;
    final textColor =
        isError ? _red.withValues(alpha: 0.9) : _muted;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Copy bar ──────────────────────────────────────────────────
          InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: output));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.copy_outlined,
                      size: 12,
                      color: isError
                          ? _red.withValues(alpha: 0.6)
                          : _muted,),
                  const SizedBox(width: 4),
                  Text(
                    'Copy',
                    style: TextStyle(
                      fontSize: 11,
                      color: isError
                          ? _red.withValues(alpha: 0.6)
                          : _muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Log text ──────────────────────────────────────────────────
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: isError ? 120 : 240,),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(10),
              child: Text(
                output,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 11,
                  color: textColor,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Footer ─────────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  final DeployState state;
  final String serverId;
  final String serverName;
  final VoidCallback onRetry;

  const _Footer({
    required this.state,
    required this.serverId,
    required this.serverName,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (state.isRunning) {
      // Nothing in footer while running.
      return const SizedBox.shrink();
    }

    if (state.failed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _red.withValues(alpha: 0.15),
              foregroundColor: _red,
              side: BorderSide(color: _red.withValues(alpha: 0.4)),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),),
            ),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text(
              'Retry',
              style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
            ),
          ),
        ),
      );
    }

    if (state.done) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _green.withValues(alpha: 0.15),
              foregroundColor: _green,
              side: BorderSide(color: _green.withValues(alpha: 0.4)),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),),
            ),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      MCScreen(serverId: serverId, serverName: serverName),
                  fullscreenDialog: true,
                ),
              );
            },
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text(
              'Open Mission Control',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
