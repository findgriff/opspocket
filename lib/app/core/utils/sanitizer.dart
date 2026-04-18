/// Redacts secrets from strings before logging or display. Cheap, best-effort;
/// never treat this as a security boundary, only as defense-in-depth so
/// incidental logging doesn't leak tokens.
class Sanitizer {
  Sanitizer._();

  static final List<RegExp> _secretPatterns = [
    // DigitalOcean personal access tokens start with "dop_v1_".
    RegExp(r'\bdop_v1_[A-Fa-f0-9]{40,}\b'),
    // Generic bearer tokens in headers.
    RegExp(r'(authorization:\s*bearer\s+)[A-Za-z0-9\-_\.=]+', caseSensitive: false),
    // Generic API key assignments.
    RegExp(r'(api[_-]?key|token|secret|password)\s*[:=]\s*([^\s]+)', caseSensitive: false),
    // OpenSSH private key bodies.
    RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]+?-----END [A-Z ]*PRIVATE KEY-----'),
    // AWS access key pattern.
    RegExp(r'\bAKIA[0-9A-Z]{16}\b'),
    // GitHub tokens.
    RegExp(r'\bgh[pousr]_[A-Za-z0-9]{20,}\b'),
  ];

  /// Returns a sanitized copy of [input].
  static String sanitize(String input) {
    var out = input;
    for (final p in _secretPatterns) {
      out = out.replaceAllMapped(p, (m) {
        final prefix = m.groupCount >= 1 ? (m.group(1) ?? '') : '';
        if (prefix.isNotEmpty) {
          return '$prefix[REDACTED]';
        }
        return '[REDACTED]';
      });
    }
    return out;
  }

  /// Truncates [input] to at most [maxChars] and sanitizes it.
  static String summarise(String input, {int maxChars = 500}) {
    final s = sanitize(input);
    if (s.length <= maxChars) return s;
    return '${s.substring(0, maxChars)}... [truncated]';
  }
}
