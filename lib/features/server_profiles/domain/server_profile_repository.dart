import '../../../shared/models/server_profile.dart';

abstract class ServerProfileRepository {
  Stream<List<ServerProfile>> watchAll();
  Future<List<ServerProfile>> getAll();
  Future<ServerProfile?> getById(String id);
  Future<void> upsert(ServerProfile profile);
  Future<void> delete(String id);
  Future<void> toggleFavorite(String id);
  Future<void> touchLastConnected(String id, DateTime when);
}
