import '../../../shared/models/audit_log_entry.dart';

abstract class AuditRepository {
  Stream<List<AuditLogEntry>> watchAll({String? serverId, bool? successOnly});
  Future<List<AuditLogEntry>> getAll({String? serverId, bool? successOnly});

  /// Convenience wrapper around insert. Accepts enum-like string names so
  /// callers don't all have to import the enum set.
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
  });

  Future<void> clearAll();
}
