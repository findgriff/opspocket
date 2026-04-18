import '../../../shared/models/quick_action.dart';

abstract class QuickActionRepository {
  Stream<List<QuickAction>> watchVisible();
  Future<List<QuickAction>> getAll();
  Future<void> upsert(QuickAction action);
  Future<void> delete(String id);
  Future<void> seedDefaultsIfEmpty();
}
