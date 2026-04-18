import 'server_profile.dart';

/// Metadata for a stored provider API token. Actual token body lives in
/// flutter_secure_storage under [secureStorageKey].
class ProviderCredential {
  final String id;
  final ProviderType providerType;

  /// Human label, e.g. "DO main account".
  final String label;

  final String secureStorageKey;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  const ProviderCredential({
    required this.id,
    required this.providerType,
    required this.label,
    required this.secureStorageKey,
    required this.createdAt,
    this.lastUsedAt,
  });
}
