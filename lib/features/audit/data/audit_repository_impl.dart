import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/database/mappers.dart';
import '../../../shared/models/audit_log_entry.dart';
import '../../../shared/providers/db_providers.dart';
import '../domain/audit_repository.dart';

class AuditRepositoryImpl implements AuditRepository {
  final AppDatabase _db;
  AuditRepositoryImpl(this._db);

  @override
  Stream<List<AuditLogEntry>> watchAll({String? serverId, bool? successOnly}) {
    final q = _db.select(_db.auditLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
    if (serverId != null) q.where((t) => t.serverId.equals(serverId));
    if (successOnly != null) q.where((t) => t.success.equals(successOnly));
    return q.watch().map((rows) => rows.map((r) => r.toModel()).toList());
  }

  @override
  Future<List<AuditLogEntry>> getAll({String? serverId, bool? successOnly}) async {
    final q = _db.select(_db.auditLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
    if (serverId != null) q.where((t) => t.serverId.equals(serverId));
    if (successOnly != null) q.where((t) => t.success.equals(successOnly));
    final rows = await q.get();
    return rows.map((r) => r.toModel()).toList();
  }

  @override
  Future<void> log({
    String? serverId,
    String? serverNickname,
    required String actionType,
    required String transport,
    required bool success,
    String? rawCommand,
    String? commandTemplateName,
    String? shortOutputSummary,
    String? errorSummary,
  }) async {
    final entry = AuditLogEntry(
      id: const Uuid().v4(),
      timestamp: DateTime.now(),
      serverId: serverId,
      serverNickname: serverNickname,
      actionType: _parseAction(actionType),
      rawCommand: rawCommand,
      commandTemplateName: commandTemplateName,
      transport: _parseTransport(transport),
      success: success,
      shortOutputSummary: shortOutputSummary,
      errorSummary: errorSummary,
    );
    await _db.into(_db.auditLogs).insert(auditLogToCompanion(entry));
  }

  @override
  Future<void> clearAll() async {
    await _db.delete(_db.auditLogs).go();
  }

  AuditActionType _parseAction(String name) {
    for (final v in AuditActionType.values) {
      if (v.name == name) return v;
    }
    return AuditActionType.runCommand;
  }

  AuditTransport _parseTransport(String name) {
    for (final v in AuditTransport.values) {
      if (v.name == name) return v;
    }
    return AuditTransport.local;
  }
}

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  return AuditRepositoryImpl(ref.watch(appDatabaseProvider));
});

final auditStreamProvider = StreamProvider.autoDispose.family<
    List<AuditLogEntry>, ({String? serverId, bool? successOnly})>((ref, f) {
  return ref.watch(auditRepositoryProvider).watchAll(
        serverId: f.serverId,
        successOnly: f.successOnly,
      );
});
