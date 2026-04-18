/// Trust-on-first-use record of an SSH host key fingerprint.
class HostFingerprintRecord {
  final String id;
  final String serverId;
  final String hostnameOrIp;
  final int port;

  /// Usually a SHA-256 fingerprint in base64 form (OpenSSH style:
  /// `SHA256:abc...`).
  final String fingerprint;

  final DateTime acceptedAt;
  final DateTime? lastSeenAt;

  const HostFingerprintRecord({
    required this.id,
    required this.serverId,
    required this.hostnameOrIp,
    required this.port,
    required this.fingerprint,
    required this.acceptedAt,
    this.lastSeenAt,
  });
}
