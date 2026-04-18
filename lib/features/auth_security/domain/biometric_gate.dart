/// Interface for biometric / device-auth confirmation. Concrete impl wraps
/// local_auth so tests can fake it.
abstract class BiometricGate {
  /// True if any biometric (or device credential fallback) is usable.
  Future<bool> isAvailable();

  /// Prompts the user. [reason] is shown in the system prompt. Returns true
  /// on successful auth.
  Future<bool> authenticate({required String reason});
}
