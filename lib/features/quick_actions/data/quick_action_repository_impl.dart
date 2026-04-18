import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/database/mappers.dart';
import '../../../shared/models/quick_action.dart';
import '../../../shared/providers/db_providers.dart';
import '../domain/quick_action_repository.dart';

class QuickActionRepositoryImpl implements QuickActionRepository {
  final AppDatabase _db;
  QuickActionRepositoryImpl(this._db);

  @override
  Stream<List<QuickAction>> watchVisible() {
    final q = _db.select(_db.quickActions)
      ..where((t) => t.visible.equals(true))
      ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return q.watch().map((rows) => rows.map((r) => r.toModel()).toList());
  }

  @override
  Future<List<QuickAction>> getAll() async {
    final rows = await _db.select(_db.quickActions).get();
    return rows.map((r) => r.toModel()).toList();
  }

  @override
  Future<void> upsert(QuickAction action) async {
    await _db.into(_db.quickActions).insertOnConflictUpdate(quickActionToCompanion(action));
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.quickActions)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> seedDefaultsIfEmpty() async {
    final existing = await getAll();
    final existingIds = existing.map((a) => a.id).toSet();

    // Always-present defaults — only inserted when the table is empty.
    if (existing.isEmpty) {
      const firstRun = <QuickAction>[
        QuickAction(
          id: 'qa.status',
          label: 'VPS Status',
          emoji: '🩺',
          templateId: 'builtin.generic.status',
          sortOrder: 10,
          isBuiltin: true,
        ),
        QuickAction(
          id: 'qa.restart_service',
          label: 'Restart service',
          emoji: '🔁',
          templateId: 'builtin.systemd.restart',
          sortOrder: 30,
          isBuiltin: true,
        ),
        QuickAction(
          id: 'qa.pm2_restart',
          label: 'PM2 restart',
          emoji: '🟢',
          templateId: 'builtin.pm2.restart',
          sortOrder: 60,
          isBuiltin: true,
        ),
        QuickAction(
          id: 'qa.reboot',
          label: 'Reboot server',
          emoji: '⚠️',
          templateId: 'builtin.server.reboot',
          sortOrder: 70,
          isBuiltin: true,
        ),
      ];
      for (final a in firstRun) {
        await upsert(a);
      }
    }

    // OpenClaw recovery actions — upserted on every launch so new installs
    // and existing installs both get them (stable IDs = no duplicates).
    const ocDefaults = <QuickAction>[
      QuickAction(
        id: 'qa.oc.gateway_restart',
        label: 'OC Gateway restart',
        emoji: '🔄',
        templateId: 'builtin.openclaw.gateway-restart',
        sortOrder: 15,
        isBuiltin: true,
      ),
      QuickAction(
        id: 'qa.oc.gateway_status',
        label: 'OC Gateway status',
        emoji: '📡',
        templateId: 'builtin.openclaw.gateway-status',
        sortOrder: 16,
        isBuiltin: true,
      ),
      QuickAction(
        id: 'qa.oc.pm2_mc',
        label: 'Mission Control PM2',
        emoji: '🚀',
        templateId: 'builtin.pm2.list',
        sortOrder: 17,
        isBuiltin: true,
      ),
      QuickAction(
        id: 'qa.oc.nginx_restart',
        label: 'Nginx restart',
        emoji: '🌐',
        templateId: 'builtin.nginx.restart',
        sortOrder: 18,
        isBuiltin: true,
      ),
      QuickAction(
        id: 'qa.oc.doctor',
        label: 'OpenClaw doctor',
        emoji: '🛠️',
        templateId: 'builtin.openclaw.doctor',
        sortOrder: 19,
        isBuiltin: true,
      ),
    ];
    for (final a in ocDefaults) {
      if (!existingIds.contains(a.id)) {
        await upsert(a);
      }
    }
  }
}

final quickActionRepositoryProvider = Provider<QuickActionRepository>((ref) {
  return QuickActionRepositoryImpl(ref.watch(appDatabaseProvider));
});

final visibleQuickActionsProvider = StreamProvider<List<QuickAction>>((ref) {
  return ref.watch(quickActionRepositoryProvider).watchVisible();
});
