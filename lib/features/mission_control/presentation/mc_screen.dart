import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ssh/presentation/ssh_connection_notifier.dart';
import '../data/mc_repository.dart';
import '../domain/mc_models.dart';

// ── Palette ────────────────────────────────────────────────────────────────────
const _bg = Color(0xFF000000);
const _surface = Color(0xFF0E0E0E);
const _card = Color(0xFF161616);
const _border = Color(0xFF252525);
const _red = Color(0xFFFF3B1F);
const _cyan = Color(0xFF00E6FF);
const _purple = Color(0xFFB57BFF);
const _green = Color(0xFF4CAF50);
const _amber = Color(0xFFFFB800);
const _white = Color(0xFFFFFFFF);
const _muted = Color(0xFF888888);
const _dimmed = Color(0xFF3A3A3A);

// ── Entry point ────────────────────────────────────────────────────────────────

class MCScreen extends ConsumerStatefulWidget {
  final String serverId;
  final String serverName;
  const MCScreen({super.key, required this.serverId, required this.serverName});

  @override
  ConsumerState<MCScreen> createState() => _MCScreenState();
}

class _MCScreenState extends ConsumerState<MCScreen> {
  int _tabIndex = 0;

  static const _tabIcons = [
    (Icons.task_alt_outlined, 'Tasks'),
    (Icons.smart_toy_outlined, 'Agents'),
    (Icons.folder_open_outlined, 'Projects'),
    (Icons.schedule_outlined, 'Schedule'),
    (Icons.memory_outlined, 'Memory'),
  ];

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(
          children: [
            _MCHeader(
              serverName: widget.serverName,
              onRefresh: () => mcRefresh(ref, widget.serverId),
              onClose: () => Navigator.pop(context),
            ),
            Expanded(
              child: IndexedStack(
                index: _tabIndex,
                children: [
                  _TasksTab(serverId: widget.serverId),
                  _AgentsTab(serverId: widget.serverId),
                  _ProjectsTab(serverId: widget.serverId),
                  _CalendarTab(serverId: widget.serverId),
                  _MemoryTab(serverId: widget.serverId),
                ],
              ),
            ),
            _BottomNav(
              tabs: _tabIcons,
              selected: _tabIndex,
              onTap: (i) => setState(() => _tabIndex = i),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _MCHeader extends StatelessWidget {
  final String serverName;
  final VoidCallback onRefresh;
  final VoidCallback onClose;
  const _MCHeader({required this.serverName, required this.onRefresh, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: _white, size: 20),
                onPressed: onClose,
              ),
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _red.withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.crisis_alert, color: _red, size: 16),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MISSION CONTROL',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 11,
                      color: _red,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    serverName,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      color: _muted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, color: _muted, size: 20),
                onPressed: onRefresh,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bottom nav ─────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final List<(IconData, String)> tabs;
  final int selected;
  final ValueChanged<int> onTap;
  const _BottomNav({required this.tabs, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: tabs.asMap().entries.map((e) {
              final active = e.key == selected;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(e.key),
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(e.value.$1, size: 20, color: active ? _red : _dimmed),
                      const SizedBox(height: 3),
                      Text(
                        e.value.$2,
                        style: TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 9,
                          color: active ? _red : _dimmed,
                          letterSpacing: 0.5,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────────

Widget _dot(Color c) => Container(
      width: 7, height: 7,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 4)],
      ),
    );

Widget _badge(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: color, letterSpacing: 1, fontWeight: FontWeight.w700),
      ),
    );

Widget _sectionEmpty(String title, String sub, IconData icon) => Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: _dimmed),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(sub, style: const TextStyle(color: _muted, fontSize: 13), textAlign: TextAlign.center),
          ],
        ),
      ),
    );

Widget _sectionError(Object e) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: _red),
            const SizedBox(height: 12),
            const Text('Failed to load', style: TextStyle(color: _white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(e.toString(),
                style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: _muted),
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,),
          ],
        ),
      ),
    );

Widget _shimmer() => ListView.builder(
      itemCount: 5,
      padding: const EdgeInsets.all(16),
      itemBuilder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 72,
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10)),
      ),
    );

McRepository _mcRepo(WidgetRef ref, String serverId) =>
    McRepository(ref.read(sshClientProvider(serverId)));

// ── Tasks tab ──────────────────────────────────────────────────────────────────

class _TasksTab extends ConsumerWidget {
  final String serverId;
  const _TasksTab({required this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: _Fab(
        label: 'New Task',
        icon: Icons.add,
        color: _red,
        onTap: () => _showCreateTask(context, ref, serverId),
      ),
      body: ref.watch(mcTasksProvider(serverId)).when(
        loading: _shimmer,
        error: (e, _) => _sectionError(e),
        data: (tasks) => tasks.isEmpty
            ? _sectionEmpty('No tasks yet', 'Create a task to set OpenClaw to work', Icons.task_alt_outlined)
            : RefreshIndicator(
                color: _red,
                backgroundColor: _card,
                onRefresh: () async => mcRefresh(ref, serverId),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: tasks.length,
                  itemBuilder: (_, i) => _TaskRow(task: tasks[i]),
                ),
              ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final McTask task;
  const _TaskRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final color = task.statusColor;
    return GestureDetector(
      onTap: () => _showTaskDetail(context, task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 5), child: _dot(color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      style: const TextStyle(color: _white, fontSize: 14, fontWeight: FontWeight.w600),
                      maxLines: 2, overflow: TextOverflow.ellipsis,),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _badge(task.status, color),
                      if (task.taskKind != null) ...[const SizedBox(width: 6), _badge(task.taskKind!, _muted)],
                      const Spacer(),
                      Text(task.timeAgo, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: _muted)),
                    ],
                  ),
                  if (task.agentId != null) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.smart_toy_outlined, size: 11, color: _muted),
                      const SizedBox(width: 4),
                      Text(task.agentId!, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: _muted)),
                      if (task.runDuration.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        const Icon(Icons.timer_outlined, size: 11, color: _muted),
                        const SizedBox(width: 4),
                        Text(task.runDuration, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: _muted)),
                      ],
                    ],),
                  ],
                  if (task.error != null && task.error!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: _red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
                      child: Text(task.error!,
                          style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: _red),
                          maxLines: 2, overflow: TextOverflow.ellipsis,),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void _showTaskDetail(BuildContext context, McTask task) {
  showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _BottomSheet(
      title: task.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _badge(task.status, task.statusColor),
            if (task.taskKind != null) ...[const SizedBox(width: 8), _badge(task.taskKind!, _muted)],
          ],),
          const SizedBox(height: 14),
          if (task.agentId != null) _kv('Agent', task.agentId!),
          if (task.timeAgo.isNotEmpty) _kv('Created', task.timeAgo),
          if (task.runDuration.isNotEmpty) _kv('Duration', task.runDuration),
          if (task.description != null && task.description!.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Description', style: _labelStyle),
            const SizedBox(height: 6),
            Text(task.description!, style: const TextStyle(color: _white, fontSize: 13, height: 1.5)),
          ],
          if (task.error != null && task.error!.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('Error', style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: _red, letterSpacing: 0.5)),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: SelectableText(task.error!, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: _red)),
            ),
          ],
        ],
      ),
    ),
  );
}

// ── Agents tab ─────────────────────────────────────────────────────────────────

class _AgentsTab extends ConsumerWidget {
  final String serverId;
  const _AgentsTab({required this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: _bg,
      floatingActionButton: _Fab(
        label: 'Spawn Agent',
        icon: Icons.auto_awesome,
        color: _purple,
        onTap: () => _showSpawnAgent(context, ref, serverId),
      ),
      body: ref.watch(mcAgentsProvider(serverId)).when(
        loading: _shimmer,
        error: (e, _) => _sectionError(e),
        data: (agents) => agents.isEmpty
            ? _sectionEmpty('No agents', 'Spawn your first AI agent below', Icons.smart_toy_outlined)
            : RefreshIndicator(
                color: _red,
                backgroundColor: _card,
                onRefresh: () async => mcRefresh(ref, serverId),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  itemCount: agents.length,
                  itemBuilder: (_, i) => _AgentCard(agent: agents[i]),
                ),
              ),
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  final McAgent agent;
  const _AgentCard({required this.agent});

  @override
  Widget build(BuildContext context) {
    final sc = agent.statusColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                // Avatar circle
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: _purple.withValues(alpha: 0.4)),
                  ),
                  child: Center(
                    child: Text(agent.initials,
                        style: const TextStyle(color: _purple, fontSize: 15, fontWeight: FontWeight.w800, fontFamily: 'JetBrainsMono'),),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(agent.name, style: const TextStyle(color: _white, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(agent.role, style: const TextStyle(color: _purple, fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _dot(sc),
                    const SizedBox(height: 4),
                    Text(agent.status.toUpperCase(),
                        style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: sc, letterSpacing: 1),),
                  ],
                ),
              ],
            ),
          ),
          if (agent.soul.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _purple.withValues(alpha: 0.15)),
                ),
                child: Text(
                  '"${agent.soul}"',
                  style: const TextStyle(color: _muted, fontSize: 12, fontStyle: FontStyle.italic, height: 1.5),
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: _border))),
            child: Row(
              children: [
                const Icon(Icons.history, size: 12, color: _muted),
                const SizedBox(width: 5),
                Text('${agent.sessionCount} sessions',
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: _muted),),
                if (agent.models.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.model_training, size: 12, color: _muted),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(agent.models.first,
                        style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: _muted),
                        overflow: TextOverflow.ellipsis,),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Projects tab ───────────────────────────────────────────────────────────────

class _ProjectsTab extends ConsumerWidget {
  final String serverId;
  const _ProjectsTab({required this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(mcProjectsProvider(serverId)).when(
      loading: _shimmer,
      error: (e, _) => _sectionError(e),
      data: (projects) => projects.isEmpty
          ? _sectionEmpty('No projects found', 'No git repos detected in ~/clawd', Icons.folder_open_outlined)
          : RefreshIndicator(
              color: _red,
              backgroundColor: _card,
              onRefresh: () async => mcRefresh(ref, serverId),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: projects.length,
                itemBuilder: (_, i) => _ProjectRow(project: projects[i]),
              ),
            ),
    );
  }
}

class _ProjectRow extends StatelessWidget {
  final McProject project;
  const _ProjectRow({required this.project});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: _cyan.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.folder_outlined, color: _cyan, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(project.name, style: const TextStyle(color: _white, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  if (project.branch != null) ...[
                    const Icon(Icons.merge_type, size: 11, color: _muted),
                    const SizedBox(width: 3),
                    Text(project.branch!, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: _muted)),
                    const SizedBox(width: 10),
                  ],
                  if (project.kind != null) _badge(project.kind!, _cyan),
                ],),
                if (project.changeSummary != null && project.changeSummary!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(project.changeSummary!, style: const TextStyle(color: _muted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Calendar tab ───────────────────────────────────────────────────────────────

class _CalendarTab extends ConsumerWidget {
  final String serverId;
  const _CalendarTab({required this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(mcCalendarProvider(serverId)).when(
      loading: _shimmer,
      error: (e, _) => _sectionError(e),
      data: (events) => events.isEmpty
          ? _sectionEmpty('No scheduled jobs', 'No cron events found in OpenClaw', Icons.schedule_outlined)
          : RefreshIndicator(
              color: _red,
              backgroundColor: _card,
              onRefresh: () async => mcRefresh(ref, serverId),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: events.length,
                itemBuilder: (_, i) => _CalendarRow(event: events[i]),
              ),
            ),
    );
  }
}

class _CalendarRow extends StatelessWidget {
  final McCalendarEvent event;
  const _CalendarRow({required this.event});

  @override
  Widget build(BuildContext context) {
    final on = event.enabled;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: on ? _border : _dimmed),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: (on ? _amber : _muted).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(on ? Icons.schedule : Icons.pause_circle_outline, color: on ? _amber : _muted, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.name, style: TextStyle(color: on ? _white : _muted, fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(children: [
                  if (event.expr != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: _amber.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                      child: Text(event.expr!, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: _amber)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (event.agentId != null)
                    Text(event.agentId!, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: _muted)),
                ],),
                if (event.lastRunAt != null) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Text('Last: ${event.lastRunAt}', style: const TextStyle(fontSize: 11, color: _muted)),
                    if (event.lastStatus != null) ...[const SizedBox(width: 8), _badge(event.lastStatus!, event.statusColor)],
                  ],),
                ],
              ],
            ),
          ),
          Container(
            width: 10, height: 10,
            decoration: BoxDecoration(color: on ? _green : _dimmed, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

// ── Memory tab ─────────────────────────────────────────────────────────────────

class _MemoryTab extends ConsumerWidget {
  final String serverId;
  const _MemoryTab({required this.serverId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(mcMemoryProvider(serverId)).when(
      loading: _shimmer,
      error: (e, _) => _sectionError(e),
      data: (entries) => entries.isEmpty
          ? _sectionEmpty('No memory entries', "OpenClaw hasn't indexed any memory yet", Icons.memory_outlined)
          : RefreshIndicator(
              color: _red,
              backgroundColor: _card,
              onRefresh: () async => mcRefresh(ref, serverId),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                itemCount: entries.length,
                itemBuilder: (_, i) => _MemoryRow(entry: entries[i]),
              ),
            ),
    );
  }
}

class _MemoryRow extends StatelessWidget {
  final McMemoryEntry entry;
  const _MemoryRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => _BottomSheet(
          title: entry.displayPath,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.startLine != null)
                Text('Lines ${entry.startLine}–${entry.endLine ?? entry.startLine}',
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: _muted),),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: _border)),
                child: SelectableText(entry.text,
                    style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12, color: _white, height: 1.6),),
              ),
              if (entry.updatedAt != null) ...[
                const SizedBox(height: 8),
                Text(entry.updatedAt!, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: _dimmed)),
              ],
            ],
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.code, size: 12, color: _cyan),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(entry.displayPath,
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: _cyan),
                      overflow: TextOverflow.ellipsis,),
                ),
                if (entry.startLine != null)
                  Text('L${entry.startLine}',
                      style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: _muted),),
              ],
            ),
            const SizedBox(height: 8),
            Text(entry.text, style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
                maxLines: 3, overflow: TextOverflow.ellipsis,),
          ],
        ),
      ),
    );
  }
}

// ── Create Task sheet ──────────────────────────────────────────────────────────

void _showCreateTask(BuildContext context, WidgetRef ref, String serverId) {
  showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _CreateTaskForm(serverId: serverId),
  );
}

class _CreateTaskForm extends ConsumerStatefulWidget {
  final String serverId;
  const _CreateTaskForm({required this.serverId});

  @override
  ConsumerState<_CreateTaskForm> createState() => _CreateTaskFormState();
}

class _CreateTaskFormState extends ConsumerState<_CreateTaskForm> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _priority = 'medium';
  String? _agentId; // null = use OpenClaw default
  bool _loading = false;
  String? _output;
  bool _success = false;

  static const _priorities = ['low', 'medium', 'high', 'critical'];
  static const _priorityColors = {
    'low': _muted, 'medium': _cyan, 'high': _amber, 'critical': _red,
  };

  @override
  void dispose() { _titleCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() { _loading = true; _output = null; });
    try {
      final out = await _mcRepo(ref, widget.serverId).createTask(
        title,
        description: _descCtrl.text.trim(),
        priority: _priority,
        agentId: _agentId,
      );
      if (!mounted) return;
      setState(() { _loading = false; _output = out.isEmpty ? '✓ Task created' : out; _success = true; });
      mcRefresh(ref, widget.serverId);
      await Future.delayed(const Duration(milliseconds: 1400));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _output = e.toString(); _success = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final agentsAsync = ref.watch(mcAgentsProvider(widget.serverId));
    final agents = agentsAsync.valueOrNull ?? [];

    return _BottomSheet(
      title: 'New Task',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          const Text('Title', style: _labelStyle),
          const SizedBox(height: 6),
          _InputField(ctrl: _titleCtrl, hint: 'What needs to be done?', maxLines: 2),
          const SizedBox(height: 16),

          // Description
          const Text('Description', style: _labelStyle),
          const SizedBox(height: 6),
          _InputField(ctrl: _descCtrl, hint: 'Provide context for the agent…', maxLines: 3),
          const SizedBox(height: 16),

          // Agent picker
          Row(
            children: [
              const Text('Assign to Agent', style: _labelStyle),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('optional', style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: _cyan, letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              // "Default" pill
              _AgentPill(
                label: 'Default',
                selected: _agentId == null,
                onTap: () => setState(() => _agentId = null),
              ),
              // Live agent pills
              ...agents.map((a) => _AgentPill(
                label: a.agentId,
                selected: _agentId == a.agentId,
                onTap: () => setState(() => _agentId = a.agentId),
              ),),
            ],
          ),
          const SizedBox(height: 16),

          // Priority
          const Text('Priority', style: _labelStyle),
          const SizedBox(height: 8),
          Row(
            children: _priorities.map((p) {
              final active = _priority == p;
              final c = _priorityColors[p]!;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _priority = p),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: active ? c.withValues(alpha: 0.18) : _surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: active ? c : _border, width: active ? 1.5 : 1),
                    ),
                    child: Center(
                      child: Text(
                        '${p[0].toUpperCase()}${p.substring(1)}',
                        style: TextStyle(
                          color: active ? c : _muted, fontSize: 11,
                          fontWeight: FontWeight.w700, fontFamily: 'JetBrainsMono',
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          if (_output != null) ...[
            _OutputBox(text: _output!, success: _success),
            const SizedBox(height: 12),
          ],
          _ActionButton(
            label: _loading
                ? 'Launching…'
                : _agentId != null
                    ? 'Launch → $_agentId'
                    : 'Launch Task',
            icon: Icons.rocket_launch_outlined,
            color: _red,
            enabled: !_loading,
            onTap: _submit,
          ),
          SizedBox(height: keyboardH),
        ],
      ),
    );
  }
}

// ── Spawn Agent sheet ──────────────────────────────────────────────────────────

const _soulPresets = [
  ('Relentless', 'Assumes nothing works until proven. Traces every call, questions every assumption. Ships only when certain.'),
  ('Architect', 'Builds for simplicity first. Challenges complexity with a raised eyebrow. Designs what future engineers will thank.'),
  ('Guardian', 'Trusts no input. Checks every boundary, every permission, every secret. Security is the foundation.'),
  ('Speedster', 'Measures before optimising. Cares deeply about user-facing latency. Fast is a feature, not an afterthought.'),
  ('Tester', 'Coverage is safety. Every edge case deserves a name. Breaks things on purpose so production never has to.'),
  ('Wordsmith', 'Code is communication. Documentation is kindness. Writes for the engineer debugging at 2am.'),
];

void _showSpawnAgent(BuildContext context, WidgetRef ref, String serverId) {
  showModalBottomSheet(
    context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
    builder: (_) => _SpawnAgentForm(serverId: serverId),
  );
}

class _SpawnAgentForm extends ConsumerStatefulWidget {
  final String serverId;
  const _SpawnAgentForm({required this.serverId});

  @override
  ConsumerState<_SpawnAgentForm> createState() => _SpawnAgentFormState();
}

class _SpawnAgentFormState extends ConsumerState<_SpawnAgentForm> {
  final _nameCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  final _soulCtrl = TextEditingController();
  bool _loading = false;
  String? _output;
  bool _success = false;

  @override
  void dispose() { _nameCtrl.dispose(); _roleCtrl.dispose(); _soulCtrl.dispose(); super.dispose(); }

  Future<void> _spawn() async {
    final name = _nameCtrl.text.trim();
    final role = _roleCtrl.text.trim();
    if (name.isEmpty || role.isEmpty) return;
    setState(() { _loading = true; _output = null; });
    try {
      final out = await _mcRepo(ref, widget.serverId)
          .spawnAgent(name, role, _soulCtrl.text.trim());
      if (!mounted) return;
      setState(() { _loading = false; _output = out.isEmpty ? '✓ Agent commissioned' : out; _success = true; });
      mcRefresh(ref, widget.serverId);
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _output = e.toString(); _success = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    return _BottomSheet(
      title: 'Commission Agent',
      titleColor: _purple,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Name', style: _labelStyle),
          const SizedBox(height: 6),
          _InputField(ctrl: _nameCtrl, hint: 'Atlas, Nova, Orion, Lyra…'),
          const SizedBox(height: 16),
          const Text('Role', style: _labelStyle),
          const SizedBox(height: 6),
          _InputField(ctrl: _roleCtrl, hint: 'Senior Code Reviewer, DevOps Specialist…'),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Soul', style: _labelStyle),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('personality', style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 9, color: _purple, letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6, runSpacing: 6,
            children: _soulPresets.map((p) => GestureDetector(
              onTap: () => setState(() => _soulCtrl.text = p.$2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _purple.withValues(alpha: 0.25)),
                ),
                child: Text(p.$1, style: const TextStyle(color: _purple, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
            ),).toList(),
          ),
          const SizedBox(height: 10),
          _InputField(ctrl: _soulCtrl, hint: "Describe this agent's personality and approach…", maxLines: 4),
          const SizedBox(height: 24),
          if (_output != null) ...[
            _OutputBox(text: _output!, success: _success),
            const SizedBox(height: 12),
          ],
          _ActionButton(
            label: _loading ? 'Bringing to life…' : 'Bring to Life',
            icon: Icons.auto_awesome,
            color: _purple,
            enabled: !_loading,
            onTap: _spawn,
          ),
          SizedBox(height: keyboardH),
        ],
      ),
    );
  }
}

// ── Shared form components ─────────────────────────────────────────────────────

const _labelStyle = TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: _muted, letterSpacing: 0.4);

class _InputField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final int maxLines;
  const _InputField({required this.ctrl, required this.hint, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      style: const TextStyle(color: _white, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF444444), fontSize: 13),
        filled: true,
        fillColor: _surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _red, width: 1.5)),
      ),
    );
  }
}

class _OutputBox extends StatelessWidget {
  final String text;
  final bool success;
  const _OutputBox({required this.text, required this.success});

  @override
  Widget build(BuildContext context) {
    final c = success ? _green : _red;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: c.withValues(alpha: 0.25))),
      child: Text(text, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: c)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  const _ActionButton({required this.label, required this.icon, required this.color, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.15) : _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: enabled ? color.withValues(alpha: 0.5) : _border),
          boxShadow: enabled ? [BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 14)] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: enabled ? color : _muted, size: 18),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(color: enabled ? color : _muted, fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
          ],
        ),
      ),
    );
  }
}

class _Fab extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _Fab({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _white, size: 18),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: _white, fontSize: 14, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ── Agent pill ─────────────────────────────────────────────────────────────────

class _AgentPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AgentPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _cyan.withValues(alpha: 0.15) : _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? _cyan.withValues(alpha: 0.5) : _border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 11,
            color: selected ? _cyan : _muted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ── Reusable bottom sheet chrome ───────────────────────────────────────────────

class _BottomSheet extends StatelessWidget {
  final String title;
  final Color titleColor;
  final Widget child;
  const _BottomSheet({required this.title, required this.child, this.titleColor = _white});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: _border)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(width: 36, height: 4, decoration: BoxDecoration(color: _dimmed, borderRadius: BorderRadius.circular(2))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Text(title, style: TextStyle(color: titleColor, fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  GestureDetector(onTap: () => Navigator.pop(context), child: const Icon(Icons.close, color: _muted, size: 20)),
                ],
              ),
            ),
            const Divider(color: _border, height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                padding: const EdgeInsets.all(20),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Key-value row used in detail sheets ───────────────────────────────────────

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(k, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 11, color: _muted)),
          ),
          Expanded(child: Text(v, style: const TextStyle(color: _white, fontSize: 13))),
        ],
      ),
    );
