import '../../../shared/models/server_profile.dart';

/// Result from a provider-side instance query.
class ProviderInstanceStatus {
  final String id;
  final String name;
  final String status;
  final String? region;
  final List<String> ipv4;

  const ProviderInstanceStatus({
    required this.id,
    required this.name,
    required this.status,
    this.region,
    this.ipv4 = const [],
  });
}

/// Provider-side actions we can perform as an SSH fallback. Keep this tiny —
/// recovery first, admin tooling later.
abstract class ProviderApi {
  ProviderType get type;

  Future<ProviderInstanceStatus> getStatus({required String resourceId});
  Future<void> reboot({required String resourceId});
  Future<void> powerCycle({required String resourceId});
}
