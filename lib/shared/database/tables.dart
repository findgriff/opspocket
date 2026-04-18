import 'package:drift/drift.dart';

/// Drift table definitions. Keep storage types primitive; enums persist as
/// short strings so we can evolve them without fragile int mapping.
///
/// @DataClassName is applied to every table so generated row classes don't
/// collide with domain model classes of similar names.

@DataClassName('ServerProfileData')
class ServerProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get nickname => text().withLength(min: 1, max: 64)();
  TextColumn get hostnameOrIp => text().withLength(min: 1, max: 253)();
  IntColumn get port => integer().withDefault(const Constant(22))();
  TextColumn get username => text().withLength(min: 1, max: 64)();
  TextColumn get authMethod => text()(); // SshAuthMethod.name
  TextColumn get privateKeyLabel => text().nullable()();
  TextColumn get secureStorageKey => text().nullable()();
  BoolColumn get hasPassphrase => boolean().withDefault(const Constant(false))();
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();
  TextColumn get notes => text().nullable()();
  TextColumn get providerType => text().withDefault(const Constant('none'))();
  TextColumn get providerResourceId => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastConnectedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('HostFingerprintData')
class HostFingerprints extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text()();
  TextColumn get hostnameOrIp => text()();
  IntColumn get port => integer()();
  TextColumn get fingerprint => text()();
  DateTimeColumn get acceptedAt => dateTime()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CommandTemplateData')
class CommandTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 80)();
  TextColumn get category => text()();
  TextColumn get commandText => text()();
  TextColumn get placeholdersJson => text().withDefault(const Constant('[]'))();
  BoolColumn get dangerous => boolean().withDefault(const Constant(false))();
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  TextColumn get description => text().nullable()();
  TextColumn get applicableStackJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('QuickActionData')
class QuickActions extends Table {
  TextColumn get id => text()();
  TextColumn get label => text().withLength(min: 1, max: 40)();
  TextColumn get emoji => text().nullable()();
  TextColumn get templateId => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get visible => boolean().withDefault(const Constant(true))();
  BoolColumn get isBuiltin => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AuditLogData')
class AuditLogs extends Table {
  TextColumn get id => text()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get serverId => text().nullable()();
  TextColumn get serverNickname => text().nullable()();
  TextColumn get actionType => text()();
  TextColumn get commandTemplateName => text().nullable()();
  TextColumn get rawCommand => text().nullable()();
  TextColumn get transport => text()();
  BoolColumn get success => boolean()();
  TextColumn get shortOutputSummary => text().nullable()();
  TextColumn get errorSummary => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ProviderCredentialData')
class ProviderCredentials extends Table {
  TextColumn get id => text()();
  TextColumn get providerType => text()();
  TextColumn get label => text().withLength(min: 1, max: 64)();
  TextColumn get secureStorageKey => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AppSettingData')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
