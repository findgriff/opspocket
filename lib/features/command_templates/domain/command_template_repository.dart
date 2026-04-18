import '../../../shared/models/command_template.dart';

abstract class CommandTemplateRepository {
  Stream<List<CommandTemplate>> watchAll();
  Future<List<CommandTemplate>> getAll();
  Future<CommandTemplate?> getById(String id);
  Future<void> upsert(CommandTemplate template);
  Future<void> delete(String id);
  Future<void> toggleFavorite(String id);

  /// Idempotent — inserts builtins if not already present.
  Future<void> seedBuiltinsIfEmpty();
}
