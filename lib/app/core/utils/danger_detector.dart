/// Detects destructive / dangerous commands by pattern. Used to gate
/// execution behind an extra confirmation step (and optionally biometrics).
///
/// This is advisory, not exhaustive — it catches common footguns so a
/// stressed user doesn't nuke a server by muscle-memory. A command can also
/// be flagged as dangerous via [CommandTemplate.dangerous].
class DangerDetector {
  DangerDetector._();

  /// Patterns that should trigger a confirmation prompt.
  static final List<RegExp> _patterns = [
    RegExp(r'\brm\s+-[a-zA-Z]*r[a-zA-Z]*f[a-zA-Z]*\b'), // rm -rf / rm -fr etc
    RegExp(r'\brm\s+-[a-zA-Z]*f[a-zA-Z]*r[a-zA-Z]*\b'),
    RegExp(r'\bmkfs\b'),
    RegExp(r'\bdd\s+if='),
    RegExp(r'>\s*/dev/sd[a-z]'),
    RegExp(r'\bshutdown\b'),
    RegExp(r'\bpoweroff\b'),
    RegExp(r'\bhalt\b'),
    RegExp(r'\breboot\b'),
    RegExp(r'\binit\s+0\b'),
    RegExp(r'\binit\s+6\b'),
    RegExp(r':\(\)\s*\{'), // fork bomb heuristic
    RegExp(r'\bchmod\s+-R\s+777\b'),
    RegExp(r'\bchown\s+-R\s+'),
    RegExp(r'\bdocker\s+system\s+prune'),
    RegExp(r'\bdocker\s+rm\s+-f\b'),
    RegExp(r'\bkubectl\s+delete\b'),
    RegExp(r'\buserdel\b'),
    RegExp(r'\bdrop\s+database\b', caseSensitive: false),
    RegExp(r'\btruncate\s+table\b', caseSensitive: false),
    RegExp(r'\bsudo\s+(rm|mkfs|dd|shutdown|poweroff|reboot|halt)\b'),
  ];

  /// Returns true if [command] matches any known dangerous pattern.
  static bool isDangerous(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return false;
    for (final p in _patterns) {
      if (p.hasMatch(trimmed)) return true;
    }
    return false;
  }

  /// Returns a human-readable reason for the danger flag, or null.
  static String? reason(String command) {
    final trimmed = command.trim();
    for (final p in _patterns) {
      if (p.hasMatch(trimmed)) {
        return 'Matches destructive pattern: ${p.pattern}';
      }
    }
    return null;
  }
}
