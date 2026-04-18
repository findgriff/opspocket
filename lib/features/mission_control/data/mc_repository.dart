import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ssh/domain/ssh_client.dart';
import '../../ssh/presentation/ssh_connection_notifier.dart';
import '../domain/mc_models.dart';

// ── SSH command wrappers ───────────────────────────────────────────────────────

const _clawdPrefix =
    r"""su - clawd -c 'export PATH="$HOME/.npm-global/bin:$PATH"; """;

String _clawdCmd(String cmd) => "$_clawdPrefix$cmd'";

const _tasksSql =
    'SELECT task_id as id, '
    'COALESCE(label, task_kind, "task") as title, '
    'task as description, task_kind as taskKind, '
    'status, agent_id as agentId, label, error, '
    'created_at as createdAt, started_at as startedAt, ended_at as endedAt '
    'FROM task_runs '
    'ORDER BY COALESCE(last_event_at, started_at, created_at) DESC '
    'LIMIT 100';

const _memorySql =
    'SELECT id, path, source, '
    'start_line as startLine, end_line as endLine, '
    'text, updated_at as updatedAt '
    'FROM chunks ORDER BY updated_at DESC LIMIT 100';

// ── Repository ─────────────────────────────────────────────────────────────────

class McRepository {
  final SshClient _client;
  const McRepository(this._client);

  Future<String> _exec(String cmd) async {
    final r = await _client.exec(cmd, timeout: const Duration(seconds: 20));
    return r.stdout.trim();
  }

  Future<List<McTask>> fetchTasks() async {
    final out = await _exec(
      _clawdCmd(
        'sqlite3 -json ~/.openclaw/tasks/runs.sqlite "$_tasksSql" 2>/dev/null || echo "[]"',
      ),
    );
    return McTask.parseList(out.isEmpty ? '[]' : out);
  }

  Future<List<McAgent>> fetchAgents() async {
    final out = await _exec(
      _clawdCmd(
        'cat ~/.openclaw/agents/main/sessions/sessions.json 2>/dev/null || echo "{}"',
      ),
    );
    return McAgent.parseSessionsJson(out.isEmpty ? '{}' : out);
  }

  Future<List<McProject>> fetchProjects() async {
    final out = await _exec(
      _clawdCmd(
        r'find ~/clawd -maxdepth 3 -name ".git" -type d 2>/dev/null | sed "s|/.git||" | head -20 || echo ""',
      ),
    );
    return McProject.parseList(out);
  }

  Future<List<McCalendarEvent>> fetchCalendar() async {
    final out = await _exec(
      _clawdCmd(
        'cat ~/.openclaw/cron/jobs.json 2>/dev/null || echo "[]"',
      ),
    );
    return McCalendarEvent.parseList(out.isEmpty ? '[]' : out);
  }

  Future<List<McMemoryEntry>> fetchMemory() async {
    final out = await _exec(
      _clawdCmd(
        'sqlite3 -json ~/.openclaw/memory/main.sqlite "$_memorySql" 2>/dev/null || echo "[]"',
      ),
    );
    return McMemoryEntry.parseList(out.isEmpty ? '[]' : out);
  }

  Future<String> createTask(
    String title, {
    String? description,
    String priority = 'medium',
    String? agentId,
  }) async {
    final titleEsc = title.replaceAll('"', '\\"');
    final desc = description != null && description.isNotEmpty
        ? ' --description "${description.replaceAll('"', '\\"')}"'
        : '';
    final agent = agentId != null && agentId.isNotEmpty
        ? ' --agent "${agentId.replaceAll('"', '\\"')}"'
        : '';
    return _exec(
      _clawdCmd('openclaw tasks create "$titleEsc"$desc$agent --priority $priority 2>&1'),
    );
  }

  Future<String> spawnAgent(String name, String role, String soul) async {
    final n = name.replaceAll('"', '\\"');
    final r = role.replaceAll('"', '\\"');
    final s = soul.replaceAll('"', '\\"').replaceAll('\n', ' ');
    return _exec(
      _clawdCmd('openclaw agents new --name "$n" --role "$r" --instructions "$s" 2>&1'),
    );
  }
}

// ── Refresh counter trick — bump to invalidate ─────────────────────────────────

final _mcRefreshProvider = StateProvider.family<int, String>((_, __) => 0);

// ── Providers ─────────────────────────────────────────────────────────────────

McRepository _repo(Ref ref, String serverId) =>
    McRepository(ref.read(sshClientProvider(serverId)));

final mcTasksProvider =
    FutureProvider.autoDispose.family<List<McTask>, String>((ref, id) async {
  ref.watch(_mcRefreshProvider(id));
  return _repo(ref, id).fetchTasks();
});

final mcAgentsProvider =
    FutureProvider.autoDispose.family<List<McAgent>, String>((ref, id) async {
  ref.watch(_mcRefreshProvider(id));
  return _repo(ref, id).fetchAgents();
});

final mcProjectsProvider =
    FutureProvider.autoDispose.family<List<McProject>, String>((ref, id) async {
  ref.watch(_mcRefreshProvider(id));
  return _repo(ref, id).fetchProjects();
});

final mcCalendarProvider =
    FutureProvider.autoDispose.family<List<McCalendarEvent>, String>((ref, id) async {
  ref.watch(_mcRefreshProvider(id));
  return _repo(ref, id).fetchCalendar();
});

final mcMemoryProvider =
    FutureProvider.autoDispose.family<List<McMemoryEntry>, String>((ref, id) async {
  ref.watch(_mcRefreshProvider(id));
  return _repo(ref, id).fetchMemory();
});

void mcRefresh(WidgetRef ref, String serverId) =>
    ref.read(_mcRefreshProvider(serverId).notifier).state++;
