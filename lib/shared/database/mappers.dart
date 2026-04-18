import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../models/audit_log_entry.dart';
import '../models/command_template.dart';
import '../models/host_fingerprint_record.dart';
import '../models/provider_credential.dart';
import '../models/quick_action.dart';
import '../models/server_profile.dart';
import 'app_database.dart';

List<String> _decodeStringList(String json) {
  if (json.isEmpty) return const [];
  try {
    final list = jsonDecode(json);
    if (list is List) return list.map((e) => e.toString()).toList();
  } catch (_) {}
  return const [];
}

String _encodeStringList(List<String> list) => jsonEncode(list);

T _enumByName<T extends Enum>(List<T> values, String name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

extension ServerProfileMapping on ServerProfileData {
  ServerProfile toModel() => ServerProfile(
        id: id,
        nickname: nickname,
        hostnameOrIp: hostnameOrIp,
        port: port,
        username: username,
        authMethod: _enumByName(SshAuthMethod.values, authMethod, SshAuthMethod.privateKey),
        privateKeyLabel: privateKeyLabel,
        secureStorageKey: secureStorageKey,
        hasPassphrase: hasPassphrase,
        tags: _decodeStringList(tagsJson),
        notes: notes,
        providerType: _enumByName(ProviderType.values, providerType, ProviderType.none),
        providerResourceId: providerResourceId,
        isFavorite: isFavorite,
        lastConnectedAt: lastConnectedAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

ServerProfilesCompanion serverProfileToCompanion(ServerProfile p) {
  return ServerProfilesCompanion.insert(
    id: p.id,
    nickname: p.nickname,
    hostnameOrIp: p.hostnameOrIp,
    port: Value(p.port),
    username: p.username,
    authMethod: p.authMethod.name,
    privateKeyLabel: Value(p.privateKeyLabel),
    secureStorageKey: Value(p.secureStorageKey),
    hasPassphrase: Value(p.hasPassphrase),
    tagsJson: Value(_encodeStringList(p.tags)),
    notes: Value(p.notes),
    providerType: Value(p.providerType.name),
    providerResourceId: Value(p.providerResourceId),
    isFavorite: Value(p.isFavorite),
    lastConnectedAt: Value(p.lastConnectedAt),
    createdAt: p.createdAt,
    updatedAt: p.updatedAt,
  );
}

extension CommandTemplateMapping on CommandTemplateData {
  CommandTemplate toModel() => CommandTemplate(
        id: id,
        name: name,
        category: _enumByName(CommandCategory.values, category, CommandCategory.generic),
        commandText: commandText,
        placeholders: _decodeStringList(placeholdersJson),
        dangerous: dangerous,
        isBuiltin: isBuiltin,
        isFavorite: isFavorite,
        description: description,
        applicableStack: _decodeStringList(applicableStackJson),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

CommandTemplatesCompanion commandTemplateToCompanion(CommandTemplate t) {
  return CommandTemplatesCompanion.insert(
    id: t.id,
    name: t.name,
    category: t.category.name,
    commandText: t.commandText,
    placeholdersJson: Value(_encodeStringList(t.placeholders)),
    dangerous: Value(t.dangerous),
    isBuiltin: Value(t.isBuiltin),
    isFavorite: Value(t.isFavorite),
    description: Value(t.description),
    applicableStackJson: Value(_encodeStringList(t.applicableStack)),
    createdAt: t.createdAt,
    updatedAt: t.updatedAt,
  );
}

extension QuickActionMapping on QuickActionData {
  QuickAction toModel() => QuickAction(
        id: id,
        label: label,
        emoji: emoji,
        templateId: templateId,
        sortOrder: sortOrder,
        visible: visible,
        isBuiltin: isBuiltin,
      );
}

QuickActionsCompanion quickActionToCompanion(QuickAction q) {
  return QuickActionsCompanion.insert(
    id: q.id,
    label: q.label,
    emoji: Value(q.emoji),
    templateId: q.templateId,
    sortOrder: Value(q.sortOrder),
    visible: Value(q.visible),
    isBuiltin: Value(q.isBuiltin),
  );
}

extension AuditLogMapping on AuditLogData {
  AuditLogEntry toModel() => AuditLogEntry(
        id: id,
        timestamp: timestamp,
        serverId: serverId,
        serverNickname: serverNickname,
        actionType: _enumByName(AuditActionType.values, actionType, AuditActionType.runCommand),
        commandTemplateName: commandTemplateName,
        rawCommand: rawCommand,
        transport: _enumByName(AuditTransport.values, transport, AuditTransport.local),
        success: success,
        shortOutputSummary: shortOutputSummary,
        errorSummary: errorSummary,
      );
}

AuditLogsCompanion auditLogToCompanion(AuditLogEntry e) {
  return AuditLogsCompanion.insert(
    id: e.id,
    timestamp: e.timestamp,
    serverId: Value(e.serverId),
    serverNickname: Value(e.serverNickname),
    actionType: e.actionType.name,
    commandTemplateName: Value(e.commandTemplateName),
    rawCommand: Value(e.rawCommand),
    transport: e.transport.name,
    success: e.success,
    shortOutputSummary: Value(e.shortOutputSummary),
    errorSummary: Value(e.errorSummary),
  );
}

extension HostFingerprintMapping on HostFingerprintData {
  HostFingerprintRecord toModel() => HostFingerprintRecord(
        id: id,
        serverId: serverId,
        hostnameOrIp: hostnameOrIp,
        port: port,
        fingerprint: fingerprint,
        acceptedAt: acceptedAt,
        lastSeenAt: lastSeenAt,
      );
}

HostFingerprintsCompanion hostFingerprintToCompanion(HostFingerprintRecord r) {
  return HostFingerprintsCompanion.insert(
    id: r.id,
    serverId: r.serverId,
    hostnameOrIp: r.hostnameOrIp,
    port: r.port,
    fingerprint: r.fingerprint,
    acceptedAt: r.acceptedAt,
    lastSeenAt: Value(r.lastSeenAt),
  );
}

extension ProviderCredentialMapping on ProviderCredentialData {
  ProviderCredential toModel() => ProviderCredential(
        id: id,
        providerType: _enumByName(ProviderType.values, providerType, ProviderType.none),
        label: label,
        secureStorageKey: secureStorageKey,
        createdAt: createdAt,
        lastUsedAt: lastUsedAt,
      );
}

ProviderCredentialsCompanion providerCredentialToCompanion(ProviderCredential c) {
  return ProviderCredentialsCompanion.insert(
    id: c.id,
    providerType: c.providerType.name,
    label: c.label,
    secureStorageKey: c.secureStorageKey,
    createdAt: c.createdAt,
    lastUsedAt: Value(c.lastUsedAt),
  );
}
