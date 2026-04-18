import '../../../shared/models/host_fingerprint_record.dart';

abstract class HostFingerprintRepository {
  Future<HostFingerprintRecord?> getForServer(String serverId);
  Future<void> upsert(HostFingerprintRecord record);
  Future<void> deleteForServer(String serverId);
}
