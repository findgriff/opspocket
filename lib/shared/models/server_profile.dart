/// Plain-data server profile. Persisted to Drift; never contains secret bodies
/// — private key material is referenced via [secureStorageKey] and lives in
/// the OS keychain.
enum SshAuthMethod {
  privateKey,
  passwordNotStored, // user must type per-connection; not recommended
}

enum ProviderType {
  none,
  digitalOcean,
  aws,
  hetzner,
  linode,
  custom,
}

class ServerProfile {
  final String id;
  final String nickname;
  final String hostnameOrIp;
  final int port;
  final String username;
  final SshAuthMethod authMethod;

  /// Human label for the stored private key (e.g. "ops-droplet key").
  final String? privateKeyLabel;

  /// flutter_secure_storage key pointing at the PEM body.
  final String? secureStorageKey;

  /// Whether the key is passphrase-protected (passphrase also in secure storage).
  final bool hasPassphrase;

  final List<String> tags;
  final String? notes;
  final ProviderType providerType;

  /// e.g. DO droplet id, AWS instance id. Optional.
  final String? providerResourceId;

  final bool isFavorite;
  final DateTime? lastConnectedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ServerProfile({
    required this.id,
    required this.nickname,
    required this.hostnameOrIp,
    required this.port,
    required this.username,
    required this.authMethod,
    this.privateKeyLabel,
    this.secureStorageKey,
    this.hasPassphrase = false,
    this.tags = const [],
    this.notes,
    this.providerType = ProviderType.none,
    this.providerResourceId,
    this.isFavorite = false,
    this.lastConnectedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  ServerProfile copyWith({
    String? nickname,
    String? hostnameOrIp,
    int? port,
    String? username,
    SshAuthMethod? authMethod,
    String? privateKeyLabel,
    String? secureStorageKey,
    bool? hasPassphrase,
    List<String>? tags,
    String? notes,
    ProviderType? providerType,
    String? providerResourceId,
    bool? isFavorite,
    DateTime? lastConnectedAt,
    DateTime? updatedAt,
  }) {
    return ServerProfile(
      id: id,
      nickname: nickname ?? this.nickname,
      hostnameOrIp: hostnameOrIp ?? this.hostnameOrIp,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      privateKeyLabel: privateKeyLabel ?? this.privateKeyLabel,
      secureStorageKey: secureStorageKey ?? this.secureStorageKey,
      hasPassphrase: hasPassphrase ?? this.hasPassphrase,
      tags: tags ?? this.tags,
      notes: notes ?? this.notes,
      providerType: providerType ?? this.providerType,
      providerResourceId: providerResourceId ?? this.providerResourceId,
      isFavorite: isFavorite ?? this.isFavorite,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
