enum AuditActionType {
  sshConnect,
  sshDisconnect,
  runCommand,
  runQuickAction,
  runTemplate,
  providerReboot,
  providerPowerCycle,
  providerStatus,
  settingsChange,
  appUnlock,
  appLock,
  dangerousConfirm,
}

enum AuditTransport {
  ssh,
  providerApi,
  local,
}

class AuditLogEntry {
  final String id;
  final DateTime timestamp;
  final String? serverId;
  final String? serverNickname;
  final AuditActionType actionType;
  final String? commandTemplateName;
  final String? rawCommand;
  final AuditTransport transport;
  final bool success;
  final String? shortOutputSummary;
  final String? errorSummary;

  const AuditLogEntry({
    required this.id,
    required this.timestamp,
    this.serverId,
    this.serverNickname,
    required this.actionType,
    this.commandTemplateName,
    this.rawCommand,
    required this.transport,
    required this.success,
    this.shortOutputSummary,
    this.errorSummary,
  });
}
