import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/ssh/presentation/ssh_connection_notifier.dart';
import '../../../features/ssh/domain/ssh_client.dart';
import '../domain/deploy_state.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _repo = 'https://github.com/findgriff/mission-control.git';
const _dir = '/home/clawd/mission-control';

/// Wraps a shell command so it runs as the `clawd` user with the npm-global
/// bin directory on PATH — consistent with how McRepository runs commands.
String _clawd(String cmd) =>
    """su - clawd -c 'export PATH="\$HOME/.npm-global/bin:/usr/local/bin:/usr/bin:\$PATH"; $cmd'""";

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final deployProvider = StateNotifierProvider.autoDispose
    .family<DeployNotifier, DeployState, String>(
  (ref, serverId) => DeployNotifier(ref.read(sshClientProvider(serverId))),
);

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class DeployNotifier extends StateNotifier<DeployState> {
  final SshClient _ssh;

  DeployNotifier(this._ssh) : super(DeployState.initial());

  /// Run all deploy steps sequentially. Resets state first so retries work.
  Future<void> deploy() async {
    // Reset to a clean slate each time deploy() is called (for retries).
    state = DeployState.initial().copyWith(isRunning: true);

    // ------------------------------------------------------------------
    // Step 0: Check whether the repo directory exists on the VPS.
    // ------------------------------------------------------------------
    bool firstRun;
    try {
      firstRun = await _runStep(
        index: 0,
        command: _clawd('test -d $_dir && echo exists || echo missing'),
        evaluate: (result) {
          if (!result.success) return false;
          // Treat any non-'exists' stdout as first run (covers empty output).
          return result.stdout.trim() != 'exists';
        },
      );
    } catch (_) {
      return; // _runStep already marked the step failed.
    }

    // ------------------------------------------------------------------
    // Step 1: Clone (first run) or Pull (update).
    // ------------------------------------------------------------------
    // Use fetch + reset --hard so divergent histories never block an update.
    final cloneOrPull = firstRun
        ? _clawd('cd /home/clawd && git clone $_repo')
        : _clawd('cd $_dir && git fetch origin && git reset --hard origin/main');

    if (!await _execStep(index: 1, command: cloneOrPull)) { return; }

    // ------------------------------------------------------------------
    // Step 2: npm install
    // ------------------------------------------------------------------
    if (!await _execStep(
      index: 2,
      command: _clawd('cd $_dir && npm install'),
    )) { return; }

    // ------------------------------------------------------------------
    // Step 3: npm run build  (~60–90 s)
    // ------------------------------------------------------------------
    if (!await _execStep(
      index: 3,
      command: _clawd('cd $_dir && npm run build'),
      timeout: const Duration(minutes: 5),
    )) { return; }

    // ------------------------------------------------------------------
    // Step 4: pm2 start or restart (install pm2 if not found)
    // ------------------------------------------------------------------
    if (!await _execStep(
      index: 4,
      command: _clawd(
        'which pm2 || npm install -g pm2 2>&1 && '
        'cd $_dir && (pm2 restart mission-control 2>/dev/null || '
        'pm2 start "npm start -- --port 3001" --name mission-control)',
      ),
    )) { return; }

    // ------------------------------------------------------------------
    // Step 5: pm2 save
    // ------------------------------------------------------------------
    if (!await _execStep(
      index: 5,
      command: _clawd('pm2 save --force'),
    )) { return; }

    // ------------------------------------------------------------------
    // Step 6: Nginx — ensure /mission-control proxies to port 3001.
    //         Runs as root (no su needed).
    // ------------------------------------------------------------------
    if (!await _execStep(
      index: 6,
      command: r"""
CONF=/etc/nginx/sites-available/default
if grep -q '127.0.0.1:3001' "$CONF"; then
  echo 'nginx already configured'
elif grep -q 'mission-control' "$CONF"; then
  sed -i 's|proxy_pass http://127.0.0.1:[0-9]*|proxy_pass http://127.0.0.1:3001|g' "$CONF"
  nginx -t && systemctl reload nginx && echo 'nginx updated'
else
  sed -i '/location \/ {/i\\
\tlocation = /mission-control {\\
\t\tproxy_pass http://127.0.0.1:3001;\\
\t\tproxy_http_version 1.1;\\
\t\tproxy_set_header Host $host;\\
\t\tproxy_set_header Upgrade $http_upgrade;\\
\t\tproxy_set_header Connection "upgrade";\\
\t}\\
\tlocation /mission-control/ {\\
\t\tproxy_pass http://127.0.0.1:3001;\\
\t\tproxy_http_version 1.1;\\
\t\tproxy_set_header Host $host;\\
\t\tproxy_set_header Upgrade $http_upgrade;\\
\t\tproxy_set_header Connection "upgrade";\\
\t}
' "$CONF"
  nginx -t && systemctl reload nginx && echo 'nginx configured'
fi
""",
    )) { return; }

    // All steps succeeded.
    state = state.copyWith(isRunning: false, done: true);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Runs a step, marks it running, marks it success/failure, and returns the
  /// raw evaluation result. Used for step 0 where we need to inspect stdout.
  ///
  /// Throws if the step fails (so the caller can return early).
  Future<bool> _runStep({
    required int index,
    required String command,
    required bool Function(dynamic result) evaluate,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    _markRunning(index);
    try {
      final result = await _ssh.exec(command, timeout: timeout);
      final value = evaluate(result);
      _markDone(index, success: result.success, output: result.combinedOutput());
      if (!result.success) throw Exception('step $index failed');
      return value;
    } catch (e) {
      if (state.steps[index].status != DeployStepStatus.failure) {
        _markDone(index, success: false, output: e.toString());
      }
      state = state.copyWith(isRunning: false, failed: true);
      rethrow;
    }
  }

  /// Runs a step and returns true on success, false on failure (with state
  /// already updated).
  Future<bool> _execStep({
    required int index,
    required String command,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    _markRunning(index);
    try {
      final result = await _ssh.exec(command, timeout: timeout);
      _markDone(index, success: result.success, output: result.combinedOutput());
      if (!result.success) {
        state = state.copyWith(isRunning: false, failed: true);
        return false;
      }
      return true;
    } catch (e) {
      _markDone(index, success: false, output: e.toString());
      state = state.copyWith(isRunning: false, failed: true);
      return false;
    }
  }

  void _markRunning(int index) {
    final steps = List<DeployStep>.from(state.steps);
    steps[index] = steps[index].copyWith(status: DeployStepStatus.running);
    state = state.copyWith(steps: steps);
  }

  void _markDone(int index, {required bool success, String output = ''}) {
    final steps = List<DeployStep>.from(state.steps);
    steps[index] = steps[index].copyWith(
      status: success ? DeployStepStatus.success : DeployStepStatus.failure,
      output: output,
    );
    state = state.copyWith(steps: steps);
  }
}
