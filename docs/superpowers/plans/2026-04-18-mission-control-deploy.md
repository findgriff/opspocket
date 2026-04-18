# Mission Control One-Tap Deploy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Deploy Mission Control" tile to the server detail screen that SSHes into the VPS, clones or pulls `git@github.com:findgriff/mission-control.git`, builds the Next.js app, and starts/restarts it with pm2 — all with live step-by-step progress shown in a fullscreen deploy screen.

**Architecture:** Three new files (domain state, notifier, UI screen) follow the existing Riverpod `StateNotifier.family` pattern used throughout the app. SSH commands run sequentially via `SshClient.exec()`, each updating a list of `DeployStep` objects that drive the UI. The server detail screen gets one new `_ActionTile`.

**Tech Stack:** Flutter, Riverpod 2 (`StateNotifier.family`), `SshClient.exec()` (dartssh2 abstraction), `flutter_test`, `mocktail`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `lib/features/mission_control/domain/deploy_state.dart` | `DeployStepStatus` enum, `DeployStep` model, `DeployState` aggregate |
| Create | `lib/features/mission_control/presentation/deploy_notifier.dart` | `DeployNotifier` — drives step sequence via SSH |
| Create | `lib/features/mission_control/presentation/deploy_screen.dart` | Fullscreen deploy UI |
| Modify | `lib/features/server_profiles/presentation/server_detail_screen.dart` | Add Deploy tile + import |
| Create | `test/deploy_notifier_test.dart` | Unit tests for notifier logic |

---

## Task 1: Domain model

**Files:**
- Create: `lib/features/mission_control/domain/deploy_state.dart`

- [ ] **Step 1: Create the file**

```dart
// lib/features/mission_control/domain/deploy_state.dart

enum DeployStepStatus { pending, running, success, failure }

class DeployStep {
  final String label;
  final DeployStepStatus status;
  final String output;

  const DeployStep({
    required this.label,
    this.status = DeployStepStatus.pending,
    this.output = '',
  });

  DeployStep copyWith({DeployStepStatus? status, String? output}) => DeployStep(
        label: label,
        status: status ?? this.status,
        output: output ?? this.output,
      );
}

class DeployState {
  final List<DeployStep> steps;
  final bool isRunning;
  final bool done;
  final bool failed;

  const DeployState({
    required this.steps,
    this.isRunning = false,
    this.done = false,
    this.failed = false,
  });

  /// Index of the currently-running step, or -1 if none.
  int get activeStep =>
      steps.indexWhere((s) => s.status == DeployStepStatus.running);

  static DeployState initial() => DeployState(
        steps: const [
          DeployStep(label: 'Checking VPS'),
          DeployStep(label: 'Pulling latest code'),
          DeployStep(label: 'Installing packages'),
          DeployStep(label: 'Building'),
          DeployStep(label: 'Starting service'),
          DeployStep(label: 'Saving pm2 state'),
        ],
      );

  DeployState copyWith({
    List<DeployStep>? steps,
    bool? isRunning,
    bool? done,
    bool? failed,
  }) =>
      DeployState(
        steps: steps ?? this.steps,
        isRunning: isRunning ?? this.isRunning,
        done: done ?? this.done,
        failed: failed ?? this.failed,
      );
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/findgriff/Downloads/opspocket-main
flutter analyze lib/features/mission_control/domain/deploy_state.dart
```
Expected: no errors.

---

## Task 2: Deploy notifier — tests first

**Files:**
- Create: `test/deploy_notifier_test.dart`
- Create: `lib/features/mission_control/presentation/deploy_notifier.dart`

- [ ] **Step 1: Add mocktail to dev dependencies if not present**

Check `pubspec.yaml`. If `mocktail` is not under `dev_dependencies`, add it:
```bash
cd /Users/findgriff/Downloads/opspocket-main
flutter pub add --dev mocktail
```
Expected: `pubspec.yaml` updated, `flutter pub get` runs automatically.

- [ ] **Step 2: Write the failing tests**

```dart
// test/deploy_notifier_test.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:opspocket/features/mission_control/domain/deploy_state.dart';
import 'package:opspocket/features/mission_control/presentation/deploy_notifier.dart';
import 'package:opspocket/shared/models/command_execution_result.dart';
import 'package:opspocket/features/ssh/domain/ssh_client.dart';

class MockSshClient extends Mock implements SshClient {}

CommandExecutionResult _ok(String stdout) => CommandExecutionResult(
      command: '',
      stdout: stdout,
      stderr: '',
      exitCode: 0,
      duration: Duration.zero,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
    );

CommandExecutionResult _fail(String stderr) => CommandExecutionResult(
      command: '',
      stdout: '',
      stderr: stderr,
      exitCode: 1,
      duration: Duration.zero,
      startedAt: DateTime.now(),
      finishedAt: DateTime.now(),
    );

void main() {
  late MockSshClient ssh;
  late DeployNotifier notifier;

  setUp(() {
    ssh = MockSshClient();
    notifier = DeployNotifier(ssh);
  });

  group('DeployNotifier initial state', () {
    test('starts idle with 6 pending steps', () {
      expect(notifier.state.steps.length, 6);
      expect(notifier.state.isRunning, false);
      expect(notifier.state.done, false);
      expect(notifier.state.failed, false);
      for (final s in notifier.state.steps) {
        expect(s.status, DeployStepStatus.pending);
      }
    });
  });

  group('DeployNotifier.deploy() — first-time setup', () {
    setUp(() {
      // Step 0: check — returns 'missing'
      when(() => ssh.exec(
            any(that: contains('test -d')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('missing'));
      // Step 1: clone
      when(() => ssh.exec(
            any(that: contains('git clone')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('Cloning into mission-control...'));
      // Step 2: npm install
      when(() => ssh.exec(
            any(that: contains('npm install')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('added 300 packages'));
      // Step 3: npm run build
      when(() => ssh.exec(
            any(that: contains('npm run build')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('Build complete'));
      // Step 4: pm2 start/restart
      when(() => ssh.exec(
            any(that: contains('pm2')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('[PM2] Process started'));
    });

    test('sets done=true after all steps succeed', () async {
      await notifier.deploy();
      expect(notifier.state.done, true);
      expect(notifier.state.failed, false);
      for (final s in notifier.state.steps) {
        expect(s.status, DeployStepStatus.success);
      }
    });
  });

  group('DeployNotifier.deploy() — update (repo exists)', () {
    setUp(() {
      when(() => ssh.exec(
            any(that: contains('test -d')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('exists'));
      when(() => ssh.exec(
            any(that: contains('git pull')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('Already up to date.'));
      when(() => ssh.exec(
            any(that: contains('npm install')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('up to date'));
      when(() => ssh.exec(
            any(that: contains('npm run build')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('Build complete'));
      when(() => ssh.exec(
            any(that: contains('pm2')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('[PM2] Restarted'));
    });

    test('uses git pull not git clone when repo exists', () async {
      await notifier.deploy();
      verify(() => ssh.exec(
            any(that: contains('git pull')),
            timeout: any(named: 'timeout'),
          )).called(1);
      verifyNever(() => ssh.exec(
            any(that: contains('git clone')),
            timeout: any(named: 'timeout'),
          ));
    });
  });

  group('DeployNotifier.deploy() — failure handling', () {
    test('stops at failed step and sets failed=true', () async {
      when(() => ssh.exec(
            any(that: contains('test -d')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('exists'));
      when(() => ssh.exec(
            any(that: contains('git pull')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _fail('Permission denied (publickey)'));

      await notifier.deploy();

      expect(notifier.state.failed, true);
      expect(notifier.state.done, false);
      // Step 1 (pull) is failure
      expect(notifier.state.steps[1].status, DeployStepStatus.failure);
      // Steps after the failure remain pending
      expect(notifier.state.steps[2].status, DeployStepStatus.pending);
    });

    test('can retry after failure', () async {
      var callCount = 0;
      when(() => ssh.exec(
            any(that: contains('test -d')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? _fail('timeout') : _ok('exists');
      });
      when(() => ssh.exec(
            any(that: contains('git pull')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('up to date'));
      when(() => ssh.exec(
            any(that: contains('npm install')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('ok'));
      when(() => ssh.exec(
            any(that: contains('npm run build')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('ok'));
      when(() => ssh.exec(
            any(that: contains('pm2')),
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => _ok('ok'));

      await notifier.deploy(); // first attempt — fails
      expect(notifier.state.failed, true);

      await notifier.deploy(); // retry — succeeds
      expect(notifier.state.done, true);
    });
  });
}
```

- [ ] **Step 3: Run tests — expect failure (file not yet created)**

```bash
cd /Users/findgriff/Downloads/opspocket-main
flutter test test/deploy_notifier_test.dart
```
Expected: compilation error — `deploy_notifier.dart` not found.

- [ ] **Step 4: Create the notifier**

```dart
// lib/features/mission_control/presentation/deploy_notifier.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ssh/domain/ssh_client.dart';
import '../../ssh/presentation/ssh_connection_notifier.dart';
import '../domain/deploy_state.dart';

// Commands run as the clawd user, with npm-global on PATH
String _clawd(String cmd) =>
    """su - clawd -c 'export PATH="\$HOME/.npm-global/bin:\$PATH"; $cmd'""";

const _repo = 'git@github.com:findgriff/mission-control.git';
const _dir  = '/home/clawd/mission-control';

final deployProvider = StateNotifierProvider.autoDispose
    .family<DeployNotifier, DeployState, String>(
  (ref, serverId) => DeployNotifier(ref.read(sshClientProvider(serverId))),
);

class DeployNotifier extends StateNotifier<DeployState> {
  final SshClient _ssh;

  DeployNotifier(this._ssh) : super(DeployState.initial());

  Future<void> deploy() async {
    // Reset to initial state so retries start fresh
    state = DeployState.initial().copyWith(isRunning: true);

    try {
      // ── Step 0: Check whether repo already exists ──────────────────────
      await _run(0, _clawd('test -d $_dir && echo exists || echo missing'));
      if (state.failed) return;
      final isFirstRun = !state.steps[0].output.contains('exists');

      // ── Step 1: Clone or pull ──────────────────────────────────────────
      final cloneOrPull = isFirstRun
          ? _clawd('cd /home/clawd && git clone $_repo 2>&1')
          : _clawd('git -C $_dir pull 2>&1');
      await _run(1, cloneOrPull);
      if (state.failed) return;

      // ── Step 2: npm install ────────────────────────────────────────────
      await _run(
        2,
        _clawd('cd $_dir && npm install --omit=dev 2>&1'),
        timeout: const Duration(minutes: 3),
      );
      if (state.failed) return;

      // ── Step 3: npm run build ──────────────────────────────────────────
      await _run(
        3,
        _clawd('cd $_dir && npm run build 2>&1'),
        timeout: const Duration(minutes: 5),
      );
      if (state.failed) return;

      // ── Step 4: pm2 start or restart ──────────────────────────────────
      await _run(
        4,
        _clawd(
          '(pm2 restart mission-control 2>&1) || '
          '(pm2 start "npm start -- --port 3001" --name mission-control 2>&1)',
        ),
      );
      if (state.failed) return;

      // ── Step 5: pm2 save ───────────────────────────────────────────────
      await _run(5, _clawd('pm2 save 2>&1'));
      if (state.failed) return;

      state = state.copyWith(isRunning: false, done: true);
    } catch (e) {
      // Unexpected exception — mark current running step as failure
      final idx = state.activeStep;
      if (idx >= 0) {
        _markStep(idx, DeployStepStatus.failure, e.toString());
      }
      state = state.copyWith(isRunning: false, failed: true);
    }
  }

  Future<void> _run(
    int stepIndex,
    String command, {
    Duration timeout = const Duration(minutes: 1),
  }) async {
    _markStep(stepIndex, DeployStepStatus.running, '');

    final result = await _ssh.exec(command, timeout: timeout);
    final output = result.combinedOutput().trim();

    if (result.success) {
      _markStep(stepIndex, DeployStepStatus.success, output);
    } else {
      _markStep(stepIndex, DeployStepStatus.failure, output);
      state = state.copyWith(isRunning: false, failed: true);
    }
  }

  void _markStep(int index, DeployStepStatus status, String output) {
    final updated = List<DeployStep>.from(state.steps);
    updated[index] = updated[index].copyWith(status: status, output: output);
    state = state.copyWith(steps: updated);
  }
}
```

- [ ] **Step 5: Run tests — expect pass**

```bash
cd /Users/findgriff/Downloads/opspocket-main
flutter test test/deploy_notifier_test.dart
```
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
cd /Users/findgriff/Downloads/opspocket-main
git add lib/features/mission_control/domain/deploy_state.dart \
        lib/features/mission_control/presentation/deploy_notifier.dart \
        test/deploy_notifier_test.dart
git commit -m "feat: add DeployNotifier + DeployState for Mission Control one-tap deploy"
```

---

## Task 3: Deploy screen UI

**Files:**
- Create: `lib/features/mission_control/presentation/deploy_screen.dart`

- [ ] **Step 1: Create the screen**

```dart
// lib/features/mission_control/presentation/deploy_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/deploy_state.dart';
import '../presentation/deploy_notifier.dart';
import '../presentation/mc_screen.dart';

// ── Palette (matches MCScreen) ────────────────────────────────────────────────
const _bg      = Color(0xFF000000);
const _surface = Color(0xFF0E0E0E);
const _card    = Color(0xFF161616);
const _border  = Color(0xFF252525);
const _red     = Color(0xFFFF3B1F);
const _green   = Color(0xFF4CAF50);
const _purple  = Color(0xFFB57BFF);
const _white   = Color(0xFFFFFFFF);
const _muted   = Color(0xFF888888);
const _dimmed  = Color(0xFF3A3A3A);

class DeployScreen extends ConsumerStatefulWidget {
  final String serverId;
  final String serverName;
  const DeployScreen({super.key, required this.serverId, required this.serverName});

  @override
  ConsumerState<DeployScreen> createState() => _DeployScreenState();
}

class _DeployScreenState extends ConsumerState<DeployScreen> {
  // Track which build step output boxes are expanded
  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    // Auto-start deploy on open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(deployProvider(widget.serverId).notifier).deploy();
    });
  }

  @override
  Widget build(BuildContext context) {
    final deploy = ref.watch(deployProvider(widget.serverId));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _bg,
        body: Column(
          children: [
            _header(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                children: [
                  ...deploy.steps.asMap().entries.map(
                        (e) => _StepRow(
                          step: e.value,
                          expanded: _expanded.contains(e.key),
                          onToggle: () => setState(() {
                            if (_expanded.contains(e.key)) {
                              _expanded.remove(e.key);
                            } else {
                              _expanded.add(e.key);
                            }
                          }),
                        ),
                      ),
                  const SizedBox(height: 24),
                  if (deploy.failed) _retryButton(context),
                  if (deploy.done) _openButton(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _border)),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.close, color: _white, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _purple.withValues(alpha: 0.4)),
                ),
                child: const Icon(Icons.rocket_launch_outlined, color: _purple, size: 15),
              ),
              const SizedBox(width: 10),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'DEPLOY',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 11,
                      color: _purple,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    widget.serverName,
                    style: const TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      color: _muted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _retryButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _expanded.clear());
        ref.read(deployProvider(widget.serverId).notifier).deploy();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: _red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _red.withValues(alpha: 0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.refresh, color: _red, size: 18),
            SizedBox(width: 10),
            Text('Retry Deploy',
                style: TextStyle(color: _red, fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _openButton(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MCScreen(
              serverId: widget.serverId,
              serverName: widget.serverName,
            ),
            fullscreenDialog: true,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: _green.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _green.withValues(alpha: 0.4)),
          boxShadow: [BoxShadow(color: _green.withValues(alpha: 0.15), blurRadius: 14)],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.open_in_new, color: _green, size: 18),
            SizedBox(width: 10),
            Text('Open Mission Control',
                style: TextStyle(color: _green, fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

// ── Step row ──────────────────────────────────────────────────────────────────

class _StepRow extends StatelessWidget {
  final DeployStep step;
  final bool expanded;
  final VoidCallback onToggle;
  const _StepRow({required this.step, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _statusIcon,
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    step.label,
                    style: TextStyle(
                      color: _labelColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (step.output.isNotEmpty)
                  GestureDetector(
                    onTap: onToggle,
                    child: Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: _muted,
                    ),
                  ),
              ],
            ),
          ),
          if (expanded && step.output.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _border),
                ),
                child: SelectableText(
                  step.output,
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 11,
                    color: _muted,
                    height: 1.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color get _borderColor => switch (step.status) {
        DeployStepStatus.success => _green.withValues(alpha: 0.25),
        DeployStepStatus.failure => const Color(0xFFFF3B1F).withValues(alpha: 0.3),
        DeployStepStatus.running => _purple.withValues(alpha: 0.3),
        DeployStepStatus.pending => _border,
      };

  Color get _labelColor => switch (step.status) {
        DeployStepStatus.pending => _muted,
        _ => _white,
      };

  Widget get _statusIcon => switch (step.status) {
        DeployStepStatus.pending => const Icon(Icons.radio_button_unchecked, size: 18, color: _dimmed),
        DeployStepStatus.running => const SizedBox(
            width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: _purple),
          ),
        DeployStepStatus.success => const Icon(Icons.check_circle_outline, size: 18, color: _green),
        DeployStepStatus.failure => const Icon(Icons.cancel_outlined, size: 18, color: _red),
      };
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd /Users/findgriff/Downloads/opspocket-main
flutter analyze lib/features/mission_control/presentation/deploy_screen.dart
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add lib/features/mission_control/presentation/deploy_screen.dart
git commit -m "feat: add DeployScreen UI for Mission Control one-tap deploy"
```

---

## Task 4: Wire the tile into server detail screen

**Files:**
- Modify: `lib/features/server_profiles/presentation/server_detail_screen.dart`

- [ ] **Step 1: Add import at the top of the file**

In `server_detail_screen.dart`, add this import alongside the existing mc_screen import:

```dart
import '../../mission_control/presentation/deploy_screen.dart';
```

- [ ] **Step 2: Add the Deploy tile after the Mission Control tile**

Find this block in `server_detail_screen.dart`:
```dart
              _ActionTile(
                icon: Icons.crisis_alert,
                label: 'Mission Control',
                subtitle: 'Tasks, agents, projects, memory',
                color: const Color(0xFFFF3B1F),
                onTap: () {
                  final name = server.nickname.isNotEmpty ? server.nickname : server.hostnameOrIp;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MCScreen(serverId: serverId, serverName: name),
                      fullscreenDialog: true,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _ClawGateTile(serverId: serverId),
```

Replace with:
```dart
              _ActionTile(
                icon: Icons.crisis_alert,
                label: 'Mission Control',
                subtitle: 'Tasks, agents, projects, memory',
                color: const Color(0xFFFF3B1F),
                onTap: () {
                  final name = server.nickname.isNotEmpty ? server.nickname : server.hostnameOrIp;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MCScreen(serverId: serverId, serverName: name),
                      fullscreenDialog: true,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _ActionTile(
                icon: Icons.rocket_launch_outlined,
                label: 'Deploy Mission Control',
                subtitle: 'Pull latest from GitHub & rebuild',
                color: const Color(0xFFB57BFF),
                onTap: () {
                  final name = server.nickname.isNotEmpty ? server.nickname : server.hostnameOrIp;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeployScreen(serverId: serverId, serverName: name),
                      fullscreenDialog: true,
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _ClawGateTile(serverId: serverId),
```

- [ ] **Step 3: Verify full project compiles**

```bash
cd /Users/findgriff/Downloads/opspocket-main
flutter analyze
```
Expected: no errors (warnings about trailing commas are fine).

- [ ] **Step 4: Run all tests**

```bash
flutter test
```
Expected: all tests pass including the new `deploy_notifier_test.dart`.

- [ ] **Step 5: Commit**

```bash
git add lib/features/server_profiles/presentation/server_detail_screen.dart \
        lib/features/mission_control/presentation/deploy_screen.dart
git commit -m "feat: wire Deploy Mission Control tile into server detail screen"
```

---

## Task 5: Manual smoke test

- [ ] **Step 1: Set up VPS deploy key (one-time prerequisite)**

SSH into the VPS as clawd and run:
```bash
ssh-keygen -t ed25519 -C "clawd@vps-deploy" -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```
Copy the output. Go to:
**github.com/findgriff/mission-control → Settings → Deploy keys → Add deploy key**
Paste the key. Title: "VPS clawd deploy key". Read-only is fine.

Test it works:
```bash
ssh -T git@github.com
```
Expected: `Hi findgriff! You've successfully authenticated...`

- [ ] **Step 2: Run the app and test the happy path**

```bash
flutter run -d "iPhone 16"
```

1. Open a server → tap **Deploy Mission Control**
2. `DeployScreen` opens, all 6 steps start running
3. Each step ticks green in sequence (build takes ~90s)
4. **Open Mission Control** button appears on success
5. Tap it → `MCScreen` opens

- [ ] **Step 3: Test retry on failure**

1. Disconnect from SSH mid-deploy (toggle aeroplane mode briefly)
2. A step should turn red with error output
3. Tap **Retry** → all steps reset to pending and re-run from start

- [ ] **Step 4: Test update path**

1. Make a small change in the Mission Control web app (e.g. change a string in `src/app/tasks/page.tsx`)
2. Push to `git@github.com:findgriff/mission-control.git`
3. Tap **Deploy Mission Control** again
4. Step 1 should say "Pulling latest code" (not cloning)
5. After deploy: open Mission Control — see the change live

---

## Prerequisites Checklist

Before running the app against a real server:

- [ ] Mission Control code pushed to `git@github.com:findgriff/mission-control.git`
- [ ] VPS clawd SSH deploy key added to GitHub (Task 5 Step 1)
- [ ] Node.js + npm installed on VPS (`node --version`)
- [ ] pm2 installed globally for clawd (`pm2 --version`)
- [ ] Nginx configured with `location /mission-control { proxy_pass http://localhost:3001; }`
