import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/database/app_database.dart';
import '../../../shared/database/mappers.dart';
import '../../../shared/models/command_template.dart';
import '../../../shared/providers/db_providers.dart';
import '../domain/command_template_repository.dart';
import 'builtin_templates.dart';

class CommandTemplateRepositoryImpl implements CommandTemplateRepository {
  final AppDatabase _db;
  CommandTemplateRepositoryImpl(this._db);

  @override
  Stream<List<CommandTemplate>> watchAll() {
    final q = _db.select(_db.commandTemplates)
      ..orderBy([
        (t) => OrderingTerm.desc(t.isFavorite),
        (t) => OrderingTerm.desc(t.isBuiltin),
        (t) => OrderingTerm.asc(t.name),
      ]);
    return q.watch().map((rows) => rows.map((r) => r.toModel()).toList());
  }

  @override
  Future<List<CommandTemplate>> getAll() async {
    final rows = await _db.select(_db.commandTemplates).get();
    return rows.map((r) => r.toModel()).toList();
  }

  @override
  Future<CommandTemplate?> getById(String id) async {
    final row = await (_db.select(_db.commandTemplates)..where((t) => t.id.equals(id))).getSingleOrNull();
    return row?.toModel();
  }

  @override
  Future<void> upsert(CommandTemplate template) async {
    await _db.into(_db.commandTemplates).insertOnConflictUpdate(commandTemplateToCompanion(template));
  }

  @override
  Future<void> delete(String id) async {
    await (_db.delete(_db.commandTemplates)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> toggleFavorite(String id) async {
    final t = await getById(id);
    if (t == null) return;
    await upsert(t.copyWith(isFavorite: !t.isFavorite, updatedAt: DateTime.now()));
  }

  @override
  Future<void> seedBuiltinsIfEmpty() async {
    // Always upsert builtins so new templates are added on upgrade.
    // Safe because IDs are stable and isBuiltin=true prevents user deletion.
    final now = DateTime.now();
    for (final t in BuiltinTemplates.all(now)) {
      await upsert(t);
    }
  }
}

final commandTemplateRepositoryProvider = Provider<CommandTemplateRepository>((ref) {
  return CommandTemplateRepositoryImpl(ref.watch(appDatabaseProvider));
});

final commandTemplatesStreamProvider = StreamProvider<List<CommandTemplate>>((ref) {
  return ref.watch(commandTemplateRepositoryProvider).watchAll();
});
