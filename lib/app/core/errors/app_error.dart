/// Sealed set of user-visible errors. Keep messages short and non-leaky.
sealed class AppError implements Exception {
  final String message;
  final Object? cause;
  const AppError(this.message, {this.cause});

  @override
  String toString() => '$runtimeType($message)';
}

class ValidationError extends AppError {
  const ValidationError(super.message);
}

class SshAuthError extends AppError {
  const SshAuthError(super.message, {super.cause});
}

class SshTimeoutError extends AppError {
  const SshTimeoutError(super.message, {super.cause});
}

class SshUnreachableError extends AppError {
  const SshUnreachableError(super.message, {super.cause});
}

class HostFingerprintMismatchError extends AppError {
  final String expected;
  final String actual;
  const HostFingerprintMismatchError({
    required this.expected,
    required this.actual,
  }) : super('Host key fingerprint mismatch');
}

class HostFingerprintUnknownError extends AppError {
  final String fingerprint;
  const HostFingerprintUnknownError(this.fingerprint)
      : super('Host key not yet trusted');
}

class ProviderApiError extends AppError {
  final int? statusCode;
  const ProviderApiError(super.message, {this.statusCode, super.cause});
}

class BiometricUnavailableError extends AppError {
  const BiometricUnavailableError([super.msg = 'Biometrics unavailable']);
}

class BiometricDeniedError extends AppError {
  const BiometricDeniedError([super.msg = 'Biometric authentication denied']);
}

class SecureStorageError extends AppError {
  const SecureStorageError(super.message, {super.cause});
}

class NoNetworkError extends AppError {
  const NoNetworkError() : super('No network connection');
}

class UnknownAppError extends AppError {
  const UnknownAppError([super.msg = 'Unknown error']);
}
