import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/features/mission_control/domain/mc_models.dart';

void main() {
  group('McTask.parseList', () {
    test('parses a well-formed task list from sqlite3 -json', () {
      final raw = jsonEncode([
        {
          'id': 'abc',
          'title': 'Patch prod',
          'status': 'running',
          'taskKind': 'patch',
          'agentId': 'atlas',
          'createdAt': 1700000000000,
          'startedAt': 1700000001000,
          'endedAt': 1700000061000,
        },
      ]);
      final tasks = McTask.parseList(raw);
      expect(tasks, hasLength(1));
      expect(tasks.first.id, 'abc');
      expect(tasks.first.title, 'Patch prod');
      expect(tasks.first.runDuration, '1m 0s');
    });

    test('tolerates snake_case keys', () {
      final raw = jsonEncode([
        {
          'id': 'x',
          'title': 't',
          'task_kind': 'deploy',
          'agent_id': 'nova',
          'created_at': 1700000000000,
          'started_at': 1700000000000,
          'ended_at': 1700000005000,
        },
      ]);
      final tasks = McTask.parseList(raw);
      expect(tasks.first.taskKind, 'deploy');
      expect(tasks.first.agentId, 'nova');
      expect(tasks.first.runDuration, '5s');
    });

    test('tolerates numeric values delivered as strings', () {
      // Simulates a backend that JSON-encodes epoch ms as a string.
      final raw = jsonEncode([
        {
          'id': 'x',
          'title': 't',
          'createdAt': '1700000000000',
          'startedAt': '1700000000000',
          'endedAt': '1700000030000',
        },
      ]);
      final tasks = McTask.parseList(raw);
      expect(tasks, hasLength(1));
      expect(tasks.first.runDuration, '30s');
    });

    test('empty / malformed JSON yields an empty list', () {
      expect(McTask.parseList(''), isEmpty);
      expect(McTask.parseList('[]'), isEmpty);
      expect(McTask.parseList('not json'), isEmpty);
    });
  });

  group('McMemoryEntry.parseList', () {
    test('parses numeric line fields as ints even when sent as strings', () {
      final raw = jsonEncode([
        {
          'id': '1',
          'path': 'x/y.dart',
          'start_line': '10',
          'end_line': '42',
          'text': 'hello',
        },
      ]);
      final entries = McMemoryEntry.parseList(raw);
      expect(entries, hasLength(1));
      expect(entries.first.startLine, 10);
      expect(entries.first.endLine, 42);
    });
  });

  group('McAgent.parseSessionsJson', () {
    test('handles map-of-agents form', () {
      final raw = jsonEncode({
        'atlas': {
          'name': 'Atlas',
          'role': 'Reviewer',
          'sessions': [
            {'status': 'active'},
          ],
        },
      });
      final agents = McAgent.parseSessionsJson(raw);
      expect(agents.single.name, 'Atlas');
      expect(agents.single.status, 'active');
      expect(agents.single.sessionCount, 1);
    });

    test('returns an empty list for garbage input rather than throwing', () {
      expect(McAgent.parseSessionsJson('nope'), isEmpty);
      expect(McAgent.parseSessionsJson('{}'), isEmpty);
    });
  });
}
