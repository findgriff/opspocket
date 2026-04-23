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
    test('starts idle with 7 pending steps', () {
      expect(notifier.state.steps.length, 7);
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
      when(() => ssh.exec(
            any(that: contains('test -d')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('missing'));
      when(() => ssh.exec(
            any(that: contains('git clone')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('Cloning into mission-control...'));
      when(() => ssh.exec(
            any(that: contains('npm install')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('added 300 packages'));
      when(() => ssh.exec(
            any(that: contains('npm run build')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('Build complete'));
      when(() => ssh.exec(
            any(that: contains('pm2')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('[PM2] Process started'));
      when(() => ssh.exec(
            any(that: contains('sites-available')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('nginx reloaded'));
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
          ),).thenAnswer((_) async => _ok('exists'));
      when(() => ssh.exec(
            any(that: contains('git fetch')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('Already up to date.'));
      when(() => ssh.exec(
            any(that: contains('npm install')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('up to date'));
      when(() => ssh.exec(
            any(that: contains('npm run build')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('Build complete'));
      when(() => ssh.exec(
            any(that: contains('pm2')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('[PM2] Restarted'));
      when(() => ssh.exec(
            any(that: contains('sites-available')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('nginx reloaded'));
    });

    test('uses git fetch+reset not git clone when repo exists', () async {
      await notifier.deploy();
      verify(() => ssh.exec(
            any(that: contains('git fetch')),
            timeout: any(named: 'timeout'),
          ),).called(1);
      verifyNever(() => ssh.exec(
            any(that: contains('git clone')),
            timeout: any(named: 'timeout'),
          ),);
    });
  });

  group('DeployNotifier.deploy() — failure handling', () {
    test('stops at failed step and sets failed=true', () async {
      when(() => ssh.exec(
            any(that: contains('test -d')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('exists'));
      when(() => ssh.exec(
            any(that: contains('git fetch')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _fail('Permission denied (publickey)'));

      await notifier.deploy();

      expect(notifier.state.failed, true);
      expect(notifier.state.done, false);
      expect(notifier.state.steps[1].status, DeployStepStatus.failure);
      expect(notifier.state.steps[2].status, DeployStepStatus.pending);
    });

    test('can retry after failure', () async {
      var callCount = 0;
      when(() => ssh.exec(
            any(that: contains('test -d')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async {
        callCount++;
        return callCount == 1 ? _fail('timeout') : _ok('exists');
      });
      when(() => ssh.exec(
            any(that: contains('git fetch')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('up to date'));
      when(() => ssh.exec(
            any(that: contains('npm install')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('ok'));
      when(() => ssh.exec(
            any(that: contains('npm run build')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('ok'));
      when(() => ssh.exec(
            any(that: contains('pm2')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('ok'));
      when(() => ssh.exec(
            any(that: contains('sites-available')),
            timeout: any(named: 'timeout'),
          ),).thenAnswer((_) async => _ok('nginx reloaded'));

      await notifier.deploy();
      expect(notifier.state.failed, true);

      await notifier.deploy();
      expect(notifier.state.done, true);
    });
  });
}
