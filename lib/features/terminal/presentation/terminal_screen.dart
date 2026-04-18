import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../app/theme/app_theme.dart';
import '../../../shared/models/command_template.dart';
import '../../../shared/models/session_state.dart';
import '../../command_templates/data/command_template_repository_impl.dart';
import '../../command_templates/presentation/placeholder_prompt.dart';
import '../../command_templates/presentation/slash_palette.dart';
import '../../server_profiles/data/server_profile_repository_impl.dart';
import '../../ssh/presentation/command_runner.dart';
import '../../ssh/presentation/ssh_connection_notifier.dart';

// ── Palette ──────────────────────────────────────────────────────────────────
const _bg        = Color(0xFF0A0A0A);
const _surface   = Color(0xFF141414);
const _border    = Color(0xFF2A2A2A);
const _cyan      = Color(0xFF00E6FF);
const _red       = Color(0xFFFF3B1F);
const _deepRed   = Color(0xFFB81200);
const _softRed   = Color(0xFFFF6A4D);
const _white     = Color(0xFFFFFFFF);
const _muted     = Color(0xFF888888);
const _dimText   = Color(0xFF999999);

class _TerminalEntry {
  final String command;
  final String output;
  final bool error;
  final int? exitCode;
  final Duration duration;
  final DateTime at;
  _TerminalEntry(this.command, this.output, this.error, this.exitCode,
      this.duration, this.at,);
}

class TerminalScreen extends ConsumerStatefulWidget {
  final String serverId;
  const TerminalScreen({super.key, required this.serverId});

  @override
  ConsumerState<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends ConsumerState<TerminalScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  final _layerLink = LayerLink();
  final List<_TerminalEntry> _entries = [];
  bool _busy = false;

  OverlayEntry? _suggestionOverlay;
  List<CommandTemplate> _allTemplates = [];

  static final _timeFmt = DateFormat('HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _hideSuggestions();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  // ── Suggestion overlay ───────────────────────────────────────────────────

  void _onTextChanged() {
    final text = _controller.text;
    if (text.startsWith('/')) {
      _showSuggestions(text.substring(1).toLowerCase());
    } else {
      _hideSuggestions();
    }
  }

  void _showSuggestions(String query) {
    final filtered = _allTemplates.where((t) {
      final q = query.replaceAll('/', '');
      return t.slash.contains(q) ||
          t.name.toLowerCase().contains(q) ||
          t.applicableStack.any((s) => s.contains(q));
    }).take(7).toList();

    _hideSuggestions();
    if (filtered.isEmpty) return;

    _suggestionOverlay = OverlayEntry(
      builder: (_) => Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          child: Material(
            elevation: 16,
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                border: Border.all(color: _cyan.withValues(alpha: 0.3), width: 1),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
                boxShadow: [
                  BoxShadow(
                    color: _cyan.withValues(alpha: 0.08),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    child: Text(
                      '${filtered.length} command${filtered.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          color: _cyan.withValues(alpha: 0.6),
                          fontSize: 10,
                          fontFamily: 'JetBrainsMono',
                          letterSpacing: 0.8,),
                    ),
                  ),
                  const Divider(height: 1, color: _border),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: _border),
                      itemBuilder: (_, i) => _SuggestionRow(
                        template: filtered[i],
                        onTap: () => _selectSuggestion(filtered[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_suggestionOverlay!);
  }

  void _hideSuggestions() {
    _suggestionOverlay?.remove();
    _suggestionOverlay = null;
  }

  Future<void> _selectSuggestion(CommandTemplate template) async {
    _hideSuggestions();
    if (template.placeholders.isNotEmpty) {
      final rendered =
          await PlaceholderPromptSheet.show(context: context, template: template);
      if (rendered != null && rendered.isNotEmpty) {
        _controller.text = rendered;
        _controller.selection =
            TextSelection.collapsed(offset: rendered.length);
      }
    } else {
      _controller.text = template.commandText;
      _controller.selection =
          TextSelection.collapsed(offset: template.commandText.length);
    }
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sshConnectionProvider(widget.serverId));
    final serverAsync = ref.watch(serverProfileByIdProvider(widget.serverId));

    ref.watch(commandTemplatesStreamProvider).whenData((t) {
      _allTemplates = t;
    });

    final nickname = serverAsync.maybeWhen(
      data: (s) => s?.nickname ?? 'terminal',
      orElse: () => 'terminal',
    );

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(nickname, session),
      body: Column(
        children: [
          _StatusBar(state: session, serverId: widget.serverId),
          Expanded(child: _buildOutput()),
          _buildInputBar(session),
        ],
      ),
    );
  }

  AppBar _buildAppBar(String nickname, SessionState session) {
    return AppBar(
      backgroundColor: _surface,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          // Traffic-light dots
          _dot(_deepRed),
          const SizedBox(width: 6),
          _dot(_softRed),
          const SizedBox(width: 6),
          _dot(_cyan.withValues(alpha: 0.5)),
          const SizedBox(width: 14),
          Text(
            nickname,
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 14,
              color: _white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'All commands',
          icon: const Icon(Icons.grid_view_rounded, size: 20),
          onPressed: _openPalette,
          color: _dimText,
        ),
        IconButton(
          tooltip: 'Copy all',
          icon: const Icon(Icons.copy_outlined, size: 20),
          onPressed: _copyAll,
          color: _dimText,
        ),
        IconButton(
          tooltip: 'Clear',
          icon: const Icon(Icons.delete_sweep_outlined, size: 20),
          onPressed: () => setState(_entries.clear),
          color: _dimText,
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _buildOutput() {
    if (_entries.isEmpty) {
      return Container(
        color: _bg,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.terminal, color: _muted, size: 40),
              const SizedBox(height: 12),
              const Text('Ready', style: TextStyle(color: _muted, fontFamily: 'JetBrainsMono', fontSize: 13)),
              const SizedBox(height: 4),
              Text('type a command or / to search',
                  style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 12),),
            ],
          ),
        ),
      );
    }

    return Container(
      color: _bg,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
        itemCount: _entries.length,
        itemBuilder: (_, i) => _EntryBlock(entry: _entries[i], timeFmt: _timeFmt),
      ),
    );
  }

  Widget _buildInputBar(SessionState session) {
    final isConnected = session.connectionState == SshConnectionState.connected;
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SafeArea(
        top: false,
        child: CompositedTransformTarget(
          link: _layerLink,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                // Prompt symbol
                Padding(
                  padding: const EdgeInsets.only(right: 8, left: 4),
                  child: Text(
                    isConnected ? '❯' : '○',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 16,
                      color: isConnected ? _cyan : _muted,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    style: AppTheme.mono(size: 14, color: _white),
                    cursorColor: _cyan,
                    decoration: InputDecoration(
                      hintText: isConnected ? 'command or / to search…' : 'not connected',
                      hintStyle: AppTheme.mono(size: 13, color: _muted),
                      isDense: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _run(),
                    autocorrect: false,
                    enableSuggestions: false,
                    enabled: !_busy,
                  ),
                ),
                const SizedBox(width: 8),
                // Bolt button
                GestureDetector(
                  onTap: _openPalette,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _border,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bolt, color: _cyan, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                // Send button
                GestureDetector(
                  onTap: _busy ? null : _run,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _busy ? _border : _red,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: _busy
                          ? []
                          : [
                              BoxShadow(
                                color: _red.withValues(alpha: 0.4),
                                blurRadius: 8,
                                spreadRadius: 0,
                              ),
                            ],
                    ),
                    child: Icon(
                      _busy ? Icons.hourglass_bottom : Icons.send_rounded,
                      color: _busy ? _muted : _white,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _openPalette() async {
    _hideSuggestions();
    FocusScope.of(context).unfocus();
    final command = await SlashPalette.show(context: context, ref: ref);
    if (command != null && command.isNotEmpty) {
      _controller.text = command;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _focus.requestFocus());
    }
  }

  Future<void> _run() async {
    _hideSuggestions();
    final cmd = _controller.text.trim();
    if (cmd.isEmpty || _busy) return;

    // Intercept clear locally — no need to hit the server.
    if (cmd == 'clear' || cmd == 'cls') {
      _controller.clear();
      setState(() => _entries.clear());
      return;
    }

    setState(() => _busy = true);
    _controller.clear();
    final started = DateTime.now();
    try {
      final result = await ref.read(commandRunnerProvider).run(
            context: context,
            serverId: widget.serverId,
            command: cmd,
          );
      final dur = DateTime.now().difference(started);
      if (result == null) {
        if (mounted) setState(() => _entries.add(_TerminalEntry(cmd, '(cancelled)', false, null, dur, DateTime.now())));
      } else {
        if (mounted) {
          setState(() => _entries.add(_TerminalEntry(
          cmd, result.combinedOutput(), !result.success,
          result.exitCode, dur, result.finishedAt,
        ),),);
        }
      }
    } catch (e) {
      final dur = DateTime.now().difference(started);
      if (mounted) setState(() => _entries.add(_TerminalEntry(cmd, e.toString(), true, -1, dur, DateTime.now())));
    }
    if (mounted) {
      setState(() => _busy = false);
      await Future.delayed(const Duration(milliseconds: 50));
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,);
      }
    }
  }

  Future<void> _copyAll() async {
    final buf = StringBuffer();
    for (final e in _entries) {
      buf.writeln('\$ ${e.command}');
      buf.writeln(e.output);
      buf.writeln();
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard')),
    );
  }
}

// ── Status bar ───────────────────────────────────────────────────────────────

class _StatusBar extends ConsumerWidget {
  final SessionState state;
  final String serverId;
  const _StatusBar({required this.state, required this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDisconnected = state.connectionState == SshConnectionState.disconnected ||
        state.connectionState == SshConnectionState.error;
    final color = _stateColor(state.connectionState);

    return GestureDetector(
      onTap: isDisconnected
          ? () => ref.read(sshConnectionProvider(serverId).notifier).connect()
          : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        color: color.withValues(alpha: 0.12),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 4)],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'SSH: ${state.connectionState.name}',
              style: TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 11,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
            if (state.lastError != null) ...[
              Text('  —  ', style: TextStyle(color: color.withValues(alpha: 0.5), fontSize: 11)),
              Expanded(
                child: Text(
                  state.lastError!,
                  style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: color.withValues(alpha: 0.8)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else
              const Spacer(),
            if (isDisconnected)
              Text(
                'tap to connect',
                style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: color.withValues(alpha: 0.7)),
              ),
          ],
        ),
      ),
    );
  }

  Color _stateColor(SshConnectionState s) {
    switch (s) {
      case SshConnectionState.connected: return _cyan;
      case SshConnectionState.error: return _deepRed;
      case SshConnectionState.connecting:
      case SshConnectionState.reconnecting: return _softRed;
      default: return const Color(0xFF666666);
    }
  }
}

// ── Entry block ───────────────────────────────────────────────────────────────

class _EntryBlock extends StatelessWidget {
  final _TerminalEntry entry;
  final DateFormat timeFmt;
  const _EntryBlock({required this.entry, required this.timeFmt});

  @override
  Widget build(BuildContext context) {
    final exitOk = !entry.error && (entry.exitCode == null || entry.exitCode == 0);
    final exitColor = exitOk ? _cyan : _softRed;
    final ms = entry.duration.inMilliseconds;
    final durationStr = ms < 1000 ? '${ms}ms' : '${(ms / 1000).toStringAsFixed(1)}s';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: exitOk ? _cyan.withValues(alpha: 0.4) : _softRed.withValues(alpha: 0.5), width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Command line
          Container(
            color: _surface,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Text('❯ ', style: AppTheme.mono(size: 13, color: _cyan, weight: FontWeight.bold)),
                Expanded(
                  child: Text(
                    entry.command,
                    style: AppTheme.mono(size: 13, color: _white, weight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Text(timeFmt.format(entry.at),
                    style: AppTheme.mono(size: 10, color: _muted),),
                const SizedBox(width: 8),
                Text(durationStr, style: AppTheme.mono(size: 10, color: _muted)),
                const SizedBox(width: 8),
                if (entry.exitCode != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: exitColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: exitColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '${entry.exitCode}',
                      style: AppTheme.mono(size: 10, color: exitColor),
                    ),
                  ),
              ],
            ),
          ),
          // Output
          if (entry.output.isNotEmpty)
            Container(
              color: _bg,
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Text(
                entry.output,
                style: AppTheme.mono(
                  size: 13,
                  color: entry.error ? _softRed : _white,
                ),
              ),
            ),
          Container(height: 1, color: _border),
        ],
      ),
    );
  }
}

// ── Suggestion row ────────────────────────────────────────────────────────────

class _SuggestionRow extends StatelessWidget {
  final CommandTemplate template;
  final VoidCallback onTap;
  const _SuggestionRow({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              template.dangerous ? Icons.warning_amber_rounded : Icons.chevron_right,
              color: template.dangerous ? _softRed : _cyan,
              size: 16,
            ),
            const SizedBox(width: 10),
            Text(template.slash,
                style: AppTheme.mono(size: 13, color: _red, weight: FontWeight.bold),),
            const SizedBox(width: 10),
            Expanded(
              child: Text(template.name,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.mono(size: 12, color: _white),),
            ),
            Text(
              template.applicableStack.take(2).join(', '),
              style: AppTheme.mono(size: 10, color: _muted),
            ),
          ],
        ),
      ),
    );
  }
}
