import 'dart:convert';

import 'package:flutter/material.dart';

// ── Status colours ─────────────────────────────────────────────────────────────

Color mcStatusColor(String? s) => switch (s?.toLowerCase()) {
      'running' || 'active' || 'connected' => const Color(0xFF00E6FF),
      'done' || 'success' || 'completed' || 'healthy' => const Color(0xFF4CAF50),
      'failed' || 'error' || 'critical' => const Color(0xFFFF3B1F),
      'pending' || 'waiting' || 'queued' => const Color(0xFFFFB800),
      'cancelled' || 'disabled' || 'idle' => const Color(0xFF888888),
      _ => const Color(0xFF888888),
    };

String mcTimeAgo(dynamic epochMs) {
  if (epochMs == null) return '';
  final ms = epochMs is int ? epochMs : int.tryParse(epochMs.toString());
  if (ms == null || ms == 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${(diff.inDays / 30).floor()}mo ago';
}

String mcDuration(int? startMs, int? endMs) {
  if (startMs == null || endMs == null) return '';
  final d = Duration(milliseconds: endMs - startMs);
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  if (d.inMinutes < 60) return '${d.inMinutes}m ${d.inSeconds % 60}s';
  return '${d.inHours}h ${d.inMinutes % 60}m';
}

// ── McTask ─────────────────────────────────────────────────────────────────────

class McTask {
  final String id;
  final String title;
  final String? description;
  final String status;
  final String? taskKind;
  final String? label;
  final String? agentId;
  final String? error;
  final int? createdAt;
  final int? startedAt;
  final int? endedAt;

  const McTask({
    required this.id,
    required this.title,
    this.description,
    this.status = 'pending',
    this.taskKind,
    this.label,
    this.agentId,
    this.error,
    this.createdAt,
    this.startedAt,
    this.endedAt,
  });

  factory McTask.fromJson(Map<String, dynamic> j) => McTask(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '(untitled)',
        description: j['description']?.toString(),
        status: j['status']?.toString() ?? 'pending',
        taskKind: (j['taskKind'] ?? j['task_kind'])?.toString(),
        label: j['label']?.toString(),
        agentId: (j['agentId'] ?? j['agent_id'])?.toString(),
        error: j['error']?.toString(),
        createdAt: (j['createdAt'] ?? j['created_at']) as int?,
        startedAt: (j['startedAt'] ?? j['started_at']) as int?,
        endedAt: (j['endedAt'] ?? j['ended_at']) as int?,
      );

  static List<McTask> parseList(String raw) {
    try {
      final list = jsonDecode(raw.trim()) as List;
      return list.map((e) => McTask.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Color get statusColor => mcStatusColor(status);
  String get timeAgo => mcTimeAgo(createdAt);
  String get runDuration => mcDuration(startedAt, endedAt);
}

// ── McAgent ────────────────────────────────────────────────────────────────────

class McAgent {
  final String agentId;
  final String name;
  final String role;
  final String soul;
  final String status;
  final int sessionCount;
  final List<String> models;

  const McAgent({
    required this.agentId,
    required this.name,
    required this.role,
    required this.soul,
    this.status = 'idle',
    this.sessionCount = 0,
    this.models = const [],
  });

  factory McAgent.fromJson(String id, Map<String, dynamic> j) {
    final sessions = j['sessions'] as List? ?? [];
    final latestSession = sessions.isNotEmpty
        ? sessions.last as Map<String, dynamic>
        : <String, dynamic>{};
    return McAgent(
      agentId: id,
      name: j['name']?.toString() ?? id,
      role: j['role']?.toString() ?? 'AI Agent',
      soul: (j['soul'] ?? j['instructions'] ?? j['systemPrompt'] ?? '').toString(),
      status: latestSession['status']?.toString() ?? j['latestStatus']?.toString() ?? 'idle',
      sessionCount: sessions.length,
      models: (j['models'] as List? ?? []).map((e) => e.toString()).toList(),
    );
  }

  static List<McAgent> parseSessionsJson(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is Map) {
        return decoded.entries.map((e) {
          final data = e.value is Map
              ? e.value as Map<String, dynamic>
              : <String, dynamic>{};
          return McAgent.fromJson(e.key.toString(), data);
        }).toList();
      }
      if (decoded is List) {
        return decoded.map((e) {
          final m = e as Map<String, dynamic>;
          return McAgent.fromJson(m['agentId']?.toString() ?? m['id']?.toString() ?? '', m);
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Color get statusColor => mcStatusColor(status);

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }
}

// ── McProject ──────────────────────────────────────────────────────────────────

class McProject {
  final String slug;
  final String name;
  final String? kind;
  final String? branch;
  final String? changeSummary;
  final String? relativePath;
  final String? lastUpdated;

  const McProject({
    required this.slug,
    required this.name,
    this.kind,
    this.branch,
    this.changeSummary,
    this.relativePath,
    this.lastUpdated,
  });

  factory McProject.fromJson(Map<String, dynamic> j) => McProject(
        slug: j['slug']?.toString() ?? j['name']?.toString() ?? '',
        name: j['name']?.toString() ?? j['slug']?.toString() ?? '(unnamed)',
        kind: j['kind']?.toString(),
        branch: j['branch']?.toString(),
        changeSummary: (j['changeSummary'] ?? j['change_summary'])?.toString(),
        relativePath: (j['relativePath'] ?? j['relative_path'])?.toString(),
        lastUpdated: (j['lastUpdated'] ?? j['last_updated'])?.toString(),
      );

  static List<McProject> parseList(String raw) {
    final trimmed = raw.trim();
    try {
      final list = jsonDecode(trimmed) as List;
      return list.map((e) => McProject.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return trimmed
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((path) {
            final name = path.trim().split('/').last;
            return McProject(slug: name, name: name, relativePath: path.trim());
          })
          .toList();
    }
  }
}

// ── McCalendarEvent ────────────────────────────────────────────────────────────

class McCalendarEvent {
  final String id;
  final String name;
  final bool enabled;
  final String? agentId;
  final String? scheduleKind;
  final String? expr;
  final String? payloadText;
  final String? lastRunAt;
  final String? lastStatus;

  const McCalendarEvent({
    required this.id,
    required this.name,
    this.enabled = true,
    this.agentId,
    this.scheduleKind,
    this.expr,
    this.payloadText,
    this.lastRunAt,
    this.lastStatus,
  });

  factory McCalendarEvent.fromJson(Map<String, dynamic> j) => McCalendarEvent(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '(unnamed)',
        enabled: j['enabled'] as bool? ?? true,
        agentId: j['agentId']?.toString(),
        scheduleKind: j['scheduleKind']?.toString(),
        expr: j['expr']?.toString(),
        payloadText: j['payloadText']?.toString(),
        lastRunAt: j['lastRunAt']?.toString(),
        lastStatus: j['lastStatus']?.toString(),
      );

  static List<McCalendarEvent> parseList(String raw) {
    try {
      final decoded = jsonDecode(raw.trim());
      if (decoded is List) {
        return decoded.map((e) => McCalendarEvent.fromJson(e as Map<String, dynamic>)).toList();
      }
      if (decoded is Map) {
        return (decoded['jobs'] as List? ?? decoded.values.toList())
            .map((e) => McCalendarEvent.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Color get statusColor => mcStatusColor(lastStatus);
}

// ── McMemoryEntry ──────────────────────────────────────────────────────────────

class McMemoryEntry {
  final String id;
  final String? path;
  final String? source;
  final int? startLine;
  final int? endLine;
  final String text;
  final String? updatedAt;

  const McMemoryEntry({
    required this.id,
    this.path,
    this.source,
    this.startLine,
    this.endLine,
    required this.text,
    this.updatedAt,
  });

  factory McMemoryEntry.fromJson(Map<String, dynamic> j) => McMemoryEntry(
        id: j['id']?.toString() ?? '',
        path: j['path']?.toString(),
        source: j['source']?.toString(),
        startLine: (j['startLine'] ?? j['start_line']) as int?,
        endLine: (j['endLine'] ?? j['end_line']) as int?,
        text: j['text']?.toString() ?? '',
        updatedAt: (j['updatedAt'] ?? j['updated_at'])?.toString(),
      );

  static List<McMemoryEntry> parseList(String raw) {
    try {
      final list = jsonDecode(raw.trim()) as List;
      return list.map((e) => McMemoryEntry.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  String get displayPath {
    final p = path ?? source ?? '';
    if (p.isEmpty) return 'memory';
    final parts = p.split('/');
    return parts.length > 2 ? '…/${parts.sublist(parts.length - 2).join('/')}' : p;
  }
}
