/// Result of running a command over SSH (or via a provider API).
class CommandExecutionResult {
  final String command;
  final String stdout;
  final String stderr;
  final int? exitCode;
  final Duration duration;
  final DateTime startedAt;
  final DateTime finishedAt;
  final bool timedOut;

  const CommandExecutionResult({
    required this.command,
    required this.stdout,
    required this.stderr,
    this.exitCode,
    required this.duration,
    required this.startedAt,
    required this.finishedAt,
    this.timedOut = false,
  });

  bool get success => !timedOut && (exitCode == 0);

  String combinedOutput() {
    if (stderr.isEmpty) return stdout;
    if (stdout.isEmpty) return stderr;
    return '$stdout\n--- stderr ---\n$stderr';
  }
}
