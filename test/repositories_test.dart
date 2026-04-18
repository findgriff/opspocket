import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opspocket/features/audit/data/audit_repository_impl.dart';
import 'package:opspocket/features/command_templates/data/command_template_repository_impl.dart';
import 'package:opspocket/features/quick_actions/data/quick_action_repository_impl.dart';
import 'package:opspocket/features/server_profiles/data/server_profile_repository_impl.dart';
import 'package:opspocket/shared/database/app_database.dart';
import 'package:opspocket/shared/models/server_profile.dart';

import 'secure_storage_fake_test.dart' show InMemorySecureStorage;

AppDatabase _testDb() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('ServerProfileRepository', () {
    late AppDatabase db;
    late ServerProfileRepositoryImpl repo;

    setUp(() {
      db = _testDb();
      repo = ServerProfileRepositoryImpl(db, InMemorySecureStorage());
    });
    tearDown(() async => db.close());

    test('upsert + getById round-trip', () async {
      final now = DateTime.now();
      await repo.upsert(ServerProfile(
        id: 's1',
        nickname: 'prod',
        hostnameOrIp: '1.2.3.4',
        port: 22,
        username: 'root',
        authMethod: SshAuthMethod.privateKey,
        createdAt: now,
        updatedAt: now,
        tags: const ['prod', 'bot'],
      ),);
      final out = await repo.getById('s1');
      expect(out, isNotNull);
      expect(out!.nickname, 'prod');
      expect(out.tags, ['prod', 'bot']);
    });

    test('toggleFavorite flips flag', () async {
      final now = DateTime.now();
      await repo.upsert(ServerProfile(
        id: 's2',
        nickname: 'n',
        hostnameOrIp: 'h',
        port: 22,
        username: 'u',
        authMethod: SshAuthMethod.privateKey,
        createdAt: now,
        updatedAt: now,
      ),);
      await repo.toggleFavorite('s2');
      expect((await repo.getById('s2'))!.isFavorite, isTrue);
      await repo.toggleFavorite('s2');
      expect((await repo.getById('s2'))!.isFavorite, isFalse);
    });

    test('delete removes the row', () async {
      final now = DateTime.now();
      await repo.upsert(ServerProfile(
        id: 's3',
        nickname: 'n',
        hostnameOrIp: 'h',
        port: 22,
        username: 'u',
        authMethod: SshAuthMethod.privateKey,
        createdAt: now,
        updatedAt: now,
      ),);
      await repo.delete('s3');
      expect(await repo.getById('s3'), isNull);
    });
  });

  group('CommandTemplateRepository', () {
    test('seedBuiltinsIfEmpty inserts all built-ins', () async {
      final db = _testDb();
      addTearDown(() async => db.close());
      final repo = CommandTemplateRepositoryImpl(db);
      await repo.seedBuiltinsIfEmpty();
      final all = await repo.getAll();
      expect(all, isNotEmpty);
      // Rerun is idempotent.
      await repo.seedBuiltinsIfEmpty();
      final second = await repo.getAll();
      expect(second.length, all.length);
    });
  });

  group('QuickActionRepository', () {
    test('seedDefaultsIfEmpty inserts defaults once', () async {
      final db = _testDb();
      addTearDown(() async => db.close());
      final repo = QuickActionRepositoryImpl(db);
      await repo.seedDefaultsIfEmpty();
      final all = await repo.getAll();
      expect(all.length, greaterThanOrEqualTo(6));
      await repo.seedDefaultsIfEmpty();
      final second = await repo.getAll();
      expect(second.length, all.length);
    });
  });

  group('AuditRepository', () {
    test('log + getAll ordered desc by timestamp', () async {
      final db = _testDb();
      addTearDown(() async => db.close());
      final repo = AuditRepositoryImpl(db);
      await repo.log(
        actionType: 'runCommand',
        transport: 'ssh',
        success: true,
        rawCommand: 'echo 1',
      );
      // Drift stores DateTime as unix seconds by default, so we wait past a
      // second boundary to guarantee a distinct timestamp for ordering.
      await Future.delayed(const Duration(milliseconds: 1100));
      await repo.log(
        actionType: 'runCommand',
        transport: 'ssh',
        success: false,
        rawCommand: 'echo 2',
        errorSummary: 'boom',
      );
      final all = await repo.getAll();
      expect(all.length, 2);
      expect(all.first.rawCommand, 'echo 2');
    });

    test('clearAll wipes entries', () async {
      final db = _testDb();
      addTearDown(() async => db.close());
      final repo = AuditRepositoryImpl(db);
      await repo.log(actionType: 'runCommand', transport: 'ssh', success: true);
      await repo.clearAll();
      expect(await repo.getAll(), isEmpty);
    });
  });
}
